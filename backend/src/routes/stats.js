import { Router } from 'express';
import { ah } from '../lib/errors.js';
import { assertMonth, monthLabel, todayStr } from '../lib/dates.js';
import { Rational } from '../lib/rational.js';
import { payrollForMonth, productionValue } from '../services/payroll.js';

const MONTHS_BACK = 6;

const shiftMonth = (month, delta) => {
  const [y, m] = month.split('-').map(Number);
  const d = new Date(Date.UTC(y, m - 1 + delta, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
};

const ratio = (a, b) => (b > 0 ? Number((a / b).toFixed(4)) : null);

/** Résumé d'un mois à partir des saisies (production, présences, valeurs). */
function summarize(p) {
  let bricks = 0;
  let present = 0;
  let absent = 0;
  let cost = Rational.ZERO;
  let sale = Rational.ZERO;
  const days = new Set();
  const byDate = new Map();
  for (const e of p.entries) {
    if (e.bricks == null) continue;
    bricks += e.bricks;
    days.add(`${e.teamId}|${e.date}`);
    byDate.set(e.date, (byDate.get(e.date) ?? 0) + e.bricks);
    const c = productionValue(p.tariffs, 'cost', e.date, e.bricks);
    const s = productionValue(p.tariffs, 'sale', e.date, e.bricks);
    if (c) cost = cost.add(c);
    if (s) sale = sale.add(s);
    for (const st of Object.values(e.presence)) {
      if (st === 'present') present++;
      else if (st === 'absent') absent++;
    }
  }
  return { bricks, present, absent, cost, sale, margin: sale.sub(cost), workedDays: days.size, byDate };
}

/**
 * Classements et tendances (admin) : évolution sur 6 mois, production par équipe,
 * assiduité et gains par ouvrier, production jour par jour.
 */
export function statsRouter({ db, auth, admin }) {
  const r = Router();
  r.use(auth, admin);

  r.get('/', ah(async (req, res) => {
    const month = assertMonth(String(req.query.month ?? todayStr().slice(0, 7)));
    const today = todayStr();

    const trend = [];
    let current = null;
    let currentP = null;
    for (let i = MONTHS_BACK - 1; i >= 0; i--) {
      const m = shiftMonth(month, -i);
      const p = await payrollForMonth(db, m, today);
      const s = summarize(p);
      if (m === month) { current = s; currentP = p; }
      trend.push({
        month: m, label: monthLabel(m), bricks: s.bricks, workedDays: s.workedDays,
        attendanceRate: ratio(s.present, s.present + s.absent), cost: s.cost, sale: s.sale, margin: s.margin,
      });
    }

    const teams = currentP.teams.map((t) => {
      const es = currentP.entries.filter((e) => e.teamId === t.id && e.bricks != null);
      const bricks = es.reduce((a, e) => a + e.bricks, 0);
      const presents = es.reduce((a, e) => a + Object.values(e.presence).filter((s) => s === 'present').length, 0);
      const absents = es.reduce((a, e) => a + Object.values(e.presence).filter((s) => s === 'absent').length, 0);
      return {
        teamId: t.id, name: t.name, bricks, workedDays: es.length,
        avgBricksPerDay: es.length ? Math.round(bricks / es.length) : null,
        bricksPerPresent: presents ? Math.round(bricks / presents) : null,
        attendanceRate: ratio(presents, presents + absents),
      };
    }).sort((a, b) => b.bricks - a.bricks);

    const names = new Map((await db.query('select id, full_name from workers')).rows.map((w) => [w.id, w.full_name]));
    const perWorker = new Map();
    for (const e of currentP.entries) {
      for (const [id, st] of Object.entries(e.presence)) {
        if (st !== 'present' && st !== 'absent') continue;
        const w = perWorker.get(id) ?? { present: 0, absent: 0 };
        w[st]++;
        perWorker.set(id, w);
      }
    }
    const workers = [...perWorker.entries()].map(([id, w]) => ({
      workerId: id, fullName: names.get(id) ?? '—', present: w.present, absent: w.absent,
      attendanceRate: ratio(w.present, w.present + w.absent),
      earned: currentP.workers.get(id)?.total ?? Rational.ZERO,
    })).sort((a, b) => (b.attendanceRate ?? -1) - (a.attendanceRate ?? -1) || b.present - a.present
      || a.fullName.localeCompare(b.fullName, 'fr'));

    const daily = [...current.byDate.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([date, bricks]) => ({ date, bricks }));
    const best = daily.reduce((m, d) => (!m || d.bricks > m.bricks ? d : m), null);

    res.json({
      month, label: monthLabel(month),
      totals: {
        bricks: current.bricks, workedDays: current.workedDays,
        attendanceRate: ratio(current.present, current.present + current.absent),
        cost: current.cost, sale: current.sale, margin: current.margin,
        avgBricksPerDay: daily.length ? Math.round(current.bricks / daily.length) : null,
        bestDay: best,
      },
      trend, teams, workers, daily,
    });
  }));

  return r;
}
