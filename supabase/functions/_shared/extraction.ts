// Interpretação de uma fala em um lançamento financeiro.
//
// A IA propõe os campos; este módulo CONFERE a proposta contra a própria
// transcrição antes de devolvê-la ao app:
//   * valor que não aparece na fala é descartado (a IA nunca inventa valor);
//   * correções ("150... não, 115") sempre pedem confirmação;
//   * data sem menção na fala vira "hoje";
//   * categoria/conta só valem se existirem no cadastro do usuário;
//   * transferência entre contas próprias nunca vira receita/despesa.
// O mesmo módulo tem um interpretador por regras (sem IA), usado como reserva.

import { analyzeAmounts, fold, formatBRL, splitInstallments } from "./ptbr_numbers.ts";
import { parseISODate, resolveDate } from "./ptbr_dates.ts";

export const TRANSACTION_TYPES = ["income", "expense", "transfer"] as const;
export type TransactionType = typeof TRANSACTION_TYPES[number];

export const PAYMENT_METHODS = [
  "cash", "debit_card", "credit_card", "pix", "bank_slip", "bank_transfer", "other",
] as const;
export type PaymentMethod = typeof PAYMENT_METHODS[number];

/** O que a IA (ou o interpretador por regras) devolve. */
export interface RawExtraction {
  type: TransactionType | null;
  amount: number | null; // em reais
  description: string | null;
  category: string | null;
  date: string | null; // YYYY-MM-DD
  account: string | null;
  destination_account: string | null;
  payment_method: PaymentMethod | null;
  installments: number | null;
  recurring: boolean;
  notes: string | null;
  confidence: number;
  missing_fields: string[];
  requires_clarification: boolean;
  clarification_question: string | null;
}

/** O que o app recebe, já conferido. */
export interface Extraction {
  type: TransactionType | null;
  amount: number | null;
  amount_cents: number | null;
  description: string | null;
  category: string | null;
  date: string;
  account: string | null;
  destination_account: string | null;
  payment_method: PaymentMethod | null;
  installments: number | null;
  installment_amount_cents: number | null;
  first_installment_amount_cents: number | null;
  recurring: boolean;
  notes: string;
  confidence: number;
  missing_fields: string[];
  requires_clarification: boolean;
  questions: string[];
}

export interface UserContext {
  today: string; // YYYY-MM-DD, data local do usuário
  categories: Array<{ name: string; kind: "income" | "expense" }>;
  accounts: string[];
}

const MAX_AMOUNT_CENTS = 100_000_000_000; // R$ 1 bilhão

