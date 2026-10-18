import { Router } from 'express';
import { z } from 'zod';
import { ah } from '../lib/errors.js';
import { assertDate, todayStr } from '../lib/dates.js';
import { Rational } from '../lib/rational.js';
import { dayView } from '../services/days.js';
import { loadTariffs, rateFor } from '../services/payroll.js';

/**
 * Tableau de bord admin : qui est là, qui est absent, briques confectionnées,
 * coût de confection (175), valeur de vente (250) et marge du jour.
 */
// Une personne est « connectée » si on l'a vue il y a moins de 5 minutes (= délai de verrouillage de l'application).
const ONLINE_MINUTES = 5;

export function overviewRouter({ db, auth, admin }) {
  const r = Router();
  r.use(auth, admin);

  r.get('/', ah(async (req, res) => {
    const { date = todayStr() } = z.object({ date: z.string().optional() }).parse(req.query);
    assertDate(date);

    const teams = (await db.query(
      `select t.id, t.name, c.name as chief_name, i.name as interim_name
         from teams t left join users c on c.id = t.chief_id left join users i on i.id = t.interim_id order by t.name`,
    )).rows;
    const tariffs = await loadTariffs(db);

    const views = [];
    for (const t of teams) {
      views.push({ team: t, view: await dayView(db, { teamId: t.id, date, viewerWorkerId: null, withCalc: true }) });
    }

    const totals = { present: 0, absent: 0, unset: 0, teamsWithoutEntry: 0 };
    let bricks = 0;
    let cost = Rational.ZERO;
    let sale = Rational.ZERO;
    for (const { view } of views) {
      if (!view.saved) { totals.teamsWithoutEntry++; continue; }
      totals.present += view.counts.present;
      totals.absent += view.counts.absent;
      totals.unset += view.counts.unset;
      bricks += view.calc.bricks ?? 0;
      cost = cost.add(view.calc.cost);
      sale = sale.add(view.calc.sale);
    }

    const w = (await db.query(
      `select count(*)::int as total,
              count(*) filter (where active)::int as active,
              count(*) filter (where active and face_enrolled)::int as with_face
         from workers`,
    )).rows[0];
    const sup = (await db.query("select count(*)::int as n from users where role = 'chief' and active")).rows[0].n;
    const online = (await db.query(
      `select u.id, u.name, u.role, u.last_seen_at,
              (select string_agg(t.name, ', ' order by t.name) from teams t
                where t.chief_id = u.id or t.interim_id = u.id) as teams
         from users u
        where u.active and u.last_seen_at > now() - ($1 || ' minutes')::interval
        order by u.last_seen_at desc`,
      [String(ONLINE_MINUTES)],
    )).rows;

    res.json({
      date,
      workers: { total: w.total, active: w.active, withFace: w.with_face, supervisors: sup },
      online: online.map((u) => ({
        id: u.id, name: u.name, role: u.role, teams: u.teams, lastSeenAt: u.last_seen_at, isMe: u.id === req.user.id,
      })),
      onlineWindowMinutes: ONLINE_MINUTES,
      totals,
      production: {
        bricks,
        costRate: rateFor(tariffs, 'cost', date),
        saleRate: rateFor(tariffs, 'sale', date),
        cost,                 // payé aux équipes (base de paie)
        sale,                 // chiffre d'affaires
        margin: sale.sub(cost),
      },
      teams: views.map(({ team, view }) => ({
        teamId: team.id,
        name: team.name,
        chief: team.chief_name,
        interim: team.interim_name,
        saved: view.saved,
        locked: view.locked,
        counts: view.counts,
        enteredBy: view.enteredBy ?? null,
        status: view.saved ? view.calc.status : 'no_entry',
        bricks: view.bricks,
        cost: view.calc.cost,
        sale: view.calc.sale,
        share: view.calc.share,
        members: view.members.map((m) => ({ workerId: m.workerId, fullName: m.fullName, status: m.status, faceVerified: m.faceVerified, isSubstitute: m.isSubstitute })),
      })),
    });
  }));

  return r;
}
