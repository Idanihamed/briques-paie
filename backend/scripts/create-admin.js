import { loadConfig } from '../src/config.js';
import { createPgDb } from '../src/db.js';
import { openLocalDb } from '../src/localDb.js';
import { hashPin, pinSchema } from '../src/lib/pin.js';

/**
 * Crée un compte admin (le premier, ou un des trois responsables).
 *   npm run create-admin -- "Nom Prénom" 1234          (base Supabase, via .env)
 *   npm run create-admin -- --local "Nom Prénom" 1234   (base locale de développement)
 * Aucun compte n'est jamais créé automatiquement : rien n'est codé en dur.
 */
const args = process.argv.slice(2);
const local = args[0] === '--local';
const [name, pin] = local ? args.slice(1) : args;

if (!name || !pin) {
  console.error('Usage : npm run create-admin -- [--local] "Nom Prénom" <PIN 4 à 6 chiffres>');
  process.exit(1);
}
const parsed = pinSchema.safeParse(pin);
if (!parsed.success) {
  console.error(parsed.error.issues[0].message);
  process.exit(1);
}

let db;
if (local) {
  db = await openLocalDb();
} else {
  const config = loadConfig();
  db = createPgDb({ databaseUrl: config.databaseUrl, ssl: config.dbSsl });
}

try {
  const exists = await db.query('select 1 from users where lower(name) = lower($1)', [name.trim()]);
  if (exists.rows.length) throw new Error(`Un compte « ${name} » existe déjà.`);
  const { rows } = await db.query(
    "insert into users (name, role, pin_hash) values ($1, 'admin', $2) returning id",
    [name.trim(), await hashPin(pin)],
  );
  await db.query(
    "insert into audit_log (user_name, role, action, object) values ('Système', '-', 'Création de compte admin', $1)",
    [name.trim()],
  );
  console.log(`Compte admin créé : ${name.trim()} (${rows[0].id})`);
} catch (e) {
  console.error(e.message);
  process.exitCode = 1;
} finally {
  await db.close();
}
