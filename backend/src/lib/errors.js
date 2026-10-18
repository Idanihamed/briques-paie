export class HttpError extends Error {
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export const badRequest = (m, code) => new HttpError(400, m, code);
export const unauthorized = (m = 'Authentification requise.') => new HttpError(401, m, 'unauthorized');
export const forbidden = (m = 'Action refusée : droits insuffisants.') => new HttpError(403, m, 'forbidden');
export const notFound = (m = 'Introuvable.') => new HttpError(404, m, 'not_found');
export const conflict = (m, code) => new HttpError(409, m, code);

/** Enveloppe les handlers async pour que les erreurs atteignent le middleware d'erreurs. */
export const ah = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
