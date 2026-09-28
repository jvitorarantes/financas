import { test } from "node:test";
import assert from "node:assert/strict";
import { resolveDate } from "../_shared/ptbr_dates.ts";

const TODAY = "2026-09-28"; // segunda-feira

test("datas relativas", () => {
  assert.equal(resolveDate("gastei 45 no almoço hoje", TODAY).date, "2026-09-28");
  assert.equal(resolveDate("ontem gastei 80 reais no mercado", TODAY).date, "2026-09-27");
  assert.equal(resolveDate("anteontem paguei o uber", TODAY).date, "2026-09-26");
  assert.equal(resolveDate("vou pagar amanhã", TODAY).date, "2026-09-29");
  assert.equal(resolveDate("paguei há 3 dias", TODAY).date, "2026-09-25");
});

test("sem menção de data assume hoje e avisa que não achou", () => {
  const r = resolveDate("gastei 45 reais no almoço", TODAY);
  assert.equal(r.date, TODAY);
  assert.equal(r.matched, null);
});

test("dia do mês no passado e no futuro", () => {
  assert.equal(resolveDate("paguei o aluguel dia 5", TODAY).date, "2026-09-05");
  assert.equal(resolveDate("paguei dia 30", TODAY).date, "2026-08-30");
  assert.equal(resolveDate("a conta de luz vence dia 10", TODAY).date, "2026-10-10");
  assert.equal(resolveDate("recebi dia cinco de agosto", TODAY).date, "2026-08-05");
});

test("dd/mm", () => {
  assert.equal(resolveDate("paguei em 12/09", TODAY).date, "2026-09-12");
  assert.equal(resolveDate("gastei 15/12", TODAY).date, "2025-12-15");
  assert.equal(resolveDate("vence 05/01/2027", TODAY).date, "2027-01-05");
});

test("dias da semana", () => {
  assert.equal(resolveDate("sexta passada gastei 50", TODAY).date, "2026-09-25");
  assert.equal(resolveDate("gastei 50 no sábado", TODAY).date, "2026-09-26");
  assert.equal(resolveDate("vou pagar na quarta que vem", TODAY).date, "2026-09-30");
});
