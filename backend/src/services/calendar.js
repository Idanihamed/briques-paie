/**
 * Calendrier de travail.
 * Un jour est « travaillé » sauf : exception d'équipe > exception globale > jour de repos hebdomadaire.
 * Les exceptions peuvent aussi RENDRE travaillé un jour de repos (kind = 'work', ex. un dimanche).
 */
export const DEFAULT_REST_WEEKDAYS = [0]; // dimanche (modifiable par l'admin)

export const weekdayOf = (date) => new Date(`${date}T00:00:00Z`).getUTCDay();

export async function loadRestWeekdays(q) {
  const v = (await q.query("select value from app_settings where key = 'rest_weekdays'")).rows[0]?.value;
  const list = typeof v === 'string' ? JSON.parse(v) : v;
  return Array.isArray(list) ? list : DEFAULT_REST_WEEKDAYS;
}

export async function loadCalendar(q, start, endExclusive) {
  const restWeekdays = await loadRestWeekdays(q);
  const rows = (await q.query(
    'select work_date, team_id, kind, reason from calendar_days where work_date >= $1 and work_date < $2',
    [start, endExclusive],
  )).rows;
  const byKey = new Map(rows.map((r) => [`${r.team_id ?? '*'}|${r.work_date}`, r]));
  return { restWeekdays, rows, byKey };
}

const fromRow = (row, source) => ({ working: row.kind === 'work', kind: row.kind, reason: row.reason ?? null, source });

/** { working, kind, reason, source: 'team' | 'global' | 'weekly' | 'default' } */
export function resolveDay(cal, date, teamId) {
  const team = cal.byKey.get(`${teamId}|${date}`);
  if (team) return fromRow(team, 'team');
  const global = cal.byKey.get(`*|${date}`);
  if (global) return fromRow(global, 'global');
  if (cal.restWeekdays.includes(weekdayOf(date))) return { working: false, kind: 'rest', reason: null, source: 'weekly' };
  return { working: true, kind: 'work', reason: null, source: 'default' };
}

export const KIND_LABELS = {
  work: 'Travaillé (exceptionnel)',
  rest: 'Repos',
  holiday: 'Férié',
  weather: 'Intempérie',
  breakdown: 'Panne',
  other: 'Autre',
};

/** Message affiché quand on essaie de saisir un jour non travaillé. */
export const nonWorkingMessage = (info) =>
  `Jour non travaillé (${KIND_LABELS[info.kind].toLowerCase()}${info.reason ? ` : ${info.reason}` : ''}). `
  + "La saisie est impossible ; demandez à l'admin de rétablir ce jour s'il a bien été travaillé.";

/** Liste des dates AAAA-MM-JJ de `from` à `to` inclus. */
export function dateRange(from, to) {
  const out = [];
  const end = new Date(`${to}T00:00:00Z`);
  for (let d = new Date(`${from}T00:00:00Z`); d <= end; d.setUTCDate(d.getUTCDate() + 1)) {
    out.push(d.toISOString().slice(0, 10));
  }
  return out;
}
