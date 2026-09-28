// POST /functions/v1/transcribe-audio  (multipart/form-data)
//   audio: arquivo (até 60 s), session_id: uuid gerado no app, duration_ms
// Resposta: { session_id, transcription }

import {
  AppError, authenticate, corsHeaders, enforceAudioRateLimit, errorResponse, isUuid, json,
} from "../_shared/http.ts";
import { transcribe } from "../_shared/stt.ts";

const MAX_BYTES = 5 * 1024 * 1024;
const MAX_DURATION_MS = 60_500; // 60 s + tolerância do relógio do aparelho
const AUDIO_TYPES = /^audio\/(?:mp4|m4a|x-m4a|aac|mpeg|mp3|webm|ogg|wav|x-wav)/;
const AUDIO_EXT = /\.(?:m4a|mp4|aac|mp3|webm|ogg|wav)$/i;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return errorResponse(new AppError("invalid_request", 405));

  let sessionId: string | null = null;
  let ctx: Awaited<ReturnType<typeof authenticate>> | null = null;
  try {
    ctx = await authenticate(req);
    const form = await req.formData().catch(() => { throw new AppError("invalid_request"); });
    const audio = form.get("audio");
    sessionId = String(form.get("session_id") ?? "");
    const durationMs = Number(form.get("duration_ms") ?? 0);

    if (!isUuid(sessionId) || !(audio instanceof File)) throw new AppError("invalid_request");
    if (!Number.isFinite(durationMs) || durationMs > MAX_DURATION_MS) throw new AppError("audio_too_long");
    if (audio.size === 0) throw new AppError("empty_transcription", 422);
    if (audio.size > MAX_BYTES) throw new AppError("audio_too_large", 413);
    if (!AUDIO_TYPES.test(audio.type) && !AUDIO_EXT.test(audio.name)) throw new AppError("unsupported_audio", 415);

    // A sessão precisa ser nova ou do próprio usuário (o RLS garante) e não
    // pode já ter virado lançamento.
    const { data: existing } = await ctx.supabase
      .from("audio_sessions").select("status").eq("id", sessionId).maybeSingle();
    if (existing?.status === "completed") throw new AppError("invalid_request", 409);
    if (!existing) await enforceAudioRateLimit(ctx);

    const { error: upsertError } = await ctx.supabase.from("audio_sessions").upsert({
      id: sessionId,
      user_id: ctx.user.id,
      status: "transcribing",
      duration_ms: Math.max(0, Math.min(60_000, Math.round(durationMs))),
      error_code: null,
    }, { onConflict: "id" });
    if (upsertError) throw new AppError("session_not_found", 404);

    const transcription = await transcribe(audio);

    await ctx.supabase.from("audio_sessions")
      .update({ status: "extracting", transcription })
      .eq("id", sessionId);

    // O áudio não é guardado: só a transcrição fica registrada.
    return json({ session_id: sessionId, transcription });
  } catch (err) {
    if (ctx && isUuid(sessionId)) {
      const code = err instanceof AppError ? err.code : "internal";
      await ctx.supabase.from("audio_sessions")
        .update({ status: "failed", error_code: code })
        .eq("id", sessionId).neq("status", "completed");
    }
    return errorResponse(err);
  }
});
