// POST /functions/v1/financial-insights  (JSON)  { month?: "YYYY-MM" }
// Calcula as análises do mês a partir dos dados do usuário, pede ao Claude
// uma redação amigável (opcional) e só aceita textos cujos números existam
// nos dados. Resposta: { month, insights: [{ kind, severity, title, body, metrics }] }

import { AppError, authenticate, corsHeaders, errorResponse, json, serviceClient, todayInBrazil } from "../_shared/http.ts";
import { allowedNumbers, computeInsights, type Insight, isGrounded } from "../_shared/insights.ts";
import { narrateInsights } from "../_shared/claude.ts";

function monthBounds(month: string) {
  const [y, m] = month.split("-").map(Number);
  const iso = (yy: number, mm: number, dd: number) =>
    `${yy}-${String(mm).padStart(2, "0")}-${String(dd).padStart(2, "0")}`;
  const lastDay = new Date(Date.UTC(y, m, 0)).getUTCDate();
  const prevY = m === 1 ? y - 1 : y;
  const prevM = m === 1 ? 12 : m - 1;
  return { start: iso(y, m, 1), end: iso(y, m, lastDay), prevStart: iso(prevY, prevM, 1) };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return errorResponse(new AppError("invalid_request", 405));
  try {
    const ctx = await authenticate(req);
    const body = await req.json().catch(() => ({})) as { month?: unknown };
    const today = todayInBrazil();
    const month = typeof body.month === "string" ? body.month : today.slice(0, 7);
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) throw new AppError("invalid_request");
    const { start, end, prevStart } = monthBounds(month);

    const [totals, budgets, recurring] = await Promise.all([
      ctx.supabase.rpc("monthly_category_totals", { p_from: prevStart, p_to: end }),
      ctx.supabase.rpc("budget_status", { p_month: start }),
      ctx.supabase.from("recurring_transactions")
        .select("description, amount_cents, frequency, interval_count")
        .eq("active", true).eq("type", "expense"),
    ]);
    if (totals.error || budgets.error || recurring.error) throw new Error("query_failed");

    const computed = computeInsights({
      month: start,
      previousMonth: prevStart,
      today,
      totals: totals.data ?? [],
      budgets: budgets.data ?? [],
      recurring: recurring.data ?? [],
    });

    // Redação da IA: aceita só o que é sustentado pelos números calculados.
    let insights: Insight[] = computed;
    const narrated = await narrateInsights(computed);
    if (narrated) {
      const allowed = allowedNumbers(computed);
      const pool = [...computed];
      const merged: Insight[] = [];
      for (const n of narrated) {
        const idx = pool.findIndex((c) => c.kind === n.kind);
        if (idx < 0) continue;
        const [source] = pool.splice(idx, 1);
        merged.push(isGrounded(`${n.title} ${n.body}`, allowed)
          ? { ...source, title: n.title.slice(0, 120), body: n.body.slice(0, 400) }
          : source);
      }
      insights = [...merged, ...pool];
    }

    // Guarda o histórico (gravação feita pelo backend).
    const admin = serviceClient();
    await admin.from("ai_insights").delete().eq("user_id", ctx.user.id).eq("month", start);
    if (insights.length > 0) {
      await admin.from("ai_insights").insert(insights.map((i) => ({
        user_id: ctx.user.id, month: start, kind: i.kind, severity: i.severity,
        title: i.title, body: i.body, metrics: i.metrics,
      })));
    }
    return json({ month: start, insights });
  } catch (err) {
    return errorResponse(err);
  }
});
