// Transcrição de áudio (Speech-to-Text) em português do Brasil.
//
// Provedores (a chave fica SOMENTE no backend, como secret):
//   * GROQ_API_KEY   → Groq, Whisper large v3 turbo (tem plano gratuito)
//   * OPENAI_API_KEY → OpenAI, gpt-4o-transcribe (pago)
// Se as duas existirem, usa o Groq. STT_MODEL troca o modelo.

import { AppError } from "./http.ts";

const VOCABULARY_HINT =
  "Registro financeiro falado em português do Brasil. Ex.: gastei 45 reais no almoço; " +
  "recebi três mil e duzentos de salário; paguei R$ 180,90 de energia; comprei em 12 vezes no cartão; pix; débito.";

export async function transcribe(audio: File): Promise<string> {
  const groqKey = Deno.env.get("GROQ_API_KEY");
  const apiKey = groqKey ?? Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) throw new AppError("transcription_failed", 503);
  const endpoint = groqKey
    ? "https://api.groq.com/openai/v1/audio/transcriptions"
    : "https://api.openai.com/v1/audio/transcriptions";
  const defaultModel = groqKey ? "whisper-large-v3-turbo" : "gpt-4o-transcribe";

  const form = new FormData();
  form.append("file", audio, audio.name || "audio.m4a");
  form.append("model", Deno.env.get("STT_MODEL") ?? defaultModel);
  form.append("language", "pt");
  form.append("prompt", VOCABULARY_HINT);
  form.append("response_format", "json");

  const res = await fetch(endpoint, {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}` },
    body: form,
    signal: AbortSignal.timeout(45_000),
  });
  if (res.status === 429) throw new AppError("rate_limited", 429);
  if (!res.ok) {
    console.error("stt_error", res.status, (await res.text()).slice(0, 500));
    throw new AppError("transcription_failed", 502);
  }
  const body = await res.json() as { text?: string };
  const text = (body.text ?? "").replace(/\s+/g, " ").trim();
  if (text.length < 2) throw new AppError("empty_transcription", 422);
  return text.slice(0, 2000);
}
