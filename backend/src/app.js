import express from 'express';
import { existsSync } from 'node:fs';
import path from 'node:path';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';

import { authenticate, requireAdmin } from './middleware/auth.js';
import { errorHandler } from './middleware/errors.js';
import { PIN_COST } from './lib/pin.js';
import { authRouter } from './routes/auth.js';
import { teamsRouter } from './routes/teams.js';
import { workersRouter } from './routes/workers.js';
import { supervisorsRouter } from './routes/supervisors.js';
import { tariffsRouter } from './routes/tariffs.js';
import { daysRouter } from './routes/days.js';
import { overviewRouter } from './routes/overview.js';
import { payrollRouter } from './routes/payroll.js';
import { paymentsRouter } from './routes/payments.js';
import { auditRouter } from './routes/audit.js';
import { facesRouter } from './routes/faces.js';
import { calendarRouter } from './routes/calendar.js';
import { statsRouter } from './routes/stats.js';
import { reportsRouter } from './routes/reports.js';
import { alertsRouter } from './routes/alerts.js';
import { backupRouter } from './routes/backup.js';
import { invoicesRouter } from './routes/invoices.js';
import { createFaceService } from './services/faces.js';

/**
 * Fabrique l'application Express. `db` et `config` sont injectés : la production
 * utilise Supabase (pg), les tests utilisent PGlite avec le même schéma SQL.
 */
export function createApp({ db, config, pinCost = PIN_COST, faces = createFaceService({ threshold: config.faceThreshold ?? 0.5 }) }) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1); // derrière le proxy de l'hébergeur (IP réelle pour le rate-limit)

  // CSP désactivée : l'API ne sert que du JSON, et l'application web Flutter (CanvasKit/WebAssembly)
  // ne fonctionne pas avec la CSP stricte par défaut. Les autres en-têtes de sécurité restent actifs.
  app.use(helmet({ contentSecurityPolicy: false }));
  // Production : uniquement les origines listées dans CORS_ORIGINS.
  // Développement : tout `localhost` / `127.0.0.1`, quel que soit le port (flutter run choisit un port au hasard).
  const allowedOrigins = config.isProd
    ? config.corsOrigins
    : [...config.corsOrigins, /^http:\/\/(localhost|127\.0\.0\.1):\d+$/];
  app.use(cors({
    origin: allowedOrigins.length ? allowedOrigins : false,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  }));
  // Les photos (reconnaissance faciale) sont plus volumineuses que le reste des requêtes.
  const bigJson = express.json({ limit: '8mb' });
  app.use('/api/faces', bigJson);
  app.use(/^\/api\/workers\/[^/]+\/face$/, bigJson);
  app.use(express.json({ limit: '100kb' }));
  app.use(rateLimit({ windowMs: 60_000, limit: 300, standardHeaders: true, legacyHeaders: false }));

  const auth = authenticate({ db, config });
  const admin = requireAdmin(db);
  const deps = { db, config, auth, admin, pinCost, faces };

  app.get('/health', async (_req, res) => {
    try {
      await db.query('select 1');
      res.json({ status: 'ok' });
    } catch {
      res.status(503).json({ status: 'db_unavailable' });
    }
  });

  app.use('/api/auth', authRouter(deps));
  app.use('/api/teams', teamsRouter(deps));
  app.use('/api/workers', workersRouter(deps));
  app.use('/api/supervisors', supervisorsRouter(deps));
  app.use('/api/tariffs', tariffsRouter(deps));
  app.use('/api/days', daysRouter(deps));
  app.use('/api/overview', overviewRouter(deps));
  app.use('/api/payroll', payrollRouter(deps));
  app.use('/api/payments', paymentsRouter(deps));
  app.use('/api/audit', auditRouter(deps));
  app.use('/api/faces', facesRouter(deps));
  app.use('/api/calendar', calendarRouter(deps));
  app.use('/api/stats', statsRouter(deps));
  app.use('/api/reports', reportsRouter(deps));
  app.use('/api/alerts', alertsRouter(deps));
  app.use('/api/backup', backupRouter(deps));
  app.use('/api/invoices', invoicesRouter(deps));

  // Application web Flutter servie par la même adresse (aucun CORS, un seul déploiement).
  const index = config.publicDir && path.join(config.publicDir, 'index.html');
  if (index && existsSync(index)) {
    const noCache = /(index\.html|flutter_service_worker\.js|flutter_bootstrap\.js|version\.json)$/;
    app.use(express.static(config.publicDir, {
      setHeaders: (res, file) => { if (noCache.test(file)) res.setHeader('Cache-Control', 'no-cache'); },
    }));
    app.get(/^\/(?!api\/|health$).*/, (_req, res) => res.sendFile(index));
  }

  app.use((_req, res) => res.status(404).json({ error: 'Route introuvable.', code: 'not_found' }));
  app.use(errorHandler(config));
  return app;
}
