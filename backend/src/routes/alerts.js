import { Router } from 'express';
import { ah } from '../lib/errors.js';
import { todayStr } from '../lib/dates.js';
import { buildAlerts } from '../services/alerts.js';

export function alertsRouter({ db, auth, admin }) {
  const r = Router();
  r.use(auth, admin);
  r.get('/', ah(async (_req, res) => {
    const alerts = await buildAlerts(db, todayStr());
    res.json({ count: alerts.length, high: alerts.filter((a) => a.level === 'high').length, alerts });
  }));
  return r;
}
