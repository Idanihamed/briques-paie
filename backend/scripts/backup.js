// Sauvegarde locale : npm run backup  → backups/sauvegarde-AAAA-MM-JJ.json (sans PIN ni signatures de visage).
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { loadConfig } from '../src/config.js';
import { createPgDb } from '../src/db.js';
import { buildBackup } from '../src/services/backup.js';

const config = loadConfig();
const db = createPgDb({ databaseUrl: config.databaseUrl, ssl: config.dbSsl });
try {
  const dir = fileURLToPath(new URL('../backups/', import.meta.url));
  await mkdir(dir, { recursive: true });
  const file = `${dir}sauvegarde-${new Date().toISOString().slice(0, 10)}.json`;
  const b = await buildBackup(db);
  await writeFile(file, JSON.stringify(b, null, 1), 'utf8');
  console.log(`Sauvegarde écrite : ${file}`);
  console.log(b.counts);
} finally {
  await db.close();
}
