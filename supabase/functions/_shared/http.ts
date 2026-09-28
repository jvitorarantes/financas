// Utilidades HTTP das Edge Functions: CORS, respostas JSON, autenticação e
// erros amigáveis (nunca devolvem stack trace ou detalhe interno).

import { createClient, type SupabaseClient, type User } from "@supabase/supabase-js";

const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_ORIGIN") ?? "*";

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

/** Mensagens exibidas ao usuário final. */
export const FRIENDLY_MESSAGES = {
  unauthorized: "Sua sessão expirou. Entre novamente.",
  invalid_request: "Não foi possível processar o pedido.",
  audio_too_long: "O áudio pode ter no máximo 60 segundos.",
  audio_too_large: "O áudio ficou grande demais. Tente uma gravação mais curta.",
  unsupported_audio: "Formato de áudio não suportado.",
  transcription_failed: "Não conseguimos entender o áudio. Tente novamente.",
  empty_transcription: "Não conseguimos entender o áudio. Tente novamente.",
  extraction_failed: "Não conseguimos interpretar a movimentação. Preencha os dados manualmente.",
  rate_limited: "Muitas tentativas em pouco tempo. Aguarde alguns minutos.",
  session_not_found: "Gravação não encontrada. Grave novamente.",
  internal: "Algo deu errado. Tente novamente.",
} as const;
export type ErrorCode = keyof typeof FRIENDLY_MESSAGES;

export class AppError extends Error {
  code: ErrorCode;
  status: number;
  constructor(code: ErrorCode, status = 400) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

export function errorResponse(err: unknown): Response {
  if (err instanceof AppError) {
    return json({ error: { code: err.code, message: FRIENDLY_MESSAGES[err.code] } }, err.status);
  }
  // Registra o detalhe só no log do servidor.
  console.error("unexpected_error", err instanceof Error ? err.stack ?? err.message : err);
  return json({ error: { code: "internal", message: FRIENDLY_MESSAGES.internal } }, 500);
}

export interface AuthContext {
  supabase: SupabaseClient; // cliente com o JWT do usuário: o RLS vale
  user: User;
}

/** Valida o JWT do usuário e devolve um cliente que respeita o RLS. */
export async function authenticate(req: Request): Promise<AuthContext> {
  const header = req.headers.get("Authorization") ?? "";
  if (!header.startsWith("Bearer ")) throw new AppError("unauthorized", 401);
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: header } }, auth: { persistSession: false } },
  );
  const { data, error } = await supabase.auth.getUser(header.slice(7));
  if (error || !data.user) throw new AppError("unauthorized", 401);
  return { supabase, user: data.user };
}

/** Cliente de serviço (ignora RLS) — usar só para gravações do backend. */
export function serviceClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
}

/** Data de hoje no fuso de São Paulo (YYYY-MM-DD). */
export function todayInBrazil(now = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(now);
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export const isUuid = (v: unknown): v is string => typeof v === "string" && UUID.test(v);

/** Limite simples: no máximo `max` sessões de áudio por hora por usuário. */
export async function enforceAudioRateLimit(ctx: AuthContext, max = 60): Promise<void> {
  const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { count, error } = await ctx.supabase
    .from("audio_sessions")
    .select("id", { count: "exact", head: true })
    .gte("created_at", since);
  if (!error && (count ?? 0) >= max) throw new AppError("rate_limited", 429);
}
