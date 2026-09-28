// POST /functions/v1/extract-transaction  (JSON)
//   { session_id }  → interpreta a transcrição salva dessa sessão de áudio
//   { text }        → interpreta um texto digitado (sem sessão)
// Resposta: { session_id, transcription, extraction, used_ai }
// Nada é salvo como lançamento aqui: o app mostra a tela de confirmação.

import { AppError, authenticate, corsHeaders, errorResponse, isUuid, json, todayInBrazil } from "../_shared/http.ts";
import { heuristicExtract, type UserContext, validateExtraction } from "../_shared/extraction.ts";
import { extractWithClaude } from "../_shared/claude.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return errorResponse(new AppError("invalid_request", 405));

  let sessionId: string | null = null;
  let ctx: Awaited<ReturnType<typeof authenticate>> | null = null;
  try {
    ctx = await authenticate(req);
    const body = await req.json().catch(() => { throw new AppError("invalid_request"); }) as
      { session_id?: unknown; text?: unknown };

    let transcript: string;
    if (body.session_id !== undefined) {
      if (!isUuid(body.session_id)) throw new AppError("invalid_request");
      sessionId = body.session_id;
      const { data: session } = await ctx.supabase
        .from("audio_sessions").select("status, transcription").eq("id", sessionId).maybeSingle();
      if (!session?.transcription) throw new AppError("session_not_found", 404);
      if (session.status === "completed") throw new AppError("invalid_request", 409);
      transcript = session.transcription;
      await ctx.supabase.from("audio_sessions").update({ status: "extracting" }).eq("id", sessionId);
    } else {
      if (typeof body.text !== "string" || body.text.trim().length < 2 || body.text.length > 500) {
        throw new AppError("invalid_request");
      }
      transcript = body.text.trim();
    }

    const [{ data: categories }, { data: accounts }] = await Promise.all([
      ctx.supabase.from("categories").select("name, kind").eq("archived", false),
      ctx.supabase.from("accounts").select("name").eq("archived", false),
    ]);
    const userCtx: UserContext = {
      today: todayInBrazil(),
      categories: (categories ?? []) as UserContext["categories"],
      accounts: (accounts ?? []).map((a: { name: string }) => a.name),
    };

    const fromAi = await extractWithClaude(transcript, userCtx);
    const extraction = validateExtraction(fromAi ?? heuristicExtract(transcript, userCtx.today), transcript, userCtx);

    if (sessionId) {
      await ctx.supabase.from("audio_sessions")
        .update({ status: "needs_review", extraction, error_code: null })
        .eq("id", sessionId);
    }
    return json({ session_id: sessionId, transcription: transcript, extraction, used_ai: fromAi !== null });
  } catch (err) {
    if (ctx && sessionId) {
      await ctx.supabase.from("audio_sessions")
        .update({ status: "failed", error_code: err instanceof AppError ? err.code : "extraction_failed" })
        .eq("id", sessionId).neq("status", "completed");
    }
    return errorResponse(err);
  }
});
