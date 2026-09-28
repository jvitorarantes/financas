// Análises financeiras calculadas SOMENTE a partir dos dados do usuário.
// Cada insight carrega os números que o originaram (`metrics`), para o app
// mostrar de onde veio a conclusão. A IA, quando usada, só reescreve estes
// insights; qualquer número que ela cite e que não esteja nos dados é recusado.

import { formatBRL } from "./ptbr_numbers.ts";

export interface MonthlyTotalRow {
  month: string; // YYYY-MM-01
  type: "income" | "expense";
  category_id: string | null;
  category_name: string;
  total_cents: number;
  tx_count: number;
}

export interface BudgetRow {
  category_name: string;
  limit_cents: number;
  spent_cents: number;
}

export interface RecurringRow {
  description: string;
  amount_cents: number;
  frequency: "weekly" | "monthly" | "yearly";
  interval_count: number;
}

export interface Insight {
  kind: string;
  severity: "info" | "warning" | "positive";
  title: string;
  body: string;
  metrics: Record<string, number | string>;
}

export interface InsightInput {
  month: string;         // mês analisado (YYYY-MM-01)
  previousMonth: string; // mês anterior (YYYY-MM-01)
  today: string;         // YYYY-MM-DD
  totals: MonthlyTotalRow[];
  budgets: BudgetRow[];
  recurring: RecurringRow[];
}

const pct = (part: number, whole: number) => (whole === 0 ? 0 : Math.round((part / whole) * 100));

function byCategory(rows: MonthlyTotalRow[], month: string, type: "income" | "expense") {
  const map = new Map<string, number>();
  for (const r of rows) {
    if (r.month !== month || r.type !== type) continue;
    map.set(r.category_name, (map.get(r.category_name) ?? 0) + Number(r.total_cents));
  }
  return map;
}

const sum = (m: Map<string, number>) => [...m.values()].reduce((a, b) => a + b, 0);

/** Valor mensal equivalente de uma recorrência (semanal ≈ 52/12 por mês). */
export function monthlyEquivalentCents(r: RecurringRow): number {
  const n = Math.max(1, r.interval_count);
  if (r.frequency === "weekly") return Math.round((r.amount_cents * 52) / 12 / n);
  if (r.frequency === "yearly") return Math.round(r.amount_cents / 12 / n);
  return Math.round(r.amount_cents / n);
}

