import { Router } from 'express';
import { z } from 'zod';
import { ah, badRequest } from '../lib/errors.js';
import { assertDate, frDate } from '../lib/dates.js';
import { Rational } from '../lib/rational.js';
import { computeDay, DayStatus, loadEntries, loadTariffs, productionValue } from '../services/payroll.js';
import { nextDay } from '../services/days.js';

const MAX_DAYS = 93;

const spanDays = (from, to) => Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000) + 1;

/**
 * Paie sur une période libre (semaine, quinzaine…), à titre d'information : mêmes règles que la paie
 * mensuelle (briques × prix de confection ÷ présents), sans validation ni verrouillage.
 * Le règlement officiel reste la paie mensuelle validée.
 */
export function reportsRouter({ db, auth, admin }) {
  const r = Router();
  r.use(auth, admin);

  r.get('/period', ah(async (req, res) => {
    const { from, to } = z.object({ from: z.string(), to: z.string() }).parse(req.query);
    assertDate(from, 'début');
    assertDate(to, 'fin');
    if (to < from) throw badRequest('La date de fin précède le début.');
    const days = spanDays(from, to);
    if (days > MAX_DAYS) throw badRequest(`Période trop longue (${MAX_DAYS} jours au maximum).`);

    const [tariffs, entries, teams, names] = await Promise.all([
      loadTariffs(db),
      loadEntries(db, from, nextDay(to)),
      db.query('select id, name from teams').then((x) => new Map(x.rows.map((t) => [t.id, t.name]))),
      db.query('select id, full_name from workers').then((x) => new Map(x.rows.map((w) => [w.id, w.full_name]))),
    ]);

    const workers = new Map();
    const perTeam = new Map();
    let bricks = 0;
    let cost = Rational.ZERO;
    let sale = Rational.ZERO;
    let incomplete = 0;
    for (const e of entries) {
      const d = computeDay(e, tariffs);
      if (d.status === DayStatus.INCOMPLETE || d.status === DayStatus.NO_PRESENT || d.status === DayStatus.NO_TARIFF) incomplete++;
      if (e.bricks != null) {
        bricks += e.bricks;
        const s = productionValue(tariffs, 'sale', e.date, e.bricks);
        if (s) sale = sale.add(s);
      }
      if (d.status !== DayStatus.OK) continue;
      cost = cost.add(d.total);
      perTeam.set(e.teamId, (perTeam.get(e.teamId) ?? Rational.ZERO).add(d.total));
      for (const [id, st] of Object.entries(e.presence)) {
        if (st !== 'present') continue;
        const w = workers.get(id) ?? { total: Rational.ZERO, days: 0 };
        w.total = w.total.add(d.share);
        w.days++;
        workers.set(id, w);
      }
    }

    res.json({
      from, to, label: `${frDate(from)} au ${frDate(to)}`, days,
      bricks, cost, sale, margin: sale.sub(cost), incompleteDays: incomplete,
      teams: [...perTeam.entries()].map(([id, total]) => ({ teamId: id, name: teams.get(id) ?? '—', total }))
        .sort((a, b) => a.name.localeCompare(b.name, 'fr')),
      workers: [...workers.entries()].map(([id, w]) => ({ workerId: id, fullName: names.get(id) ?? '—', days: w.days, total: w.total }))
        .sort((a, b) => a.fullName.localeCompare(b.fullName, 'fr')),
    });
  }));

  return r;
}
