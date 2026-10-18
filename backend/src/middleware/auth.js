import jwt from 'jsonwebtoken';
import { forbidden, unauthorized, ah } from '../lib/errors.js';
import { logAudit } from '../lib/audit.js';

export function signToken(config, user) {
  return jwt.sign({ sub: user.id, role: user.role }, config.jwtSecret, {
    expiresIn: config.jwtTtl,
    algorithm: 'HS256',
  });
}

/**
 * Vérifie le jeton PUIS recharge l'utilisateur en base : un compte désactivé
 * ou un rôle changé est pris en compte immédiatement (pas de droits périmés).
 */
export function authenticate({ db, config }) {
  return ah(async (req, _res, next) => {
    const header = req.headers.authorization ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) throw unauthorized();
    let payload;
    try {
      payload = jwt.verify(token, config.jwtSecret, { algorithms: ['HS256'] });
    } catch {
      throw unauthorized('Session expirée. Reconnectez-vous.');
    }
    const { rows } = await db.query(
      'select id, name, role, worker_id, active from users where id = $1',
      [payload.sub],
    );
    const u = rows[0];
    if (!u || !u.active) throw unauthorized('Compte désactivé ou introuvable.');
    req.user = { id: u.id, name: u.name, role: u.role, workerId: u.worker_id };
    // Présence en ligne : mise à jour espacée, en arrière-plan.
    db.query(
      `update users set last_seen_at = now()
        where id = $1 and (last_seen_at is null or last_seen_at < now() - interval '30 seconds')`,
      [u.id],
    ).catch(() => {});
    next();
  });
}

/** Réserve une route à l'admin. Tout refus est tracé (événement de sécurité). */
export function requireAdmin(db) {
  return ah(async (req, _res, next) => {
    if (req.user?.role !== 'admin') {
      await logAudit(db, req.user, {
        action: 'Accès refusé',
        object: `${req.method} ${req.originalUrl.split('?')[0]}`,
        reason: 'Rôle admin requis',
        security: true,
      });
      throw forbidden();
    }
    next();
  });
}