export function computeInsights(input: InsightInput): Insight[] {
  const insights: Insight[] = [];
  const cur = byCategory(input.totals, input.month, "expense");
  const prev = byCategory(input.totals, input.previousMonth, "expense");
  const curIncome = sum(byCategory(input.totals, input.month, "income"));
  const curTotal = sum(cur);
  const prevTotal = sum(prev);
  const partial = input.today.slice(0, 7) === input.month.slice(0, 7);
  const soFar = partial ? " até agora" : "";

  if (curTotal === 0 && prevTotal === 0 && curIncome === 0) {
    return [{
      kind: "no_data",
      severity: "info",
      title: "Ainda não há dados suficientes",
      body: "Registre suas receitas e despesas para receber análises do seu mês.",
      metrics: {},
    }];
  }

  // 1. Categorias que mais consomem
  const top = [...cur.entries()].sort((a, b) => b[1] - a[1]).slice(0, 3);
  if (top.length > 0 && curTotal > 0) {
    const [name, value] = top[0];
    insights.push({
      kind: "top_category",
      severity: "info",
      title: `${name} é o seu maior gasto`,
      body: `Você gastou ${formatBRL(value)} com ${name}${soFar} neste mês, ${pct(value, curTotal)}% do total de ${formatBRL(curTotal)}.` +
        (top.length > 1
          ? ` Em seguida vêm ${top.slice(1).map(([n, v]) => `${n} (${formatBRL(v)})`).join(" e ")}.`
          : ""),
      metrics: Object.fromEntries([
        ["total_expense_cents", curTotal],
        ...top.map(([n, v]) => [`category:${n}`, v]),
      ]),
    });
  }

  // 2. Total do mês contra o anterior
  if (prevTotal > 0 && curTotal > 0) {
    const change = pct(curTotal - prevTotal, prevTotal);
    insights.push({
      kind: "month_over_month",
      severity: change > 10 && !partial ? "warning" : change < 0 ? "positive" : "info",
      title: change >= 0 ? "Gastos do mês em relação ao anterior" : "Seus gastos diminuíram",
      body: `Suas despesas${soFar} somam ${formatBRL(curTotal)}, contra ${formatBRL(prevTotal)} no mês anterior` +
        ` (${change >= 0 ? "+" : ""}${change}%).`,
      metrics: { current_cents: curTotal, previous_cents: prevTotal, change_percent: change },
    });
  }

  // 3. Categorias que aumentaram / diminuíram
  const changes = [...new Set([...cur.keys(), ...prev.keys()])].map((name) => ({
    name, now: cur.get(name) ?? 0, before: prev.get(name) ?? 0,
  }));
  const increased = changes
    .filter((c) => c.before > 0 && c.now - c.before >= 5000 && c.now >= c.before * 1.2)
    .sort((a, b) => (b.now - b.before) - (a.now - a.before));
  for (const c of increased.slice(0, 2)) {
    insights.push({
      kind: "category_increase",
      severity: "warning",
      title: `${c.name} aumentou`,
      body: `Você gastou ${formatBRL(c.now)} com ${c.name}${soFar} neste mês, contra ${formatBRL(c.before)} no mês anterior.`,
      metrics: { current_cents: c.now, previous_cents: c.before, category: c.name },
    });
  }
  const decreased = changes
    .filter((c) => !partial && c.before - c.now >= 5000 && c.now <= c.before * 0.8)
    .sort((a, b) => (b.before - b.now) - (a.before - a.now));
  for (const c of decreased.slice(0, 1)) {
    insights.push({
      kind: "category_decrease",
      severity: "positive",
      title: `Você economizou em ${c.name}`,
      body: `Foram ${formatBRL(c.now)} com ${c.name} neste mês, contra ${formatBRL(c.before)} no mês anterior.`,
      metrics: { current_cents: c.now, previous_cents: c.before, category: c.name },
    });
  }

  // 4. Orçamentos próximos do limite
  for (const b of input.budgets) {
    const used = pct(b.spent_cents, b.limit_cents);
    if (used < 80) continue;
    insights.push({
      kind: "budget_near_limit",
      severity: "warning",
      title: used >= 100 ? `Orçamento de ${b.category_name} estourado` : `Orçamento de ${b.category_name} perto do limite`,
      body: `Você já utilizou ${used}% do orçamento de ${b.category_name}: ${formatBRL(b.spent_cents)} de ${formatBRL(b.limit_cents)}.`,
      metrics: { spent_cents: b.spent_cents, limit_cents: b.limit_cents, used_percent: used },
    });
  }

  // 5. Gastos recorrentes
  const recurringExpenses = input.recurring.filter((r) => r.amount_cents > 0);
  if (recurringExpenses.length > 0) {
    const monthly = recurringExpenses.reduce((s, r) => s + monthlyEquivalentCents(r), 0);
    insights.push({
      kind: "recurring",
      severity: "info",
      title: "Seus gastos fixos",
      body: `Você tem ${recurringExpenses.length} despesa(s) recorrente(s), que somam cerca de ${formatBRL(monthly)} por mês.` +
        (curIncome > 0 ? ` Isso equivale a ${pct(monthly, curIncome)}% das receitas deste mês (${formatBRL(curIncome)}).` : ""),
      metrics: { monthly_recurring_cents: monthly, count: recurringExpenses.length, income_cents: curIncome },
    });
  }

  // 6. Oportunidade de economia (baseada no maior aumento)
  if (increased.length > 0) {
    const c = increased[0];
    insights.push({
      kind: "savings_opportunity",
      severity: "info",
      title: "Oportunidade de economia",
      body: `Se ${c.name} voltar ao valor do mês anterior (${formatBRL(c.before)}), você deixa de gastar ${formatBRL(c.now - c.before)}.`,
      metrics: { potential_savings_cents: c.now - c.before, previous_cents: c.before, current_cents: c.now },
    });
  }

  // 7. Receitas x despesas
  if (curIncome > 0) {
    const balance = curIncome - curTotal;
    insights.push({
      kind: "income_vs_expense",
      severity: balance >= 0 ? "positive" : "warning",
      title: balance >= 0 ? "Sobrou dinheiro no mês" : "Despesas acima das receitas",
      body: `Receitas de ${formatBRL(curIncome)} e despesas de ${formatBRL(curTotal)}${soFar}: ` +
        (balance >= 0
          ? `sobra de ${formatBRL(balance)} (${pct(balance, curIncome)}% das receitas).`
          : `faltam ${formatBRL(-balance)}.`),
      metrics: { income_cents: curIncome, expense_cents: curTotal, balance_cents: balance },
    });
  }

  return insights;
}

// ---------------------------------------------------------------------------
// Conferência de texto gerado por IA: todo valor em R$ e todo percentual
// citados precisam existir nos dados.
// ---------------------------------------------------------------------------
export function allowedNumbers(insights: Insight[]): { money: Set<string>; percents: Set<number> } {
  const money = new Set<string>();
  const percents = new Set<number>();
  for (const i of insights) {
    for (const m of i.body.matchAll(/R\$ [\d.]+,\d{2}/g)) money.add(m[0]);
    for (const m of i.body.matchAll(/([+-]?\d+)%/g)) percents.add(Math.abs(Number(m[1])));
    for (const [k, v] of Object.entries(i.metrics)) {
      if (typeof v !== "number") continue;
      if (k.endsWith("_cents") || k.startsWith("category:")) money.add(formatBRL(v));
      if (k.endsWith("_percent")) percents.add(Math.abs(v));
    }
  }
  return { money, percents };
}

export function isGrounded(text: string, allowed: { money: Set<string>; percents: Set<number> }): boolean {
  for (const m of text.matchAll(/R\$\s?[\d.]+(?:,\d{2})?/g)) {
    const normalized = m[0].replace(/R\$\s?/, "R$ ").replace(/^(R\$ [\d.]+)$/, "$1,00");
    if (!allowed.money.has(normalized)) return false;
  }
  for (const m of text.matchAll(/(\d+(?:,\d+)?)\s?%/g)) {
    const value = Number(m[1].replace(",", "."));
    if (![...allowed.percents].some((p) => Math.abs(p - value) <= 1)) return false;
  }
  return true;
}
