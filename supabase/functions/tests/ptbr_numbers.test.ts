import { test } from "node:test";
import assert from "node:assert/strict";
import {
  analyzeAmounts, formatBRL, normalizeNumbers, parseDigitsToCents, splitInstallments,
} from "../_shared/ptbr_numbers.ts";

test("números por extenso viram algarismos", () => {
  assert.equal(normalizeNumbers("recebi três mil e duzentos de salário"), "recebi 3200 de salário");
  assert.equal(normalizeNumbers("paguei cento e cinquenta de gasolina"), "paguei 150 de gasolina");
  assert.equal(normalizeNumbers("dois mil e quatrocentos em doze vezes"), "2400 em 12 vezes");
  assert.equal(normalizeNumbers("gastei quarenta e cinco reais"), "gastei 45 reais");
  assert.equal(normalizeNumbers("mil reais"), "1000 reais");
  assert.equal(normalizeNumbers("um milhão e duzentos mil"), "1200000");
  assert.equal(normalizeNumbers("2,5 mil de bônus"), "2500 de bônus");
  assert.equal(normalizeNumbers("cem reais"), "100 reais");
});

test("'um' como artigo não vira número", () => {
  assert.equal(normalizeNumbers("comprei um lanche de 20 reais"), "comprei um lanche de 20 reais");
  assert.equal(normalizeNumbers("um real"), "1 real");
});

test("algarismos no formato brasileiro", () => {
  assert.equal(parseDigitsToCents("1.200,50"), 120050);
  assert.equal(parseDigitsToCents("3.200"), 320000);
  assert.equal(parseDigitsToCents("45"), 4500);
  assert.equal(parseDigitsToCents("12,5"), 1250);
  assert.equal(parseDigitsToCents("12.5"), 1250);
  assert.equal(parseDigitsToCents("0,01"), 1);
  assert.equal(parseDigitsToCents("1,234"), null);
});

test("quantias da fala", () => {
  assert.equal(analyzeAmounts("Gastei 85 reais de gasolina hoje no cartão.").best, 8500);
  assert.equal(analyzeAmounts("Recebi 3200 reais de salário hoje.").best, 320000);
  assert.equal(analyzeAmounts("recebi três mil e duzentos de salário").best, 320000);
  assert.equal(analyzeAmounts("Paguei R$ 180,90 de energia").best, 18090);
  assert.equal(analyzeAmounts("oitenta e cinco reais e cinquenta centavos").best, 8550);
  assert.equal(analyzeAmounts("Gastei dinheiro no mercado.").best, null);
});

test("parcelas não são confundidas com valor", () => {
  const a = analyzeAmounts("Comprei uma televisão de 2400 reais em 12 vezes.");
  assert.equal(a.best, 240000);
  assert.equal(a.installments, 12);
  const b = analyzeAmounts("comprei uma televisão de dois mil e quatrocentos em doze vezes");
  assert.equal(b.best, 240000);
  assert.equal(b.installments, 12);
  assert.equal(analyzeAmounts("geladeira de 3000 em 10x").installments, 10);
});

test("dia do mês não é valor", () => {
  const a = analyzeAmounts("paguei 150 de aluguel no dia 5");
  assert.equal(a.best, 15000);
  assert.deepEqual(a.amounts, [15000]);
});

test("correção de valor é detectada", () => {
  const a = analyzeAmounts("Gastei 150... não, 115 reais no mercado.");
  assert.equal(a.corrected, true);
  assert.equal(a.best, 11500);
  assert.deepEqual(a.amounts, [15000, 11500]);
});

test("dois valores sem correção é ambíguo", () => {
  const a = analyzeAmounts("gastei 50 reais no mercado e 30 reais na padaria");
  assert.equal(a.ambiguous, true);
  assert.equal(a.best, null);
});

test("formatação e divisão de parcelas em centavos", () => {
  assert.equal(formatBRL(320050), "R$ 3.200,50");
  assert.equal(formatBRL(5), "R$ 0,05");
  assert.equal(formatBRL(-123456789), "-R$ 1.234.567,89");
  assert.deepEqual(splitInstallments(240000, 12), Array(12).fill(20000));
  assert.deepEqual(splitInstallments(10000, 3), [3334, 3333, 3333]);
  const parts = splitInstallments(99999, 7);
  assert.equal(parts.reduce((s, p) => s + p, 0), 99999);
});
