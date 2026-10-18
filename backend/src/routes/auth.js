import bcrypt from 'bcryptjs';
import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { ah, unauthorized, HttpError } from '../lib/errors.js';
import { logAudit } from '../lib/audit.js';
import { hashPin, pinSchema, verifyPin } from '../lib/pin.js';
import { signToken } from '../middleware/auth.js';

export const MAX_ATTEMPTS = 5;
export const LOCK_SECONDS = 30;

const loginSchema = z.object({ name: z.string().trim().min(1).max(100), pin: z.string().min(1).max(12) });

// Hash factice : on compare toujours un PIN pour ne pas révéler si le nom existe (timing).
const DUMMY = bcrypt.hashSync('hash-factice', 10);

export function authRouter({ db, config, auth }) {
  const r = Router();

  const limiter = rateLimit({
    windowMs: 60_000,
    limit: 20,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'Trop de requêtes. Patientez une minute.', code: 'rate_limited' },
  });

  // Connexion : nom + code PIN. Message identique si le nom est inconnu ou le code faux.
  r.post('/login', limiter, ah(async (req, res) => {
    const { name, pin } = loginSchema.parse(req.body);
    const { rows } = await db.query('select * from users where lower(name) = lower($1) and active', [name]);
    const u = rows[0];

    if (!u) {
      await verifyPin(pin, DUMMY);
      throw unauthorized('Nom ou code incorrect.');
    }
    if (u.locked_until && new Date(u.locked_until) > new Date()) {
      const s = Math.ceil((new Date(u.locked_until) - new Date()) / 1000);
      throw new HttpError(423, `Compte verrouillé. Réessayez dans ${s} s.`, 'locked');
    }

    const actor = { id: u.id, name: u.name, role: u.role };
    if (!(await verifyPin(pin, u.pin_hash))) {
      const attempts = u.failed_attempts + 1;
      const lock = attempts >= MAX_ATTEMPTS;
      await db.query(
        'update users set failed_attempts = $2, locked_until = $3 where id = $1',
        [u.id, lock ? 0 : attempts, lock ? new Date(Date.now() + LOCK_SECONDS * 1000) : null],
      );
      await logAudit(db, actor, {
        action: 'Échec de connexion',
        object: u.name,
        reason: `Tentative ${attempts}/${MAX_ATTEMPTS}`,
        security: true,
      });
      if (lock) throw new HttpError(423, `Trop de tentatives. Compte verrouillé ${LOCK_SECONDS} s.`, 'locked');
      throw unauthorized(`Nom ou code incorrect (${MAX_ATTEMPTS - attempts} essai(s) restant(s)).`);
    }

    await db.query('update users set failed_attempts = 0, locked_until = null, last_seen_at = now() where id = $1', [u.id]);
    await logAudit(db, actor, { action: 'Connexion', object: u.name });
    res.json({
      token: signToken(config, u),
      user: { id: u.id, name: u.name, role: u.role, workerId: u.worker_id },
    });
  }));

  // Déconnexion : l'utilisateur n'apparaît plus comme « connecté ».
  r.post('/logout', auth, ah(async (req, res) => {
    await db.query('update users set last_seen_at = null where id = $1', [req.user.id]);
    await logAudit(db, req.user, { action: 'Déconnexion', object: req.user.name });
    res.json({ ok: true });
  }));

  r.get('/me', auth, ah(async (req, res) => {
    const { rows } = await db.query(
      `select t.id, t.name, (t.chief_id = $1) as is_chief
         from teams t where t.chief_id = $1 or t.interim_id = $1 order by t.name`,
      [req.user.id],
    );
    res.json({
      user: req.user,
      teams: rows.map((t) => ({ id: t.id, name: t.name, role: t.is_chief ? 'titulaire' : 'remplaçant' })),
    });
  }));

  // Changement de son propre PIN.
  r.put('/pin', auth, ah(async (req, res) => {
    const { currentPin, newPin } = z.object({ currentPin: z.string().min(1), newPin: pinSchema }).parse(req.body);
    const { rows } = await db.query('select pin_hash from users where id = $1', [req.user.id]);
    if (!(await verifyPin(currentPin, rows[0].pin_hash))) throw unauthorized('Code actuel incorrect.');
    await db.query('update users set pin_hash = $2 where id = $1', [req.user.id, await hashPin(newPin)]);
    await logAudit(db, req.user, { action: 'Changement de PIN', object: req.user.name });
    res.json({ ok: true });
  }));

  return r;
}
