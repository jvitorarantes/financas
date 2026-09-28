// Números em português do Brasil: por extenso ("três mil e duzentos") e em
// algarismos ("R$ 1.200,50"). Tudo em centavos inteiros para não haver erro de
// arredondamento com ponto flutuante.

const UNITS: Record<string, number> = {
  zero: 0, um: 1, uma: 1, dois: 2, duas: 2, tres: 3, quatro: 4, cinco: 5,
  seis: 6, sete: 7, oito: 8, nove: 9, dez: 10, onze: 11, doze: 12, treze: 13,
  catorze: 14, quatorze: 14, quinze: 15, dezesseis: 16, dezasseis: 16,
  dezessete: 17, dezoito: 18, dezenove: 19,
  vinte: 20, trinta: 30, quarenta: 40, cinquenta: 50, sessenta: 60,
  setenta: 70, oitenta: 80, noventa: 90,
  cem: 100, cento: 100, duzentos: 200, duzentas: 200, trezentos: 300,
  trezentas: 300, quatrocentos: 400, quatrocentas: 400, quinhentos: 500,
  quinhentas: 500, seiscentos: 600, seiscentas: 600, setecentos: 700,
  setecentas: 700, oitocentos: 800, oitocentas: 800, novecentos: 900,
  novecentas: 900,
};
const MULTIPLIERS: Record<string, number> = {
  mil: 1_000, milhao: 1_000_000, milhoes: 1_000_000,
};

/** Remove acentos e passa para minúsculas (para comparar palavras). */
export function fold(text: string): string {
  return text.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

interface Token {
  text: string; // como está no texto
  word: string; // sem acento, minúsculo
  start: number;
  end: number;
}

function tokenize(text: string): Token[] {
  const tokens: Token[] = [];
  const re = /R\$|\d+(?:[.,]\d+)*|[A-Za-zÀ-ÿ]+/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    tokens.push({ text: m[0], word: fold(m[0]), start: m.index, end: m.index + m[0].length });
  }
  return tokens;
}

/**
 * Converte um número escrito com algarismos no formato brasileiro para
 * centésimos (1.200,50 → 120050). Aceita também "12.5" (vindo de transcrição
 * em formato inglês) quando o grupo após o ponto não tem 3 dígitos.
 */
export function parseDigitsToCents(raw: string): number | null {
  const s = raw.trim();
  if (!/^\d+(?:[.,]\d+)*$/.test(s)) return null;
  let intPart = s;
  let decPart = "";
  const lastComma = s.lastIndexOf(",");
  if (lastComma >= 0) {
    intPart = s.slice(0, lastComma).replace(/\./g, "");
    decPart = s.slice(lastComma + 1);
    if (intPart.includes(",")) return null;
  } else if (s.includes(".")) {
    const groups = s.split(".");
    const thousands = groups.slice(1).every((g) => g.length === 3);
    if (thousands) {
      intPart = groups.join("");
    } else if (groups.length === 2) {
      intPart = groups[0];
      decPart = groups[1];
    } else {
      return null;
    }
  }
  if (decPart.length > 2) return null;
  const cents = Number(intPart) * 100 + Number((decPart + "00").slice(0, 2));
  return Number.isSafeInteger(cents) ? cents : null;
}

const NUMBERISH = (w: string) => w in UNITS || w in MULTIPLIERS;
const CONTEXT_AFTER_UM = new Set([
  "mil", "milhao", "real", "reais", "vez", "vezes", "parcela", "parcelas", "conto", "contos",
]);

/**
 * Troca números por extenso por algarismos, preservando o resto do texto:
 * "recebi três mil e duzentos de salário" → "recebi 3200 de salário".
 * "2,5 mil" → "2500". "um almoço" continua "um almoço" (artigo, não número).
 */
export function normalizeNumbers(text: string): string {
  const tokens = tokenize(text);
  let out = "";
  let cursor = 0;
  let i = 0;
  while (i < tokens.length) {
    const t = tokens[i];
    const startsWithDigits = /^\d/.test(t.text);
    const digitThenMultiplier =
      startsWithDigits && i + 1 < tokens.length && tokens[i + 1].word in MULTIPLIERS;
    if (!NUMBERISH(t.word) && !digitThenMultiplier) {
      i++;
      continue;
    }

    // Consome a sequência numérica: palavras numéricas ligadas por "e".
    let total = 0;
    let current = 0;
    let j = i;
    let lastEnd = t.end;
    let fractional = false;
    if (digitThenMultiplier) {
      const cents = parseDigitsToCents(t.text);
      if (cents === null) { i++; continue; }
      const mult = MULTIPLIERS[tokens[i + 1].word];
      const value = (cents * mult) / 100;
      fractional = !Number.isInteger(value);
      total += value;
      lastEnd = tokens[i + 1].end;
      j = i + 2;
    }
    while (j < tokens.length) {
      const w = tokens[j].word;
      if (w in UNITS) {
        current += UNITS[w];
        lastEnd = tokens[j].end;
        j++;
      } else if (w in MULTIPLIERS) {
        total += (current || 1) * MULTIPLIERS[w];
        current = 0;
        lastEnd = tokens[j].end;
        j++;
      } else if (w === "e" && j + 1 < tokens.length && NUMBERISH(tokens[j + 1].word)) {
        j++;
      } else {
        break;
      }
    }
    const value = total + current;

    // "um"/"uma" sozinho costuma ser artigo ("um almoço").
    const single = j === i + 1 && (t.word === "um" || t.word === "uma");
    const nextWord = j < tokens.length ? tokens[j].word : "";
    if ((single && !CONTEXT_AFTER_UM.has(nextWord)) || fractional) {
      i = j;
      continue;
    }

    out += text.slice(cursor, t.start) + String(value);
    cursor = lastEnd;
    i = j;
  }
  return out + text.slice(cursor);
}

