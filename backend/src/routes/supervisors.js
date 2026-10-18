import { Router } from 'express';
import { z } from 'zod';
import { ah, conflict, notFound } from '../lib/errors.js';
import { logAudit } from '../lib/audit.js';
import { hashPin, pinSchema } from '../lib/pin.js';

const uuid = z.string().uuid();

/**
 * Un superviseur EST l'un des ouvriers : l'admin choisit un ouvrier déjà
 * enregistré et lui attribue un code PIN. Il se connecte ensuite avec son nom
 * et ce code, et voit les autres membres de son équipe.
 */
export function supervisorsRouter({ db, auth, admin, pinCost }) {
  const r = Router();
  r.use(auth, admin);

  r.get('/', ah(async (_req, res) => {
    const { rows } = await db.query(
      `select u.id, u.name, u.active, u.worker_id, w.team_id, t.name as team_name,
              (select array_agg(tt.name order by tt.name) from teams tt where tt.chief_id = u.id) as chief_of,
              (select array_agg(tt.name order by tt.name) from teams tt where tt.interim_id = u.id) as interim_of
         from users u join workers w on w.id = u.worker_id left join teams t on t.id = w.team_id
        where u.role = 'chief' order by u.name`,
    );
    res.json(rows.map((u) => ({
      id: u.id, name: u.name, active: u.active, workerId: u.worker_id,
      teamId: u.team_id, teamName: u.team_name,
      chiefOf: u.chief_of ?? [], interimOf: u.interim_of ?? [],
    })));
  }));

  r.post('/', ah(async (req, res) => {
    const { workerId, pin } = z.object({ workerId: uuid, pin: pinSchema }).parse(req.body);
    const pinHash = await hashPin(pin, pinCost);
    const user = await db.tx(async (q) => {
      const w = (await q.query('select id, full_name, team_id, active from workers where id = $1 for update', [workerId])).rows[0];
      if (!w || !w.active) throw notFound('Ouvrier actif introuvable.');
      if ((await q.query('select 1 from users where worker_id = $1', [workerId])).rowCount) {
        throw conflict('Cet ouvrier a déjà un accès.');
      }
      const u = (await q.query(
        "insert into users (name, role, worker_id, pin_hash) values ($1, 'chief', $2, $3) returning id, name",
        [w.full_name, workerId, pinHash],
      )).rows[0];
      let teamName = null;
      if (w.team_id) {
        const t = (await q.query('select name, chief_id from teams where id = $1 for update', [w.team_id])).rows[0];
        teamName = t.name;
        if (!t.chief_id) await q.query('update teams set chief_id = $2 where id = $1', [w.team_id, u.id]);
      }
      await logAudit(q, req.user, { action: 'Création de superviseur', object: u.name, newValue: teamName });
      return u;
    });
    // Le code n'est jamais renvoyé : l'admin le connaît puisqu'il l'a saisi.
    res.status(201).json({ id: user.id, name: user.name });
  }));

  // Réinitialisation du code (récupération d'accès, tracée).
  r.put('/:id/pin', ah(async (req, res) => {
    const { pin } = z.object({ pin: pinSchema }).parse(req.body);
    const hash = await hashPin(pin, pinCost);
    await db.tx(async (q) => {
      const u = (await q.query("select name from users where id = $1 and role = 'chief'", [req.params.id])).rows[0];
      if (!u) throw notFound('Superviseur introuvable.');
      await q.query('update users set pin_hash = $2, failed_attempts = 0, locked_until = null where id = $1', [req.params.id, hash]);
      await logAudit(q, req.user, { action: 'Réinitialisation du PIN', object: u.name });
    });
    res.json({ ok: true });
  }));

  r.patch('/:id', ah(async (req, res) => {
    const { active } = z.object({ active: z.boolean() }).parse(req.body);
    await db.tx(async (q) => {
      const u = (await q.query("select name from users where id = $1 and role = 'chief'", [req.params.id])).rows[0];
      if (!u) throw notFound('Superviseur introuvable.');
      await q.query('update users set active = $2 where id = $1', [req.params.id, active]);
      await logAudit(q, req.user, { action: active ? 'Réactivation de compte' : 'Désactivation de compte', object: u.name });
    });
    res.json({ ok: true });
  }));

  return r;
}