// ---------------------------------------------------------------------------
// Palavras-chave (descrição + categoria sugerida)
// ---------------------------------------------------------------------------
const KEYWORDS: Array<[RegExp, string, string]> = [
  [/\balmoc(?:o|ei)\b/, "Almoço", "Alimentação"],
  [/\bjant(?:a|ar|ei)\b/, "Jantar", "Alimentação"],
  [/\blanche\b/, "Lanche", "Alimentação"],
  [/\b(?:super)?mercado\b/, "Mercado", "Alimentação"],
  [/\bpadaria\b/, "Padaria", "Alimentação"],
  [/\brestaurante\b/, "Restaurante", "Alimentação"],
  [/\b(?:ifood|delivery)\b/, "Delivery", "Alimentação"],
  [/\bpizza\b/, "Pizza", "Alimentação"],
  [/\bcafe\b/, "Café", "Alimentação"],
  [/\bfeira\b/, "Feira", "Alimentação"],
  [/\bgasolina\b|\babasteci\b|\bcombustivel\b|\betanol\b/, "Gasolina", "Transporte"],
  [/\buber\b/, "Uber", "Transporte"],
  [/\bonibus\b|\bmetro\b|\bpassagem\b/, "Transporte público", "Transporte"],
  [/\bestacionamento\b/, "Estacionamento", "Transporte"],
  [/\bpedagio\b/, "Pedágio", "Transporte"],
  [/\baluguel\b/, "Aluguel", "Moradia"],
  [/\bcondominio\b/, "Condomínio", "Moradia"],
  [/\biptu\b/, "IPTU", "Moradia"],
  [/\b(?:energia|luz)\b/, "Energia", "Contas"],
  [/\bconta de agua\b|\bagua\b/, "Água", "Contas"],
  [/\binternet\b/, "Internet", "Contas"],
  [/\btelefone\b/, "Telefone", "Contas"],
  [/\bfarmacia\b|\bremedio\b/, "Farmácia", "Saúde"],
  [/\bconsulta\b|\bmedico\b/, "Consulta médica", "Saúde"],
  [/\bdentista\b/, "Dentista", "Saúde"],
  [/\bplano de saude\b/, "Plano de saúde", "Saúde"],
  [/\bcinema\b/, "Cinema", "Lazer"],
  [/\bshow\b/, "Show", "Lazer"],
  [/\bbar\b|\bcerveja\b/, "Bar", "Lazer"],
  [/\bnetflix\b|\bspotify\b|\bstreaming\b/, "Streaming", "Lazer"],
  [/\bviagem\b/, "Viagem", "Lazer"],
  [/\btelevisao\b|\btv\b/, "Televisão", "Compras"],
  [/\bgeladeira\b/, "Geladeira", "Compras"],
  [/\bcelular\b/, "Celular", "Compras"],
  [/\broupas?\b/, "Roupas", "Compras"],
  [/\btenis\b|\bsapato\b/, "Calçados", "Compras"],
  [/\bpresente\b/, "Presente", "Compras"],
  [/\bfaculdade\b|\bmensalidade\b/, "Mensalidade", "Educação"],
  [/\bcurso\b/, "Curso", "Educação"],
  [/\blivros?\b/, "Livro", "Educação"],
  [/\bescola\b/, "Escola", "Educação"],
  [/\bsalario\b/, "Salário", "Salário"],
  [/\bfreela\b|\bfreelance\b/, "Freelance", "Freelance"],
  [/\brendimentos?\b|\bdividendos\b/, "Rendimentos", "Investimentos"],
];

const OWN_ACCOUNT_WORDS = /\b(?:poupanca|conta corrente|corrente|minha conta|carteira|investimentos?|reserva|conta)\b/;
const TRANSFER_PATTERN = new RegExp(
  String.raw`\b(?:transferi|mandei|passei|enviei|movi|coloquei|guardei)\b.*\b(?:da|do)\s+(?:minha\s+)?(poupanca|conta corrente|corrente|conta|carteira|investimentos?)\b.*\b(?:para|pra|pro)\s+(?:a\s+|o\s+|minha\s+)?(poupanca|conta corrente|corrente|conta|carteira|investimentos?|reserva)\b`,
);
const INCOME_VERBS = /\b(?:recebi|ganhei|caiu|entrou|depositaram|me pagaram|vendi|recebimento)\b/;
const EXPENSE_VERBS = /\b(?:gastei|paguei|comprei|custou|saiu|torrei|dei|fiz um pix|pix de|abasteci|almocei|jantei)\b/;
const RECURRING_WORDS = /\b(?:todo mes|todos os meses|mensalmente|mensal|toda semana|recorrente|assinatura|fixo|fixa)\b/;
const PAID_TO_PERSON = /\b(?:[Pp]aguei|[Mm]andei|[Tt]ransferi|[Pp]assei|[Dd]ei|[Pp]ix|PIX)\b[^.]*?\b(?:para|pro|pra|ao|a)\s+(?:o\s+|a\s+|seu\s+|dona\s+)?([A-ZÀ-Ý][a-zà-ÿ]+)/;
const PURPOSE_HINT = /\b(?:referente|pelo|pela|pelos|pelas|por causa|de conserto|do conserto|da faxina|do servico)\b/;

function detectPayment(t: string): PaymentMethod | null {
  if (/\bdebito\b/.test(t)) return "debit_card";
  if (/\bcredito\b|\bno cartao\b|\bcartao\b|\bparcel/.test(t)) return "credit_card";
  if (/\bpix\b/.test(t)) return "pix";
  if (/\bdinheiro\b|\bem especie\b/.test(t)) return "cash";
  if (/\bboleto\b/.test(t)) return "bank_slip";
  if (/\bted\b|\bdoc\b|\btransferencia bancaria\b/.test(t)) return "bank_transfer";
  return null;
}

function keywordFor(t: string): [string, string] | null {
  for (const [re, desc, cat] of KEYWORDS) if (re.test(t)) return [desc, cat];
  return null;
}

