import { Router } from 'express';
import { z } from 'zod';
import { ah, badRequest, conflict } from '../lib/errors.js';
import { logAudit } from '../lib/audit.js';
import { assertDate, frDate, todayStr } from '../lib/dates.js';
import { requireTeamAccess } from '../services/access.js';
import { loadCalendar, nonWorkingMessage, resolveDay } from '../services/calendar.js';
import { dayView, nextDay } from '../services/days.js';
import { loadEntries } from '../services/payroll.js';

const uuid = z.string().uuid();

const putSchema = z.object({
  teamId: uuid,
  date: z.string(),
  // nombre de briques confectionnées (entier >= 0), null = non saisi
  bricks: z.number().int().min(0).max(10_000_000).nullable(),
  presences: z.array(z.object({
    workerId: uuid,
    status: z.enum(['present', 'absent', 'unset']),
    isSubstitute: z.boolean().default(false),
    faceVerified: z.boolean().default(false),
    // motif d'une absence (facultatif)
    absenceReason: z.enum(['sick', 'permission', 'unjustified', 'other']).nullable().optional(),
  })).max(60),
  // ── Synchronisation hors ligne ──
  // Version de la journée connue de l'appareil (null = aucune saisie connue). Si la journée a changé
  // entre-temps (autre appareil, correction de l'admin), la saisie est refusée (409 « stale »).
  baseVersion: z.string().nullable().optional(),
  // Identifiant de cette saisie : un renvoi après coupure réseau n'est jamais appliqué deux fois.
  requestId: uuid.optional(),
  // « Garder ma saisie » : écrase la version du serveur après arbitrage de l'utilisateur.
  force: z.boolean().optional(),
});

const summary = (e) => {
  const c = (s) => Object.values(e.presence).filter((x) => x === s).length;
  return `Briques : ${e.bricks ?? '—'} · présents ${c('present')}, absents ${c('absent')}, non saisis ${c('unset')}`;
};

/**
 * Saisie d'une journée. Le superviseur (titulaire ou remplaçant) n'envoie et ne
 * reçoit QUE présences et nombre de briques : aucun prix ni montant ne lui est
 * jamais transmis. Les calculs sont réservés à l'admin (`calc`).
 */
