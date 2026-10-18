import { Router } from 'express';
import { z } from 'zod';
import { ah, conflict, notFound } from '../lib/errors.js';
import { logAudit } from '../lib/audit.js';
import { assertMonth, monthLabel, todayStr } from '../lib/dates.js';
import { Rational } from '../lib/rational.js';
import { payrollForMonth } from '../services/payroll.js';
import { advancesByWorker } from '../services/advances.js';

/**
 * Paiements : enregistrement MANUEL de ce qui a réellement été versé (aucun envoi
 * d'argent). On conserve séparément le dû exact, l'arrondi proposé et le montant
 * réellement payé : un écart n'est jamais masqué par un arrondi.
 */
export function paymentsRouter({ db, auth, admin }) {
  const r = Router();
  r.use(auth, admin);

  r.get('/', ah(async (req, res) => {
    const month = assertMonth(z.object({ month: z.string() }).parse(req.query).month);
    const p = await payrollForMonth(db, month, todayStr());
    const locked = (await db.query('select 1 from payroll_versions where month = $1 and unlocked_at is null', [month])).rowCount > 0;
    const pays = (await db.query(
      `select p.id, p.worker_id, p.paid_at, p.theoretical_exact, p.proposed, p.paid, p.mode, u.name as author
         from payments p join users u on u.id = p.created_by where p.month = $1 order by p.paid_at`,
      [month],
    )).rows;
    const names = new Map((await db.query('select id, full_name from workers')).rows.map((w) => [w.id, w.full_name]));

    const adv = await advancesByWorker(db, month);
    // Un ouvrier qui a reçu une avance apparaît même sans gain enregistré (solde négatif visible).
    const ids = new Set([...p.workers.keys(), ...adv.keys()]);
    const workers = [...ids].map((id) => {
      const w = p.workers.get(id) ?? { total: Rational.ZERO };
      const mine = pays.filter((x) => x.worker_id === id);
      const paid = mine.reduce((s, x) => s + x.paid, 0);
      const advance = adv.get(id) ?? 0;
      const balance = w.total.sub(Rational.int(advance + paid));
      return {
        workerId: id,
        fullName: names.get(id),
        due: w.total,
        advances: advance,
        paid,
        balance, // négatif = trop-perçu (visible)
        proposed: balance.roundHalfUp(),
        payments: mine.map((x) => ({
          id: x.id, paidAt: x.paid_at, theoretical: Rational.parse(x.theoretical_exact),
          proposed: x.proposed, paid: x.paid, mode: x.mode, author: x.author,
        })),
      };
    }).sort((a, b) => a.fullName.localeCompare(b.fullName, 'fr'));

    res.json({ month, label: monthLabel(month), locked, workers });
  }));

  // ── Avances sur salaire ──
  r.get('/advances', ah(async (req, res) => {
    const month = assertMonth(z.object({ month: z.string() }).parse(req.query).month);
    const rows = (await db.query(
      `select a.id, a.worker_id, w.full_name, a.amount, a.given_at, a.mode, a.note, u.name as author
         from advances a join workers w on w.id = a.worker_id join users u on u.id = a.created_by
        where a.month = $1 order by a.given_at, a.created_at`,
      [month],
    )).rows;
    const locked = (await db.query('select 1 from payroll_versions where month = $1 and unlocked_at is null', [month])).rowCount > 0;
    res.json({
      month, label: monthLabel(month), locked,
      advances: rows.map((a) => ({ id: a.id, workerId: a.worker_id, fullName: a.full_name, amount: a.amount, givenAt: a.given_at, mode: a.mode, note: a.note, author: a.author })),
    });
  }));

  r.post('/advances', ah(async (req, res) => {
    const b = z.object({
      workerId: z.string().uuid(),
      month: z.string(),
      amount: z.number().int().positive().max(100_000_000),
      mode: z.enum(['cash', 'mobile_money']),
      note: z.string().trim().max(200).optional(),
    }).parse(req.body);
    assertMonth(b.month);
    const out = await db.tx(async (q) => {
      if ((await q.query('select 1 from payroll_versions where month = $1 and unlocked_at is null', [b.month])).rowCount) {
        throw conflict('Cette paie est verrouillée : une avance ne peut plus y être ajoutée.', 'locked');
      }
      const w = (await q.query('select full_name, active from workers where id = $1', [b.workerId])).rows[0];
      if (!w) throw notFound('Ouvrier introuvable.');
      const row = (await q.query(
        'insert into advances (worker_id, month, amount, mode, note, created_by) values ($1,$2,$3,$4,$5,$6) returning id',
        [b.workerId, b.month, b.amount, b.mode, b.note || null, req.user.id],
      )).rows[0];
      await logAudit(q, req.user, { action: 'Avance sur salaire', object: w.full_name, newValue: `${b.amount} FCFA à déduire de ${monthLabel(b.month)}` });
      return { id: row.id };
    });
    res.status(201).json(out);
  }));

  r.delete('/advances/:id', ah(async (req, res) => {
    await db.tx(async (q) => {
      const a = (await q.query(
        'select a.id, a.month, a.amount, w.full_name from advances a join workers w on w.id = a.worker_id where a.id = $1', [req.params.id],
      )).rows[0];
      if (!a) throw notFound('Avance introuvable.');
      if ((await q.query('select 1 from payroll_versions where month = $1 and unlocked_at is null', [a.month])).rowCount) {
        throw conflict("Cette paie est verrouillée : l'avance ne peut plus être annulée.", 'locked');
      }
      await q.query('delete from advances where id = $1', [a.id]);
      await logAudit(q, req.user, { action: "Annulation d'avance", object: a.full_name, oldValue: `${a.amount} FCFA (${monthLabel(a.month)})` });
    });
    res.json({ ok: true });
  }));

  r.post('/', ah(async (req, res) => {
    const b = z.object({
      workerId: z.string().uuid(),
      month: z.string(),
      paid: z.number().int().positive().max(100_000_000),
      mode: z.enum(['cash', 'mobile_money']),
    }).parse(req.body);
    assertMonth(b.month);

    const out = await db.tx(async (q) => {
      if (!(await q.query('select 1 from payroll_versions where month = $1 and unlocked_at is null', [b.month])).rowCount) {
        throw conflict("Les paiements ne s'enregistrent que sur une paie validée.", 'not_locked');
      }
      const w = (await q.query('select full_name from workers where id = $1', [b.workerId])).rows[0];
      if (!w) throw notFound('Ouvrier introuvable.');

      const p = await payrollForMonth(q, b.month, todayStr());
      const share = p.workers.get(b.workerId);
      if (!share) throw conflict('Aucun montant dû à cet ouvrier pour ce mois.', 'nothing_due');

      const paidSoFar = (await q.query('select coalesce(sum(paid),0)::int as s from payments where worker_id = $1 and month = $2', [b.workerId, b.month])).rows[0].s;
      const advance = (await advancesByWorker(q, b.month)).get(b.workerId) ?? 0;
      const balance = share.total.sub(Rational.int(advance + paidSoFar));
      const proposed = balance.roundHalfUp();

      const row = (await q.query(
        `insert into payments (worker_id, month, theoretical_exact, proposed, paid, mode, created_by)
         values ($1,$2,$3,$4,$5,$6,$7) returning id`,
        [b.workerId, b.month, balance.toString(), proposed, b.paid, b.mode, req.user.id],
      )).rows[0];

      await logAudit(q, req.user, {
        action: 'Enregistrement de paiement',
        object: w.full_name,
        newValue: `${b.paid} FCFA (dû exact ${balance.toFixed(2)})`,
      });
      return { id: row.id, theoretical: balance, proposed, paid: b.paid, newBalance: balance.sub(Rational.int(b.paid)) };
    });
    res.status(201).json(out);
  }));

  return r;
}
