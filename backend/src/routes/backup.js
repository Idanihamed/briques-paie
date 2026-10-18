import { Router } from 'express';
import { ah } from '../lib/errors.js';
import { logAudit } from '../lib/audit.js';
import { buildBackup } from '../services/backup.js';

/** Export de sauvegarde (JSON) réservé à l'admin ; chaque export est tracé. */
export function backupRouter({ db, auth, admin }) {
  const r = Router();
  r.use(auth, admin);

  r.get('/', ah(async (req, res) => {
    const b = await buildBackup(db);
    await logAudit(db, req.user, { action: 'Export de sauvegarde', object: 'Toutes les données', newValue: JSON.stringify(b.counts) });
    res.set({
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Disposition': `attachment; filename="sauvegarde-${b.createdAt.slice(0, 10)}.json"`,
      'Cache-Control': 'no-store',
    });
    res.send(JSON.stringify(b));
  }));

  return r;
}
