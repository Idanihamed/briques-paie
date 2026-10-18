import { Router } from 'express';
import { z } from 'zod';
import { ah } from '../lib/errors.js';

/** Journal d'audit : lecture seule, pagination par curseur (id décroissant). */
export function auditRouter({ db, auth, admin }) {
  const r = Router();
  r.use(auth, admin);

  r.get('/', ah(async (req, res) => {
    const q = z.object({
      limit: z.coerce.number().int().min(1).max(200).default(50),
      before: z.coerce.number().int().positive().optional(),
      securityOnly: z.enum(['true', 'false']).default('false'),
    }).parse(req.query);

    const { rows } = await db.query(
      `select id, at, user_name, role, action, object, old_value, new_value, reason, security
         from audit_log
        where ($1::bigint is null or id < $1) and ($2::boolean = false or security)
        order by id desc limit $3`,
      [q.before ?? null, q.securityOnly === 'true', q.limit],
    );
    res.json({
      items: rows.map((a) => ({
        id: Number(a.id), at: a.at, user: a.user_name, role: a.role, action: a.action, object: a.object,
        oldValue: a.old_value, newValue: a.new_value, reason: a.reason, security: a.security,
      })),
      next: rows.length === q.limit ? Number(rows.at(-1).id) : null,
    });
  }));

  return r;
}
