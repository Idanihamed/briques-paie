import { Router } from 'express';
import { z } from 'zod';
import { ah } from '../lib/errors.js';
import { logAudit } from '../lib/audit.js';
import { assertDate, frDate, todayStr } from '../lib/dates.js';
import { rateFor } from '../services/payroll.js';

const KINDS = {
  cost: { label: 'Prix de confection', hint: "Payé à l'équipe par brique confectionnée (base de paie)" },
  sale: { label: 'Prix de vente', hint: 'Prix de vente unitaire de la brique (chiffre d\'affaires)' },
};

/**
 * Prix : réservés à l'admin (le superviseur ne voit jamais un prix).
 * Historique en ajout seul (trigger) : un changement = une nouvelle ligne avec
 * date d'effet, motif, auteur et horodatage.
 */
export function tariffsRouter({ db, auth, admin }) {
  const r = Router();
  r.use(auth, admin);

  r.get('/', ah(async (_req, res) => {
    const tariffs = (await db.query(
      `select t.id, t.kind, t.value, t.effective_date, t.reason, t.created_at, u.name as author
         from tariffs t join users u on u.id = t.created_by
        order by t.effective_date desc, t.created_at desc`,
    )).rows;
    const today = todayStr();
    res.json(Object.entries(KINDS).map(([kind, meta]) => ({
      kind,
      label: meta.label,
      hint: meta.hint,
      current: rateFor(tariffs, kind, today),
      history: tariffs.filter((t) => t.kind === kind).map((t) => ({
        id: t.id, value: t.value, effectiveDate: t.effective_date,
        reason: t.reason, author: t.author, recordedAt: t.created_at,
      })),
    })));
  }));

  r.post('/', ah(async (req, res) => {
    const b = z.object({
      kind: z.enum(['cost', 'sale']),
      value: z.number().int().positive().max(1_000_000),
      effectiveDate: z.string(),
      reason: z.string().trim().min(3, 'Le motif est obligatoire.').max(300),
    }).parse(req.body);
    assertDate(b.effectiveDate, "date d'effet");

    await db.tx(async (q) => {
      const tariffs = (await q.query('select kind, value, effective_date, created_at from tariffs')).rows;
      const old = rateFor(tariffs, b.kind, b.effectiveDate);
      // Le trigger SQL refuse un tarif qui toucherait un mois verrouillé.
      await q.query(
        'insert into tariffs (kind, value, effective_date, reason, created_by) values ($1,$2,$3,$4,$5)',
        [b.kind, b.value, b.effectiveDate, b.reason, req.user.id],
      );
      await logAudit(q, req.user, {
        action: 'Modification du tarif',
        object: KINDS[b.kind].label,
        oldValue: old == null ? null : `${old} FCFA`,
        newValue: `${b.value} FCFA dès le ${frDate(b.effectiveDate)}`,
        reason: b.reason,
      });
    });
    res.status(201).json({ ok: true });
  }));

  return r;
}
