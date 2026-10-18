import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { loadConfig } from '../src/config.js';
import { createPgDb } from '../src/db.js';

const config = loadConfig();
const db = createPgDb({ databaseUrl: config.databaseUrl, ssl: config.dbSsl });
try {
  const sql = await readFile(fileURLToPath(new URL('../db/schema.sql', import.meta.url)), 'utf8');
  await db.query(sql); // le script est idempotent
  console.log('Schéma appliqué.');
} finally {
  await db.close();
}
