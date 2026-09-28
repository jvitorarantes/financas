import { test } from "node:test";
import assert from "node:assert/strict";
import { allowedNumbers, computeInsights, type InsightInput, isGrounded, monthlyEquivalentCents } from "../_shared/insights.ts";

const base: InsightInput = {
  month: "2026-09-01",
  previousMonth: "2026-08-01",
  today: "2026-09-28",
  totals: [
    { month: "2026-09-01", type: "expense", category_id: "1", category_name: "Delivery", total_cents: 62000, tx_count: 9 },
    { month: "2026-09-01", type: "expense", category_id: "2", category_name: "Transporte", total_cents: 30000, tx_count: 4 },
    { month: "2026-09-01", type: "income", category_id: "3", category_name: "Salário", total_cents: 500000, tx_count: 1 },
    { month: "2026-08-01", type: "expense", category_id: "1", category_name: "Delivery", total_cents: 39000, tx_count: 6 },
    { month: "2026-08-01", type: "expense", category_id: "2", category_name: "Transporte", total_cents: 31000, tx_count: 4 },
  ],
  budgets: [{ category_name: "Alimentação", limit_cents: 100000, spent_cents: 82000 }],
  recurring: [{ description: "Aluguel", amount_cents: 150000, frequency: "monthly", interval_count: 1 }],
};

test("insights usam somente números reais", () => {
  const list = computeInsights(base);
  const kinds = list.map((i) => i.kind);
  assert.ok(kinds.includes("top_category"));
  assert.ok(kinds.includes("category_increase"));
  assert.ok(kinds.includes("budget_near_limit"));
  assert.ok(kinds.includes("recurring"));
  assert.ok(kinds.includes("savings_opportunity"));
  const inc = list.find((i) => i.kind === "category_increase")!;
  assert.equal(inc.body, "Você gastou R$ 620,00 com Delivery até agora neste mês, contra R$ 390,00 no mês anterior.");
  assert.deepEqual(inc.metrics, { current_cents: 62000, previous_cents: 39000, category: "Delivery" });
  const budget = list.find((i) => i.kind === "budget_near_limit")!;
  assert.match(budget.body, /82% do orçamento de Alimentação/);
  const savings = list.find((i) => i.kind === "savings_opportunity")!;
  assert.match(savings.body, /R\$ 230,00/);
});

test("sem dados: não inventa análise", () => {
  const list = computeInsights({ ...base, totals: [], budgets: [], recurring: [] });
  assert.equal(list.length, 1);
  assert.equal(list[0].kind, "no_data");
});

test("texto da IA com número inexistente é recusado", () => {
  const list = computeInsights(base);
  const allowed = allowedNumbers(list);
  assert.equal(isGrounded("Delivery subiu de R$ 390,00 para R$ 620,00.", allowed), true);
  assert.equal(isGrounded("Você usou 82% do orçamento.", allowed), true);
  assert.equal(isGrounded("Você pode economizar R$ 777,00 por mês.", allowed), false);
  assert.equal(isGrounded("Seus gastos subiram 57%.", allowed), false);
});

test("equivalente mensal de recorrências", () => {
  assert.equal(monthlyEquivalentCents({ description: "", amount_cents: 12000, frequency: "yearly", interval_count: 1 }), 1000);
  assert.equal(monthlyEquivalentCents({ description: "", amount_cents: 12000, frequency: "monthly", interval_count: 2 }), 6000);
  assert.equal(monthlyEquivalentCents({ description: "", amount_cents: 1200, frequency: "weekly", interval_count: 1 }), 5200);
});
