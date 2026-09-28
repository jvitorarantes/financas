// Datas relativas em português: "hoje", "ontem", "dia 5", "sexta passada",
// "12/09". As contas são feitas em UTC puro para não depender do fuso do
// servidor; `today` sempre chega pronto (data local do usuário).

import { fold, normalizeNumbers } from "./ptbr_numbers.ts";

export interface SimpleDate { y: number; m: number; d: number }

export function parseISODate(iso: string): SimpleDate | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!m) return null;
  const date = { y: Number(m[1]), m: Number(m[2]), d: Number(m[3]) };
  return isValidDate(date) ? date : null;
}

export function toISODate(date: SimpleDate): string {
  return `${date.y}-${String(date.m).padStart(2, "0")}-${String(date.d).padStart(2, "0")}`;
}

function isValidDate({ y, m, d }: SimpleDate): boolean {
  const dt = new Date(Date.UTC(y, m - 1, d));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d;
}

export function addDays(date: SimpleDate, days: number): SimpleDate {
  const dt = new Date(Date.UTC(date.y, date.m - 1, date.d + days));
  return { y: dt.getUTCFullYear(), m: dt.getUTCMonth() + 1, d: dt.getUTCDate() };
}

function weekday(date: SimpleDate): number {
  return new Date(Date.UTC(date.y, date.m - 1, date.d)).getUTCDay(); // 0 = domingo
}

function compare(a: SimpleDate, b: SimpleDate): number {
  return toISODate(a) < toISODate(b) ? -1 : toISODate(a) > toISODate(b) ? 1 : 0;
}

const MONTHS: Record<string, number> = {
  janeiro: 1, fevereiro: 2, marco: 3, abril: 4, maio: 5, junho: 6, julho: 7,
  agosto: 8, setembro: 9, outubro: 10, novembro: 11, dezembro: 12,
};
const WEEKDAYS: Record<string, number> = {
  domingo: 0, segunda: 1, terca: 2, quarta: 3, quinta: 4, sexta: 5, sabado: 6,
};

const PAST_VERBS = /\b(?:gastei|paguei|recebi|comprei|ganhei|transferi|mandei|passei|custou|caiu|entrou|saiu|foi|tive|fiz|almocei|jantei|abasteci|depositei|enviei)\b/;
const FUTURE_HINT = /\b(?:vou|vence|vencimento|pagar|receber|agendar|agendei|devo|daqui)\b/;

export interface DateResolution {
  date: string;          // YYYY-MM-DD
  matched: string | null; // trecho que definiu a data; null = assumiu hoje
}

/**
 * Descobre a data de um lançamento a partir da fala. Sem nenhuma menção,
 * assume hoje (como o usuário espera ao dizer "gastei 45 no almoço").
 */
export function resolveDate(text: string, todayISO: string): DateResolution {
  const today = parseISODate(todayISO);
  if (!today) throw new Error("invalid today");
  const t = fold(normalizeNumbers(text));
  const past = PAST_VERBS.test(t) && !FUTURE_HINT.test(t);

  const rel: Array<[RegExp, number]> = [
    [/\bdepois de amanha\b/, 2],
    [/\banteontem\b/, -2],
    [/\bontem\b/, -1],
    [/\bamanha\b/, 1],
    [/\bhoje\b/, 0],
  ];
  for (const [re, offset] of rel) {
    const m = re.exec(t);
    if (m) return { date: toISODate(addDays(today, offset)), matched: m[0] };
  }

  const daysAgo = /\bha (\d{1,2}) dias?\b/.exec(t) ?? /\b(\d{1,2}) dias? atras\b/.exec(t);
  if (daysAgo) return { date: toISODate(addDays(today, -Number(daysAgo[1]))), matched: daysAgo[0] };

  // dd/mm ou dd/mm/aaaa
  const numeric = /\b(\d{1,2})\s*\/\s*(\d{1,2})(?:\s*\/\s*(\d{2,4}))?\b/.exec(t);
  if (numeric) {
    const d = Number(numeric[1]);
    const mo = Number(numeric[2]);
    let y = numeric[3] ? Number(numeric[3]) : today.y;
    if (y < 100) y += 2000;
    let candidate = { y, m: mo, d };
    if (!numeric[3] && past && isValidDate(candidate) && compare(candidate, today) > 0) {
      candidate = { y: y - 1, m: mo, d };
    }
    if (isValidDate(candidate)) return { date: toISODate(candidate), matched: numeric[0] };
  }

  // "dia 5", "dia 5 de setembro"
  const dayOf = /\bdia (\d{1,2})(?: de (janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro))?\b/.exec(t);
  if (dayOf) {
    const d = Number(dayOf[1]);
    const mo = dayOf[2] ? MONTHS[dayOf[2]] : today.m;
    let candidate = { y: today.y, m: mo, d };
    if (past && compare(candidate, today) > 0) {
      candidate = dayOf[2] ? { y: today.y - 1, m: mo, d } : prevMonth(candidate);
    } else if (!past && FUTURE_HINT.test(t) && compare(candidate, today) < 0 && !dayOf[2]) {
      candidate = nextMonth(candidate);
    }
    if (isValidDate(candidate)) return { date: toISODate(candidate), matched: dayOf[0] };
  }

  // Dia da semana: "na sexta", "segunda passada", "sábado que vem"
  const wd = /\b(domingo|segunda|terca|quarta|quinta|sexta|sabado)(?:-feira| feira)?( passad[oa]| que vem| proxim[oa])?\b/.exec(t);
  if (wd) {
    const target = WEEKDAYS[wd[1]];
    const forward = wd[2] ? /que vem|proxim/.test(wd[2]) : !past;
    const current = weekday(today);
    let diff: number;
    if (forward) {
      diff = (target - current + 7) % 7 || 7;
    } else {
      diff = -((current - target + 7) % 7 || 7);
    }
    return { date: toISODate(addDays(today, diff)), matched: wd[0] };
  }

  return { date: todayISO, matched: null };
}

function prevMonth(date: SimpleDate): SimpleDate {
  return date.m === 1 ? { y: date.y - 1, m: 12, d: date.d } : { y: date.y, m: date.m - 1, d: date.d };
}
function nextMonth(date: SimpleDate): SimpleDate {
  return date.m === 12 ? { y: date.y + 1, m: 1, d: date.d } : { y: date.y, m: date.m + 1, d: date.d };
}