export interface NumberMention {
  /** Valor em centavos (para quantias) ou inteiro (para parcelas/dias ×100). */
  cents: number;
  start: number;
  end: number;
  /** Tem marcador explícito de dinheiro (R$, reais, real, conto…). */
  explicitMoney: boolean;
  role: "money" | "installments" | "date" | "other";
}

const MONEY_AFTER = /^\s*(?:reais|real|conto|contos|pila|pilas)\b/i;
const CENTS_AFTER = /^\s*(?:reais|real)?\s*e\s+(\d{1,2})\s*centavos?\b/i;
const INSTALLMENTS_AFTER = /^\s*(?:x\b|vezes\b|parcelas?\b|prestac(?:oes|ao)\b|prestaç(?:ões|ão)\b)/i;
const DATE_BEFORE = /\bdia\s*$/i;
const DATE_SHAPE = /^\s*\/\s*\d{1,2}/;

/**
 * Encontra os números de um texto já normalizado (algarismos) e classifica
 * cada um: dinheiro, número de parcelas, dia do mês ou outro.
 */
export function findNumbers(normalized: string): NumberMention[] {
  const mentions: NumberMention[] = [];
  const re = /(R\$\s*)?(\d+(?:[.,]\d+)*)(x\b)?/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(normalized)) !== null) {
    const raw = m[2];
    const numStart = m.index + (m[1]?.length ?? 0);
    const before = normalized.slice(0, m.index);
    const after = normalized.slice(numStart + raw.length);
    const prevChar = normalized[m.index - 1] ?? "";
    // Parte de uma data dd/mm/aaaa?
    if (prevChar === "/" || DATE_SHAPE.test(after)) {
      mentions.push({ cents: 0, start: m.index, end: re.lastIndex, explicitMoney: false, role: "date" });
      continue;
    }
    let cents = parseDigitsToCents(raw);
    if (cents === null) continue;
    let end = numStart + raw.length;

    if (m[3] || INSTALLMENTS_AFTER.test(after)) {
      mentions.push({ cents, start: m.index, end: re.lastIndex, explicitMoney: false, role: "installments" });
      continue;
    }
    if (DATE_BEFORE.test(before)) {
      mentions.push({ cents, start: m.index, end, explicitMoney: false, role: "date" });
      continue;
    }
    let explicit = Boolean(m[1]) || MONEY_AFTER.test(after);
    const centsMatch = CENTS_AFTER.exec(after);
    if (centsMatch && cents % 100 === 0) {
      cents += Number(centsMatch[1]);
      end += centsMatch[0].length;
      explicit = true;
    }
    mentions.push({ cents, start: m.index, end, explicitMoney: explicit, role: "money" });
  }
  return mentions;
}

const CORRECTION = /\b(?:nao|quer dizer|digo|alias|ou melhor|na verdade|corrigindo|errei)\b/;

export interface AmountAnalysis {
  /** Todas as quantias citadas, em ordem. */
  amounts: number[];
  /** Quantia mais provável (a última após uma correção, ou a única). */
  best: number | null;
  /** O usuário se corrigiu ("150... não, 115") — pedir confirmação. */
  corrected: boolean;
  /** Mais de uma quantia sem correção — ambíguo. */
  ambiguous: boolean;
  installments: number | null;
}

export function analyzeAmounts(text: string): AmountAnalysis {
  const normalized = normalizeNumbers(text);
  const mentions = findNumbers(normalized);
  const money = mentions.filter((m) => m.role === "money");
  const inst = mentions.find((m) => m.role === "installments");
  const installments = inst ? Math.round(inst.cents / 100) : null;

  // Se houver quantias com marcador explícito, números soltos que não foram
  // citados numa correção são ignorados ("2 pizzas de 40 reais").
  let candidates = money;
  const hasExplicit = money.some((m) => m.explicitMoney);

  let corrected = false;
  for (let k = 1; k < money.length; k++) {
    const between = fold(normalized.slice(money[k - 1].end, money[k].start));
    if (CORRECTION.test(between)) corrected = true;
  }
  if (!corrected && hasExplicit) candidates = money.filter((m) => m.explicitMoney);

  const amounts = candidates.map((m) => m.cents).filter((c) => c > 0);
  const distinct = [...new Set(amounts)];
  let best: number | null = null;
  if (corrected) best = amounts[amounts.length - 1] ?? null;
  else if (distinct.length === 1) best = distinct[0];

  return {
    amounts,
    best,
    corrected,
    ambiguous: !corrected && distinct.length > 1,
    installments: installments !== null && installments >= 2 && installments <= 120 ? installments : null,
  };
}

/** Formata centavos como moeda brasileira: 320050 → "R$ 3.200,50". */
export function formatBRL(cents: number): string {
  const negative = cents < 0;
  const abs = Math.abs(Math.round(cents));
  const reais = Math.floor(abs / 100).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  const c = String(abs % 100).padStart(2, "0");
  return `${negative ? "-" : ""}R$ ${reais},${c}`;
}

/** Divide um total em parcelas; a diferença de centavos vai na primeira. */
export function splitInstallments(totalCents: number, count: number): number[] {
  const base = Math.floor(totalCents / count);
  const rest = totalCents - base * count;
  return Array.from({ length: count }, (_, i) => (i === 0 ? base + rest : base));
}