// ---------------------------------------------------------------------------
// Interpretador por regras (reserva quando a IA não está disponível)
// ---------------------------------------------------------------------------
export function heuristicExtract(transcript: string, today: string): RawExtraction {
  const t = fold(transcript);
  const amounts = analyzeAmounts(transcript);
  const kw = keywordFor(t);
  const transfer = TRANSFER_PATTERN.exec(t);

  let type: TransactionType | null = null;
  if (transfer) type = "transfer";
  else if (INCOME_VERBS.test(t)) type = "income";
  else if (EXPENSE_VERBS.test(t)) type = "expense";

  const date = resolveDate(transcript, today);
  const missing: string[] = [];
  if (amounts.best === null) missing.push("amount");
  if (type === null) missing.push("type");
  if (!kw && type !== "transfer") missing.push("description");

  return {
    type,
    amount: amounts.best === null ? null : amounts.best / 100,
    description: transfer ? "Transferência entre contas" : kw?.[0] ?? null,
    category: type === "transfer" ? null : kw?.[1] ?? null,
    date: date.date,
    account: transfer ? accountLabel(transfer[1]) : null,
    destination_account: transfer ? accountLabel(transfer[2]) : null,
    payment_method: type === "transfer" ? null : detectPayment(t),
    installments: type === "expense" ? amounts.installments : null,
    recurring: RECURRING_WORDS.test(t),
    notes: null,
    confidence: missing.length === 0 ? 0.7 : 0.4,
    missing_fields: missing,
    requires_clarification: missing.length > 0,
    clarification_question: null,
  };
}

function accountLabel(word: string): string {
  if (word === "poupanca") return "Poupança";
  if (word === "corrente" || word === "conta corrente" || word === "conta") return "Conta corrente";
  if (word === "carteira") return "Carteira";
  return word.charAt(0).toUpperCase() + word.slice(1);
}

// ---------------------------------------------------------------------------
// Conferência da proposta
// ---------------------------------------------------------------------------
function matchName(name: string | null, options: string[]): string | null {
  if (!name) return null;
  const f = fold(name.trim());
  return options.find((o) => fold(o) === f) ?? null;
}

function pushUnique(list: string[], value: string) {
  if (!list.includes(value)) list.push(value);
}

