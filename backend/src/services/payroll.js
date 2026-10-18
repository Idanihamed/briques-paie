import { Rational, sum } from '../lib/rational.js';
import { frDate, isSunday, monthBounds } from '../lib/dates.js';
import { loadCalendar, resolveDay } from './calendar.js';

/* ───────────────────────── Calcul pur (sans base de données) ─────────────────────────
 * Entrée « entry » : { teamId, date:'YYYY-MM-DD', bricks:int|null,
 *                      presence:{workerId: 'present'|'absent'|'unset'} }
 * Part = (briques × PRIX DE CONFECTION) ÷ présents. Aucun arrondi.
 * Le prix de vente ('sale') n'intervient jamais dans la paie : il sert à l'admin
 * pour le chiffre d'affaires et la marge.
 */

/** Tarif applicable : effective_date la plus récente <= date de production. */
export function rateFor(tariffs, kind, date) {
  let best = null;
  for (const t of tariffs) {
    if (t.kind !== kind || t.effective_date > date) continue;
    if (!best || t.effective_date > best.effective_date ||
        (t.effective_date === best.effective_date && new Date(t.created_at) > new Date(best.created_at))) {
      best = t;
    }
  }
  return best ? best.value : null;
}

export const DayStatus = Object.freeze({
  OK: 'ok',
  ZERO_PRODUCTION: 'zero_production',
  NO_PRESENT: 'no_present',
  INCOMPLETE: 'incomplete',
  NO_TARIFF: 'no_tariff',
});

const count = (entry, status) => Object.values(entry.presence).filter((s) => s === status).length;

/** Valeur de `qty` briques au prix `kind` à la date `date` (null si aucun tarif). */
export function productionValue(tariffs, kind, date, qty) {
  const rate = rateFor(tariffs, kind, date);
  return rate == null ? null : Rational.int(BigInt(qty) * BigInt(rate));
}

export function computeDay(entry, tariffs) {
  const qty = entry.bricks;
  const rate = rateFor(tariffs, 'cost', entry.date);
  const total = qty == null || rate == null ? Rational.ZERO : productionValue(tariffs, 'cost', entry.date, qty);
  const present = count(entry, 'present');
  const base = { entry, total, presentCount: present };

  // « Non saisi » n'est jamais assimilé à une absence : la journée est incomplète.
  if (count(entry, 'unset') > 0 || qty == null) return { ...base, status: DayStatus.INCOMPLETE, share: Rational.ZERO };
  if (qty > 0 && rate == null) return { ...base, status: DayStatus.NO_TARIFF, share: Rational.ZERO };
  if (qty === 0) return { ...base, status: DayStatus.ZERO_PRODUCTION, share: Rational.ZERO };
  if (present === 0) return { ...base, status: DayStatus.NO_PRESENT, share: Rational.ZERO };
  return { ...base, status: DayStatus.OK, share: total.div(Rational.int(present)) };
}

const BLOCKING = new Set([DayStatus.INCOMPLETE, DayStatus.NO_PRESENT, DayStatus.NO_TARIFF]);
export const isBlocking = (status) => BLOCKING.has(status);

/**
 * Paie d'un mois. `teams` : [{id,name}], `today` : 'YYYY-MM-DD'.
 * Retourne parts par ouvrier, totaux par équipe et anomalies (bloquantes ou non).
 */
