import { frDate, monthLabel } from '../lib/dates.js';
import { Rational } from '../lib/rational.js';
import { loadCalendar, resolveDay, dateRange } from './calendar.js';
import { nextDay } from './days.js';
import { loadEntries, loadTariffs, payrollForMonth, rateFor } from './payroll.js';
import { advancesByWorker } from './advances.js';

const LEVEL_ORDER = { high: 0, medium: 1, info: 2 };
const addDays = (date, n) => new Date(Date.parse(`${date}T00:00:00Z`) + n * 86_400_000).toISOString().slice(0, 10);

/**
 * Alertes pour l'admin : ce qui demande une action ou mérite attention.
 * Calculées à la demande à partir des saisies (rien n'est stocké).
 */
export async function buildAlerts(db, today) {
  const alerts = [];
  const push = (level, kind, title, detail) => alerts.push({ id: `${kind}:${title}`, level, kind, title, detail });

  const [tariffs, teams, names] = await Promise.all([
    loadTariffs(db),
    db.query('select id, name from teams order by name').then((r) => r.rows),
    db.query('select id, full_name, active, face_enrolled from workers').then((r) => r.rows),
  ]);
  const nameOf = new Map(names.map((w) => [w.id, w.full_name]));
  const from = addDays(today, -60);
  const entries = await loadEntries(db, from, nextDay(today));
  const calendar = await loadCalendar(db, from, nextDay(today));

  // 0. Prix manquants
  if (rateFor(tariffs, 'cost', today) == null) push('high', 'no_price', 'Prix de confection manquant', 'Aucun tarif de confection en vigueur : la paie ne peut pas être calculée.');
  if (rateFor(tariffs, 'sale', today) == null) push('medium', 'no_price', 'Prix de vente manquant', 'Aucun tarif de vente en vigueur : la marge ne peut pas être calculée.');

  // 1. Jours travaillés sans saisie (7 derniers jours, aujourd'hui exclu)
  const seen = new Set(entries.map((e) => `${e.teamId}|${e.date}`));
  for (const t of teams) {
    const missing = dateRange(addDays(today, -7), addDays(today, -1)).filter((d) => resolveDay(calendar, d, t.id).working && !seen.has(`${t.id}|${d}`));
    if (missing.length) {
      push(missing.length >= 3 ? 'high' : 'medium', 'missing_days', `${t.name} : ${missing.length} jour${missing.length > 1 ? 's' : ''} sans saisie`,
        missing.map(frDate).join(', '));
    }
  }

  // 2. Journées incomplètes (14 derniers jours)
  const recent = addDays(today, -14);
  for (const t of teams) {
    const bad = entries.filter((e) => e.teamId === t.id && e.date >= recent && e.date < today
      && (e.bricks == null || Object.values(e.presence).includes('unset')));
    if (bad.length) push('medium', 'incomplete', `${t.name} : ${bad.length} journée${bad.length > 1 ? 's' : ''} incomplète${bad.length > 1 ? 's' : ''}`, bad.map((e) => frDate(e.date)).join(', '));
  }

  // 3. Baisse de production : dernière journée très inférieure à la moyenne récente
  for (const t of teams) {
    const es = entries.filter((e) => e.teamId === t.id && e.bricks != null).sort((a, b) => a.date.localeCompare(b.date));
    if (es.length < 6) continue;
    const last = es.at(-1);
    const before = es.slice(-11, -1);
    const avg = before.reduce((a, e) => a + e.bricks, 0) / before.length;
    if (avg > 0 && last.bricks < avg * 0.6 && addDays(last.date, 3) >= today) {
      push('medium', 'production_drop', `${t.name} : baisse de production`,
        `${frDate(last.date)} : ${last.bricks} briques contre ${Math.round(avg)} en moyenne.`);
    }
  }

  // 4. Absences répétées (3 saisies consécutives ou plus, jusqu'à la dernière)
  const byWorker = new Map();
  for (const e of [...entries].sort((a, b) => a.date.localeCompare(b.date))) {
    for (const [id, st] of Object.entries(e.presence)) {
      if (st === 'unset') continue;
      (byWorker.get(id) ?? byWorker.set(id, []).get(id)).push({ date: e.date, st });
    }
  }
  for (const [id, list] of byWorker) {
    let n = 0;
    for (let i = list.length - 1; i >= 0 && list[i].st === 'absent'; i--) n++;
    if (n >= 3 && addDays(list.at(-1).date, 5) >= today) {
      push('medium', 'long_absence', `${nameOf.get(id) ?? '—'} : ${n} absences de suite`, `Depuis le ${frDate(list[list.length - n].date)}.`);
    }
  }

  // 5. Paie du mois précédent non validée
  const prev = (() => {
    const d = new Date(Date.UTC(Number(today.slice(0, 4)), Number(today.slice(5, 7)) - 2, 1));
    return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
  })();
  if (Number(today.slice(8)) >= 3) {
    const locked = (await db.query('select 1 from payroll_versions where month = $1 and unlocked_at is null', [prev])).rowCount > 0;
    if (!locked) {
      const p = await payrollForMonth(db, prev, today);
      if (p.entries.length) {
        const n = p.anomalies.filter((a) => a.blocking).length;
        push(n ? 'high' : 'medium', 'payroll_pending', `Paie de ${monthLabel(prev)} à valider`,
          n ? `${n} anomalie${n > 1 ? 's' : ''} bloquante${n > 1 ? 's' : ''} à corriger avant validation.` : 'Aucune anomalie bloquante : elle peut être validée.');
      }
    }
  }

  // 6. Avances supérieures aux gains du mois en cours
  const month = today.slice(0, 7);
  const adv = await advancesByWorker(db, month);
  if (adv.size) {
    const p = await payrollForMonth(db, month, today);
    for (const [id, amount] of adv) {
      const earned = p.workers.get(id)?.total ?? Rational.ZERO;
      if (earned.sub(Rational.int(amount)).isNegative) {
        push('high', 'advance_over', `${nameOf.get(id) ?? '—'} : avances supérieures aux gains`, `Avances ${amount} FCFA, gains à ce jour ${earned.toFixed(2)} FCFA.`);
      }
    }
  }

  // 7. Visages non enregistrés
  const noFace = names.filter((w) => w.active && !w.face_enrolled).length;
  if (noFace) push('info', 'no_face', `${noFace} ouvrier${noFace > 1 ? 's' : ''} sans visage enregistré`, 'L\'identification faciale n\'est pas possible pour eux.');

  return alerts.sort((a, b) => LEVEL_ORDER[a.level] - LEVEL_ORDER[b.level]);
}