export function validateExtraction(raw: RawExtraction, transcript: string, ctx: UserContext): Extraction {
  const t = fold(transcript);
  const analysis = analyzeAmounts(transcript);
  const missing: string[] = (raw.missing_fields ?? []).filter((f) => typeof f === "string").slice(0, 12);
  const questions: string[] = [];

  // ---- tipo ---------------------------------------------------------------
  let type: TransactionType | null = TRANSACTION_TYPES.includes(raw.type as TransactionType) ? raw.type : null;
  const ownTransfer = TRANSFER_PATTERN.exec(t);
  if (ownTransfer && type !== "transfer") {
    // Regra: transferência entre contas próprias não é receita nem despesa.
    type = "transfer";
  }
  if (type === null) {
    pushUnique(missing, "type");
    questions.push("Isso foi uma receita, uma despesa ou uma transferência?");
  }

  // ---- valor --------------------------------------------------------------
  let amountCents: number | null = null;
  const aiCents = typeof raw.amount === "number" && Number.isFinite(raw.amount)
    ? Math.round(raw.amount * 100)
    : null;
  if (analysis.corrected && analysis.best !== null) {
    amountCents = analysis.best;
    const others = analysis.amounts.filter((a) => a !== analysis.best).map(formatBRL);
    questions.push(
      `Você mencionou ${others.join(", ")} e depois ${formatBRL(analysis.best)}. O valor correto é ${formatBRL(analysis.best)}?`,
    );
  } else if (aiCents !== null) {
    const grounded = analysis.amounts.includes(aiCents) ||
      (analysis.installments !== null && analysis.amounts.some((a) => a * analysis.installments! === aiCents));
    if (grounded) amountCents = aiCents;
  } else if (analysis.best !== null) {
    amountCents = analysis.best;
  }
  if (amountCents !== null && (amountCents <= 0 || amountCents > MAX_AMOUNT_CENTS)) amountCents = null;
  if (amountCents !== null && analysis.ambiguous && !analysis.corrected) {
    questions.push(
      `Encontrei mais de um valor (${[...new Set(analysis.amounts)].map(formatBRL).join(", ")}). Confirme o valor de ${formatBRL(amountCents)}.`,
    );
  }
  if (amountCents === null) {
    pushUnique(missing, "amount");
    questions.unshift("Qual foi o valor?");
  } else {
    const idx = missing.indexOf("amount");
    if (idx >= 0) missing.splice(idx, 1);
  }

  // ---- parcelas -----------------------------------------------------------
  let installments: number | null = null;
  if (type === "expense" && analysis.installments !== null &&
      (raw.installments === null || raw.installments === analysis.installments)) {
    installments = analysis.installments;
  }
  let installmentAmount: number | null = null;
  let firstInstallmentAmount: number | null = null;
  if (installments !== null && amountCents !== null) {
    const parts = splitInstallments(amountCents, installments);
    firstInstallmentAmount = parts[0];
    installmentAmount = parts[parts.length - 1];
  }

  // ---- descrição ------------------------------------------------------------
  let description = typeof raw.description === "string" ? raw.description.trim().slice(0, 120) : "";
  const kw = keywordFor(t);
  if (!description && kw) description = kw[0];
  if (!description && type === "transfer") description = "Transferência entre contas";
  const personWithoutPurpose = type === "expense" && PAID_TO_PERSON.test(transcript) && !kw && !PURPOSE_HINT.test(t);
  if (!description || personWithoutPurpose) {
    pushUnique(missing, "description");
    questions.push(
      type === "income" ? "De onde veio essa receita?" : "Esse pagamento foi referente a quê?",
    );
  }

  // ---- categoria (sugestão; o usuário pode trocar) ---------------------------
  let category: string | null = null;
  if (type === "income" || type === "expense") {
    const names = ctx.categories.filter((c) => c.kind === type).map((c) => c.name);
    category = matchName(raw.category, names) ?? matchName(kw?.[1] ?? null, names);
  }

  // ---- data -----------------------------------------------------------------
  const resolved = resolveDate(transcript, ctx.today);
  let date = resolved.date;
  if (raw.date && parseISODate(raw.date) && resolved.matched !== null) {
    // A IA pode entender construções mais complexas; só aceitamos se a fala
    // realmente menciona uma data.
    date = raw.date;
  }
  const todayDate = parseISODate(ctx.today)!;
  const chosen = parseISODate(date)!;
  if (Math.abs(chosen.y - todayDate.y) > 1) {
    date = resolved.date;
  }

  // ---- contas e forma de pagamento ------------------------------------------
  let account = matchName(raw.account, ctx.accounts);
  let destination = type === "transfer" ? matchName(raw.destination_account, ctx.accounts) : null;
  if (type === "transfer" && ownTransfer) {
    account ??= matchName(accountLabel(ownTransfer[1]), ctx.accounts);
    destination ??= matchName(accountLabel(ownTransfer[2]), ctx.accounts);
  }
  if (type === "transfer") {
    if (!destination || destination === account) {
      destination = null;
      pushUnique(missing, "destination_account");
      questions.push("Para qual conta foi a transferência?");
    }
  }
  const payment = type === "transfer"
    ? null
    : PAYMENT_METHODS.includes(raw.payment_method as PaymentMethod)
    ? raw.payment_method
    : detectPayment(t);

  // ---- pergunta da própria IA -------------------------------------------------
  if (raw.clarification_question && raw.clarification_question.trim().length <= 200) {
    const q = raw.clarification_question.trim();
    if (!questions.some((existing) => fold(existing) === fold(q))) questions.push(q);
  }

  const requires = questions.length > 0;
  let confidence = Number.isFinite(raw.confidence) ? Math.min(1, Math.max(0, raw.confidence)) : 0.5;
  if (requires) confidence = Math.min(confidence, 0.6);

  return {
    type,
    amount: amountCents === null ? null : amountCents / 100,
    amount_cents: amountCents,
    description: description || null,
    category,
    date,
    account,
    destination_account: destination,
    payment_method: payment,
    installments,
    installment_amount_cents: installmentAmount,
    first_installment_amount_cents: firstInstallmentAmount,
    recurring: type !== "transfer" && installments === null && Boolean(raw.recurring),
    notes: (raw.notes ?? "").trim().slice(0, 500),
    confidence,
    missing_fields: missing,
    requires_clarification: requires,
    questions,
  };
}
