import { computeDay, loadEntries, loadTariffs, rateFor, productionValue, DayStatus } from './payroll.js';
import { Rational } from '../lib/rational.js';
import { loadCalendar, resolveDay } from './calendar.js';

export const nextDay = (date) => {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
};

/**
 * Détail monétaire d'une journée : RÉSERVÉ à l'admin (jamais envoyé au superviseur).
 *  cost   = briques × prix de confection (175) : base de paie de l'équipe
 *  sale   = briques × prix de vente (250)     : chiffre d'affaires
 *  margin = sale − cost
 */
export function calcView(entry, tariffs) {
  const r = computeDay(entry, tariffs);
  const qty = entry.bricks ?? 0;
  const cost = productionValue(tariffs, 'cost', entry.date, qty) ?? Rational.ZERO;
  const sale = productionValue(tariffs, 'sale', entry.date, qty) ?? Rational.ZERO;
  return {
    status: r.status,
    bricks: entry.bricks,
    costRate: rateFor(tariffs, 'cost', entry.date),
    saleRate: rateFor(tariffs, 'sale', entry.date),
    cost,
    sale,
    margin: sale.sub(cost),
    share: r.status === DayStatus.OK ? r.share : null,
  };
}

/**
 * Vue d'une journée pour une équipe : brouillon (aucune saisie) ou saisie existante.
 * `withCalc` = true uniquement pour l'admin.
 */
export async function dayView(q, { teamId, date, viewerWorkerId, withCalc }) {
  const tariffs = await loadTariffs(q);
  const [entry] = await loadEntries(q, date, nextDay(date), { teamId });

  let roster;
  if (entry) {
    roster = Object.keys(entry.presence).map((id) => ({
      id,
      status: entry.presence[id],
      isSubstitute: entry.meta[id].isSubstitute,
      faceVerified: entry.meta[id].faceVerified,
      absenceReason: entry.meta[id].absenceReason ?? null,
    }));
  } else {
    const members = (await q.query('select id from workers where team_id = $1 and active', [teamId])).rows;
    roster = members.map((m) => ({ id: m.id, status: 'unset', isSubstitute: false, faceVerified: false, absenceReason: null }));
  }

  const info = roster.length
    ? (await q.query('select id, full_name, face_enrolled from workers where id = any($1::uuid[])', [roster.map((r) => r.id)])).rows
    : [];
  const byId = new Map(info.map((w) => [w.id, w]));

  const members = roster
    .map((r) => ({
      workerId: r.id,
      fullName: byId.get(r.id)?.full_name ?? '?',
      status: r.status,
      isSubstitute: r.isSubstitute,
      faceVerified: r.faceVerified,
      absenceReason: r.absenceReason ?? null,
      faceEnrolled: byId.get(r.id)?.face_enrolled ?? false,
      isSelf: r.id === viewerWorkerId,
    }))
    .sort((a, b) => Number(a.isSubstitute) - Number(b.isSubstitute) || a.fullName.localeCompare(b.fullName, 'fr'));

  const bricks = entry ? entry.bricks : null;
  const draft = entry ?? { teamId, date, bricks, presence: Object.fromEntries(roster.map((r) => [r.id, r.status])) };
  const complete = !Object.values(draft.presence).includes('unset') && bricks != null;

  const locked = (await q.query('select month_is_locked($1::date) as locked', [date])).rows[0].locked;

  const calendar = await loadCalendar(q, date, nextDay(date));

  const view = {
    teamId,
    date,
    saved: Boolean(entry),
    // Version de la journée : sert à détecter qu'elle a été modifiée ailleurs (synchronisation hors ligne).
    version: entry?.version ?? null,
    workingDay: resolveDay(calendar, date, teamId),
    locked,
    complete,
    bricks, // nombre de briques confectionnées (null = non saisi)
    members,
    counts: {
      present: members.filter((m) => m.status === 'present').length,
      absent: members.filter((m) => m.status === 'absent').length,
      unset: members.filter((m) => m.status === 'unset').length,
    },
  };
  if (entry) {
    const who = (await q.query('select name from users where id = $1', [entry.enteredBy])).rows[0];
    view.enteredBy = who?.name ?? null;
  }
  if (withCalc) view.calc = calcView(draft, tariffs);
  return view;
}
