import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { ah, badRequest, conflict, notFound } from '../lib/errors.js';
import { logAudit } from '../lib/audit.js';
import { decryptTemplate } from '../lib/crypto.js';
import { fromBuffer } from '../services/faces.js';

export const imageSchema = z.string().min(200).max(4_000_000);

export function decodeImage(b64) {
  const buf = Buffer.from(b64.replace(/^data:image\/\w+;base64,/, ''), 'base64');
  if (buf.length < 100) throw badRequest('Image invalide.');
  return buf;
}

/**
 * Vérification d'identité par le visage : l'application envoie une photo, le
 * serveur la compare à la signature enregistrée de l'ouvrier choisi, puis jette
 * la photo. Réponse : { match, distance }.
 */
export function facesRouter({ db, config, auth, faces }) {
  const r = Router();
  r.use(auth);
  r.use(rateLimit({
    windowMs: 60_000,
    limit: 60,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'Trop de vérifications. Patientez une minute.', code: 'rate_limited' },
  }));

  r.post('/verify', ah(async (req, res) => {
    const { workerId, image } = z.object({ workerId: z.string().uuid(), image: imageSchema }).parse(req.body);

    const w = (await db.query('select full_name, active, face_template from workers where id = $1', [workerId])).rows[0];
    if (!w || !w.active) throw notFound('Ouvrier introuvable.');
    if (!w.face_template) throw conflict("Le visage de cet ouvrier n'est pas enregistré.", 'not_enrolled');

    const probe = await faces.describe(decodeImage(image));
    const stored = fromBuffer(decryptTemplate(config.faceKey, w.face_template));
    const distance = faces.distance(probe, stored);
    const match = distance <= faces.threshold;

    if (!match) {
      await logAudit(db, req.user, {
        action: 'Visage non reconnu',
        object: w.full_name,
        reason: `Distance ${distance.toFixed(3)} > seuil ${faces.threshold}`,
        security: true,
      });
    }
    res.json({ match, distance: Number(distance.toFixed(3)) });
  }));

  return r;
}
