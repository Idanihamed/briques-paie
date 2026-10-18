import 'dotenv/config';
import path from 'node:path';

/** Lit et valide la configuration. Échoue vite si un secret manque ou est trop faible. */
export function loadConfig(env = process.env) {
  const errors = [];
  const need = (key) => {
    const v = env[key];
    if (!v) errors.push(`${key} est obligatoire`);
    return v;
  };

  const jwtSecret = need('JWT_SECRET');
  if (jwtSecret && jwtSecret.length < 32) errors.push('JWT_SECRET doit contenir au moins 32 caractères');

  const faceKeyHex = need('FACE_KEY');
  if (faceKeyHex && !/^[0-9a-fA-F]{64}$/.test(faceKeyHex)) {
    errors.push('FACE_KEY doit être une clé AES-256 en hexadécimal (64 caractères)');
  }

  const databaseUrl = need('DATABASE_URL');

  if (errors.length) {
    throw new Error(`Configuration invalide :\n - ${errors.join('\n - ')}\n(voir .env.example)`);
  }

  return {
    port: Number(env.PORT ?? 3000),
    databaseUrl,
    jwtSecret,
    jwtTtl: env.JWT_TTL ?? '12h',
    faceKey: Buffer.from(faceKeyHex, 'hex'),
    // Distance maximale entre deux signatures pour accepter « c'est la même personne ».
    faceThreshold: Number(env.FACE_THRESHOLD ?? 0.5),
    corsOrigins: (env.CORS_ORIGINS ?? '').split(',').map((s) => s.trim()).filter(Boolean),
    // Supabase exige TLS ; désactivable uniquement pour un Postgres local.
    dbSsl: env.DB_SSL !== 'false',
    isProd: env.NODE_ENV === 'production',
    // Application web Flutter servie par l'API (optionnel) : dossier contenant index.html.
    publicDir: path.resolve(env.PUBLIC_DIR ?? 'public'),
  };
}
