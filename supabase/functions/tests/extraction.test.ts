import { test } from "node:test";
import assert from "node:assert/strict";
import { heuristicExtract, type RawExtraction, type UserContext, validateExtraction } from "../_shared/extraction.ts";

const ctx: UserContext = {
  today: "2026-09-28",
  accounts: ["Conta corrente", "Poupança", "Carteira"],
  categories: [
    ...["Alimentação", "Moradia", "Transporte", "Saúde", "Lazer", "Compras", "Educação", "Contas", "Outros"]
      .map((name) => ({ name, kind: "expense" as const })),
    ...["Salário", "Freelance", "Investimentos", "Outras receitas"].map((name) => ({ name, kind: "income" as const })),
  ],
};

function raw(partial: Partial<RawExtraction>): RawExtraction {
  return {
    type: null, amount: null, description: null, category: null, date: null, account: null,
    destination_account: null, payment_method: null, installments: null, recurring: false, notes: null,
    confidence: 0.9, missing_fields: [], requires_clarification: false, clarification_question: null,
    ...partial,
  };
}

const run = (text: string, partial?: Partial<RawExtraction>) =>
  validateExtraction(partial ? raw(partial) : heuristicExtract(text, ctx.today), text, ctx);

test("gasolina no cartão", () => {
  const e = run("Gastei 85 reais de gasolina hoje no cartão.");
  assert.equal(e.type, "expense");
  assert.equal(e.amount_cents, 8500);
  assert.equal(e.amount, 85);
  assert.equal(e.description, "Gasolina");
  assert.equal(e.category, "Transporte");
  assert.equal(e.date, "2026-09-28");
  assert.equal(e.payment_method, "credit_card");
  assert.equal(e.requires_clarification, false);
});

test("almoço hoje", () => {
  const e = run("Gastei 45 reais no almoço hoje.");
  assert.deepEqual([e.type, e.amount_cents, e.description, e.category, e.payment_method],
    ["expense", 4500, "Almoço", "Alimentação", null]);
});

test("salário", () => {
  const e = run("Recebi 3200 reais de salário hoje.");
  assert.deepEqual([e.type, e.amount_cents, e.description, e.category], ["income", 320000, "Salário", "Salário"]);
});

test("salário por extenso", () => {
  assert.equal(run("recebi três mil e duzentos de salário").amount_cents, 320000);
});

test("energia", () => {
  const e = run("Paguei 180 reais de energia.");
  assert.deepEqual([e.type, e.amount_cents, e.category], ["expense", 18000, "Contas"]);
});

test("ontem no mercado", () => {
  const e = run("ontem gastei 80 reais no mercado");
  assert.deepEqual([e.date, e.amount_cents, e.category], ["2026-09-27", 8000, "Alimentação"]);
});

test("transferência entre contas próprias nunca vira despesa", () => {
  const text = "Mandei 200 reais da minha conta corrente para a poupança.";
  const e = run(text);
  assert.equal(e.type, "transfer");
  assert.equal(e.amount_cents, 20000);
  assert.equal(e.account, "Conta corrente");
  assert.equal(e.destination_account, "Poupança");
  assert.equal(e.category, null);
  // Mesmo que a IA erre e diga "expense", a regra corrige.
  const fromAi = run(text, { type: "expense", amount: 200, description: "Poupança" });
  assert.equal(fromAi.type, "transfer");
  assert.equal(fromAi.category, null);
});

test("televisão parcelada", () => {
  const e = run("Comprei uma televisão de 2400 reais em 12 vezes.");
  assert.equal(e.type, "expense");
  assert.equal(e.amount_cents, 240000);
  assert.equal(e.installments, 12);
  assert.equal(e.installment_amount_cents, 20000);
  assert.equal(e.first_installment_amount_cents, 20000);
  assert.equal(e.category, "Compras");
  const extenso = run("comprei uma televisão de dois mil e quatrocentos em doze vezes");
  assert.equal(extenso.amount_cents, 240000);
  assert.equal(extenso.installments, 12);
});

test("sem valor: pergunta e não inventa", () => {
  const e = run("Gastei dinheiro no mercado.");
  assert.equal(e.amount_cents, null);
  assert.equal(e.requires_clarification, true);
  assert.ok(e.missing_fields.includes("amount"));
  assert.equal(e.questions[0], "Qual foi o valor?");
});

test("IA inventou um valor que não foi dito: descartado", () => {
  const e = run("Gastei dinheiro no mercado.", { type: "expense", amount: 50, description: "Mercado" });
  assert.equal(e.amount_cents, null);
  assert.equal(e.questions[0], "Qual foi o valor?");
});

test("IA errou o valor dito: descartado", () => {
  const e = run("Gastei 85 reais de gasolina", { type: "expense", amount: 58, description: "Gasolina" });
  assert.equal(e.amount_cents, null);
  assert.equal(e.requires_clarification, true);
});

test("pagamento a pessoa sem motivo: pergunta o motivo", () => {
  const e = run("Paguei 120 reais para João.", { type: "expense", amount: 120, description: "Pagamento para João" });
  assert.equal(e.amount_cents, 12000);
  assert.equal(e.requires_clarification, true);
  assert.ok(e.questions.includes("Esse pagamento foi referente a quê?"));
});

test("correção de valor: pede confirmação", () => {
  const e = run("Gastei 150... não, 115 reais no mercado.", { type: "expense", amount: 150, description: "Mercado" });
  assert.equal(e.amount_cents, 11500);
  assert.equal(e.requires_clarification, true);
  assert.match(e.questions[0], /R\$ 150,00.*R\$ 115,00/);
});

test("tipo ambíguo: pergunta", () => {
  const e = run("200 reais do João", { type: null, amount: 200 });
  assert.equal(e.type, null);
  assert.ok(e.questions.includes("Isso foi uma receita, uma despesa ou uma transferência?"));
});

test("data inventada pela IA sem menção na fala vira hoje", () => {
  const e = run("Gastei 45 reais no almoço", { type: "expense", amount: 45, description: "Almoço", date: "2026-09-20" });
  assert.equal(e.date, "2026-09-28");
});

test("categoria que não existe no cadastro não é aceita", () => {
  const e = run("Gastei 30 reais com o cachorro", { type: "expense", amount: 30, description: "Pet shop", category: "Pets" });
  assert.equal(e.category, null);
});

test("categoria da IA é aceita quando existe (sem acento/maiúscula)", () => {
  const e = run("Gastei 30 reais na feira", { type: "expense", amount: 30, description: "Feira", category: "alimentacao" });
  assert.equal(e.category, "Alimentação");
});

test("valor absurdo é recusado", () => {
  const e = run("gastei 5000000000 reais", { type: "expense", amount: 5_000_000_000, description: "x" });
  assert.equal(e.amount_cents, null);
});

test("receita não é parcelada", () => {
  const e = run("recebi 1200 reais em 3 vezes de freela", { type: "income", amount: 1200, description: "Freela", installments: 3 });
  assert.equal(e.installments, null);
});