export function computeMonth({ month, entries, tariffs, teams, today, isWorkingDay = (_teamId, date) => !isSunday(date) }) {
  const workers = new Map(); // workerId -> { total:Rational, lines:[{date,teamId,share}] }
  const teamTotals = new Map();
  const anomalies = [];
  const names = new Map(teams.map((t) => [t.id, t.name]));
  const seen = new Set();

  const inMonth = entries.filter((e) => e.date.startsWith(month)).sort((a, b) => a.date.localeCompare(b.date));

  for (const e of inMonth) {
    seen.add(`${e.teamId}|${e.date}`);
    const r = computeDay(e, tariffs);
    const where = `${names.get(e.teamId) ?? e.teamId}, ${frDate(e.date)}`;
    const add = (kind, message, blocking) =>
      anomalies.push({ kind, teamId: e.teamId, date: e.date, message: `${where} : ${message}`, blocking });

    switch (r.status) {
      case DayStatus.OK:
        for (const [id, s] of Object.entries(e.presence)) {
          if (s !== 'present') continue;
          const w = workers.get(id) ?? { total: Rational.ZERO, lines: [] };
          w.total = w.total.add(r.share);
          w.lines.push({ date: e.date, teamId: e.teamId, share: r.share });
          workers.set(id, w);
        }
        teamTotals.set(e.teamId, (teamTotals.get(e.teamId) ?? Rational.ZERO).add(r.total));
        break;
      case DayStatus.ZERO_PRODUCTION:
        add('zero_production', 'production nulle, aucune part attribuée.', false);
        break;
      case DayStatus.NO_PRESENT:
        add('no_present', 'production > 0 mais aucun présent.', true);
        break;
      case DayStatus.INCOMPLETE:
        add('incomplete', 'journée incomplète (présences ou production non saisies).', true);
        break;
      case DayStatus.NO_TARIFF:
        add('no_tariff', 'aucun tarif applicable à cette date.', true);
        break;
    }
  }

  // Jours TRAVAILLÉS (selon le calendrier) passés sans aucune saisie, par équipe.
  const { days } = monthBounds(month);
  for (const t of teams) {
    for (let d = 1; d <= days; d++) {
      const date = `${month}-${String(d).padStart(2, '0')}`;
      if (date >= today || !isWorkingDay(t.id, date)) continue;
      if (!seen.has(`${t.id}|${date}`)) {
        anomalies.push({ kind: 'missing_day', teamId: t.id, date, message: `${t.name}, ${frDate(date)} : aucune saisie.`, blocking: false });
      }
    }
  }
  anomalies.sort((a, b) => a.date.localeCompare(b.date));

  return {
    workers,
    teamTotals,
    anomalies,
    total: sum([...teamTotals.values()]),
    hasBlocking: anomalies.some((a) => a.blocking),
  };
}

/* ───────────────────────── Chargement depuis la base ───────────────────────── */

export async function loadTariffs(q) {
  return (await q.query('select kind, value, effective_date, created_at from tariffs')).rows;
}

/** Construit les « entries » du calcul pour [start, endExclusive). */
export async function loadEntries(q, start, endExclusive, { teamId } = {}) {
  const params = [start, endExclusive];
  let where = 'work_date >= $1 and work_date < $2';
  if (teamId) {
    params.push(teamId);
    where += ' and team_id = $3';
  }
  const rows = (await q.query(
    `select id, team_id, work_date, entered_by, bricks, last_request_id,
            to_char(updated_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as version
       from day_entries where ${where}`,
    params,
  )).rows;
  if (rows.length === 0) return [];
  const ids = rows.map((r) => r.id);
  const pres = (await q.query('select entry_id, worker_id, status, is_substitute, face_verified, absence_reason from day_presences where entry_id = any($1::uuid[])', [ids])).rows;

  const byId = new Map(
    rows.map((r) => [
      r.id,
      { id: r.id, teamId: r.team_id, date: r.work_date, enteredBy: r.entered_by, bricks: r.bricks, version: r.version, lastRequestId: r.last_request_id, presence: {}, meta: {} },
    ]),
  );
  for (const p of pres) {
    const e = byId.get(p.entry_id);
    e.presence[p.worker_id] = p.status;
    e.meta[p.worker_id] = { isSubstitute: p.is_substitute, faceVerified: p.face_verified, absenceReason: p.absence_reason };
  }
  return [...byId.values()];
}

export async function payrollForMonth(q, month, today) {
  const { start, endExclusive } = monthBounds(month);
  const [tariffs, teams] = await Promise.all([
    loadTariffs(q),
    q.query('select id, name from teams order by name').then((r) => r.rows),
  ]);
  const entries = await loadEntries(q, start, endExclusive);
  const calendar = await loadCalendar(q, start, endExclusive);
  const isWorkingDay = (teamId, date) => resolveDay(calendar, date, teamId).working;
  return { ...computeMonth({ month, entries, tariffs, teams, today, isWorkingDay }), tariffs, teams, entries, calendar };
}
