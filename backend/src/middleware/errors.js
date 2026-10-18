import { ZodError } from 'zod';
import { HttpError } from '../lib/errors.js';

/** Convertit toute erreur en réponse JSON propre, sans fuite d'information interne. */
export function errorHandler({ isProd }) {
  // eslint-disable-next-line no-unused-vars
  return (err, req, res, _next) => {
    if (err instanceof HttpError) {
      return res.status(err.status).json({ error: err.message, code: err.code });
    }
    if (err instanceof ZodError) {
      return res.status(400).json({
        error: 'Données invalides.',
        code: 'validation',
        details: err.issues.map((i) => ({ champ: i.path.join('.'), message: i.message })),
      });
    }
    // Erreurs PostgreSQL
    if (err?.code === 'P0001') {
      // exception levée par un trigger/règle de la base (mois verrouillé, ajout seul…)
      return res.status(409).json({ error: err.message, code: 'rule_violation' });
    }
    if (err?.code === '23505') {
      return res.status(409).json({ error: 'Cet enregistrement existe déjà ou entre en conflit.', code: 'duplicate' });
    }
    if (err?.code === '23503') {
      return res.status(409).json({ error: 'Référence invalide ou encore utilisée.', code: 'reference' });
    }
    if (err?.code === '23514' || err?.code === '22P02') {
      return res.status(400).json({ error: 'Valeur refusée par la base de données.', code: 'check' });
    }
    if (err?.type === 'entity.parse.failed') {
      return res.status(400).json({ error: 'JSON invalide.', code: 'bad_json' });
    }
    if (err?.type === 'entity.too.large') {
      return res.status(413).json({ error: 'Requête trop volumineuse.', code: 'too_large' });
    }
    console.error(`[${req.method} ${req.originalUrl}]`, isProd ? err.message : err);
    res.status(500).json({ error: 'Erreur interne du serveur.', code: 'internal' });
  };
}
