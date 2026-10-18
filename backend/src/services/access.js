import { forbidden, notFound } from '../lib/errors.js';
import { logAudit } from '../lib/audit.js';

/**
 * Un admin accède à toutes les équipes. Un superviseur accède à son équipe
 * (titulaire) ou à celle qu'il remplace (interim). Retourne la ligne de l'équipe.
 */
export async function requireTeamAccess(db, user, teamId) {
  const { rows } = await db.query('select id, name, chief_id, interim_id from teams where id = $1', [teamId]);
  const team = rows[0];
  if (!team) throw notFound('Équipe introuvable.');
  if (user.role === 'admin') return team;
  if (team.chief_id === user.id || team.interim_id === user.id) return team;
  await logAudit(db, user, {
    action: 'Accès refusé',
    object: `Équipe ${team.name}`,
    reason: 'Équipe non autorisée pour ce superviseur',
    security: true,
  });
  throw forbidden('Vous ne pouvez pas accéder à cette équipe.');
}

export async function teamsOf(db, user) {
  if (user.role === 'admin') {
    return (await db.query('select id, name, chief_id, interim_id from teams order by name')).rows;
  }
  return (
    await db.query(
      'select id, name, chief_id, interim_id from teams where chief_id = $1 or interim_id = $1 order by name',
      [user.id],
    )
  ).rows;
}
