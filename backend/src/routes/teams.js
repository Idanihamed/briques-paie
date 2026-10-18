import { Router } from 'express';
import { z } from 'zod';
import { ah, badRequest, conflict, notFound } from '../lib/errors.js';
import { logAudit } from '../lib/audit.js';
import { teamsOf } from '../services/access.js';

const uuid = z.string().uuid();

export function teamsRouter({ db, auth, admin }) {
  const r = Router();
  r.use(auth);

  // Admin : toutes les équipes. Superviseur : son équipe et celle qu'il remplace.
  r.get('/', ah(async (req, res) => {
    const teams = await teamsOf(db, req.user);
    const ids = teams.map((t) => t.id);
    const { rows } = await db.query(
      `select t.id, t.name, t.chief_id, c.name as chief_name, t.interim_id, i.name as interim_name,
              (select count(*)::int from workers w where w.team_id = t.id and w.active) as members
         from teams t
         left join users c on c.id = t.chief_id
         left join users i on i.id = t.interim_id
        where t.id = any($1::uuid[]) order by t.name`,
      [ids],
    );
    res.json(rows.map((t) => ({
      id: t.id,
      name: t.name,
      chief: t.chief_id ? { id: t.chief_id, name: t.chief_name } : null,
      interim: t.interim_id ? { id: t.interim_id, name: t.interim_name } : null,
      members: t.members,
    })));
  }));

  r.post('/', admin, ah(async (req, res) => {
    const { name } = z.object({ name: z.string().trim().min(1).max(80) }).parse(req.body);
    const team = await db.tx(async (q) => {
      const { rows } = await q.query('insert into teams (name) values ($1) returning id, name', [name]);
      await logAudit(q, req.user, { action: "Création d'équipe", object: name });
      return rows[0];
    });
    res.status(201).json(team);
  }));

  // Titulaire.
  r.put('/:id/chief', admin, ah(async (req, res) => {
    const { userId } = z.object({ userId: uuid.nullable() }).parse(req.body);
    await setSupervisor(db, req, req.params.id, userId, 'chief_id', 'Affectation du superviseur');
    res.json({ ok: true });
  }));

  // Remplaçant désigné par l'admin quand le titulaire est absent.
  r.put('/:id/interim', admin, ah(async (req, res) => {
    const { userId } = z.object({ userId: uuid.nullable() }).parse(req.body);
    await setSupervisor(db, req, req.params.id, userId, 'interim_id', 'Remplacement de superviseur');
    res.json({ ok: true });
  }));

  return r;
}

async function setSupervisor(db, req, teamId, userId, column, action) {
  await db.tx(async (q) => {
    const t = (await q.query(
      `select t.id, t.name, t.chief_id, t.interim_id, c.name as chief_name, i.name as interim_name
         from teams t left join users c on c.id = t.chief_id left join users i on i.id = t.interim_id
        where t.id = $1 for update of t`,
      [teamId],
    )).rows[0];
    if (!t) throw notFound('Équipe introuvable.');

    let newName = null;
    if (userId) {
      const u = (await q.query("select id, name, role, active from users where id = $1", [userId])).rows[0];
      if (!u || !u.active || u.role !== 'chief') throw badRequest('Ce compte n\'est pas un superviseur actif.');
      const other = column === 'chief_id' ? t.interim_id : t.chief_id;
      if (other === userId) throw conflict('Ce superviseur est déjà titulaire ou remplaçant de cette équipe.');
      newName = u.name;
    }
    const oldName = column === 'chief_id' ? t.chief_name : t.interim_name;
    await q.query(`update teams set ${column} = $2 where id = $1`, [teamId, userId]);
    await logAudit(q, req.user, {
      action,
      object: t.name,
      oldValue: oldName,
      newValue: newName ?? (column === 'interim_id' ? 'fin du remplacement' : null),
    });
  });
}