export function daysRouter({ db, auth }) {
  const r = Router();
  r.use(auth);

  r.get('/', ah(async (req, res) => {
    const { teamId, date } = z.object({ teamId: uuid, date: z.string() }).parse(req.query);
    assertDate(date);
    await requireTeamAccess(db, req.user, teamId);
    res.json(await dayView(db, { teamId, date, viewerWorkerId: req.user.workerId, withCalc: req.user.role === 'admin' }));
  }));

  // Ouvriers que le superviseur peut ajouter comme remplaçants ce jour-là :
  // actifs, hors de la saisie du jour, et pas déjà présents dans une autre équipe.
  r.get('/substitutes', ah(async (req, res) => {
    const { teamId, date } = z.object({ teamId: uuid, date: z.string() }).parse(req.query);
    assertDate(date);
    await requireTeamAccess(db, req.user, teamId);
    const { rows } = await db.query(
      `select w.id, w.full_name, w.face_enrolled, t.name as team_name
         from workers w left join teams t on t.id = w.team_id
        where w.active
          and not exists (select 1 from day_entries e join day_presences p on p.entry_id = e.id
                           where e.team_id = $1 and e.work_date = $2 and p.worker_id = w.id)
          and not exists (select 1 from day_presences p where p.worker_id = w.id and p.work_date = $2 and p.status = 'present')
          and (w.team_id is distinct from $1)
        order by w.full_name`,
      [teamId, date],
    );
    res.json(rows.map((w) => ({ workerId: w.id, fullName: w.full_name, teamName: w.team_name, faceEnrolled: w.face_enrolled })));
  }));

  r.put('/', ah(async (req, res) => {
    const b = putSchema.parse(req.body);
    assertDate(b.date);
    const team = await requireTeamAccess(db, req.user, b.teamId);
    if (b.date > todayStr()) throw badRequest('Impossible de saisir une date future.');

    const ids = b.presences.map((p) => p.workerId);
    if (new Set(ids).size !== ids.length) throw badRequest('Un ouvrier apparaît deux fois dans la même équipe.');
    for (const p of b.presences) {
      if (p.faceVerified && p.status !== 'present') throw badRequest("Une identification faciale ne s'applique qu'à un présent.");
      if (p.absenceReason && p.status !== 'absent') throw badRequest("Un motif d'absence ne s'applique qu'à un absent.");
    }

    try {
      await db.tx(async (q) => {
        if ((await q.query('select month_is_locked($1::date) as l', [b.date])).rows[0].l) {
          throw conflict(`La paie de ${b.date.slice(0, 7)} est verrouillée : modification refusée.`, 'locked');
        }

        // Jour non travaillé selon le calendrier (repos, férié, intempérie, panne…).
        const info = resolveDay(await loadCalendar(q, b.date, nextDay(b.date)), b.date, b.teamId);
        if (!info.working) throw conflict(nonWorkingMessage(info), 'non_working_day');

        // Verrou de la ligne : deux appareils qui envoient en même temps sont traités l'un après l'autre.
        const current = (await q.query(
          `select id, last_request_id,
                  to_char(updated_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as version
             from day_entries where team_id = $1 and work_date = $2 for update`,
          [b.teamId, b.date],
        )).rows[0];

        // Rejeu d'une saisie déjà appliquée (réponse perdue puis renvoi) : succès, sans rien réécrire.
        if (current && b.requestId && current.last_request_id === b.requestId) return;

        // Conflit : la journée a changé depuis la version connue de l'appareil.
        if (!b.force && 'baseVersion' in req.body) {
          const known = b.baseVersion ?? null;
          const now = current?.version ?? null;
          if (known !== now) {
            throw conflict(
              now === null
                ? 'Cette journée a été supprimée ou n\'existe plus sur le serveur.'
                : known === null
                  ? 'Cette journée a déjà été saisie par quelqu\'un d\'autre pendant que vous étiez hors ligne.'
                  : 'Cette journée a été modifiée par quelqu\'un d\'autre pendant que vous étiez hors ligne.',
              'stale',
            );
          }
        }

        const [prev] = await loadEntries(q, b.date, nextDay(b.date), { teamId: b.teamId });

        // Composition : membres actifs actuels + ouvriers déjà présents dans la saisie précédente.
        const active = new Set((await q.query('select id from workers where team_id = $1 and active', [b.teamId])).rows.map((x) => x.id));
        const previous = new Set(prev ? Object.keys(prev.presence) : []);
        for (const p of b.presences) {
          if (!p.isSubstitute && !active.has(p.workerId) && !previous.has(p.workerId)) {
            throw badRequest("Un ouvrier n'appartient pas à cette équipe (utilisez « remplaçant »).");
          }
          if (p.isSubstitute) {
            const w = (await q.query('select active from workers where id = $1', [p.workerId])).rows[0];
            if (!w?.active) throw badRequest('Remplaçant introuvable ou inactif.');
          }
        }
        // Les membres oubliés restent explicitement « non saisi » (jamais « absent »).
        const sent = new Set(ids);
        const presences = [
          ...b.presences,
          ...[...active].filter((id) => !sent.has(id)).map((id) => ({ workerId: id, status: 'unset', isSubstitute: false, faceVerified: false, absenceReason: null })),
        ];

        const entry = (await q.query(
          `insert into day_entries (team_id, work_date, entered_by, bricks, last_request_id) values ($1,$2,$3,$4,$5)
           on conflict (team_id, work_date) do update
             set entered_by = excluded.entered_by, bricks = excluded.bricks, last_request_id = excluded.last_request_id
           returning id`,
          [b.teamId, b.date, req.user.id, b.bricks, b.requestId ?? null],
        )).rows[0];

        await q.query('delete from day_presences where entry_id = $1', [entry.id]);
        for (const p of presences) {
          await q.query(
            `insert into day_presences (entry_id, worker_id, work_date, status, is_substitute, face_verified, absence_reason)
             values ($1,$2,$3,$4,$5,$6,$7)`,
            [entry.id, p.workerId, b.date, p.status, p.isSubstitute, p.faceVerified, p.absenceReason ?? null],
          );
        }

        const next = {
          bricks: b.bricks,
          presence: Object.fromEntries(presences.map((p) => [p.workerId, p.status])),
        };
        await logAudit(q, req.user, {
          action: prev ? 'Modification de journée' : 'Saisie de journée',
          object: `${team.name} · ${frDate(b.date)}`,
          oldValue: prev ? summary(prev) : null,
          newValue: summary(next) + (b.force ? ' · saisie conservée après conflit' : ''),
        });
      });
    } catch (e) {
      if (e?.constraint === 'one_presence_per_day_uq' || /one_presence_per_day_uq/.test(e?.message ?? '')) {
        throw conflict('Un ouvrier est déjà marqué présent dans une autre équipe ce jour-là.', 'double_presence');
      }
      throw e;
    }

    res.json(await dayView(db, { teamId: b.teamId, date: b.date, viewerWorkerId: req.user.workerId, withCalc: req.user.role === 'admin' }));
  }));

  return r;
}
