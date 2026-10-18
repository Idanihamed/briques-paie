import { loadConfig } from '../src/config.js';
import { createPgDb } from '../src/db.js';

/**
 * Définit les prix initiaux (prix de confection et prix de vente) sur une base vide de tarifs.
 *   npm run set-prices -- 175 250 "Nom de l'admin"
 *   (confection FCFA/brique, vente FCFA/brique, admin auteur)
 * Ensuite, les prix se modifient depuis l'application (écran « Prix & tarifs », avec date d'effet et motif).
 */
const [cost, sale, adminName] = process.argv.slice(2);
const c = Number(cost);
const s = Number(sale);
if (!Number.isInteger(c) || !Number.isInteger(s) || c <= 0 || s <= 0 || !adminName) {
  console.error('Usage : npm run set-prices -- <prix confection> <prix vente> "Nom de l\'admin"');
  process.exit(1);
}

const config = loadConfig();
const db = createPgDb({ databaseUrl: config.databaseUrl, ssl: config.dbSsl });
try {
  await db.tx(async (q) => {
    const admin = (await q.query("select id, name from users where role = 'admin' and lower(name) = lower($1)", [adminName])).rows[0];
    if (!admin) throw new Error(`Aucun admin nommé « ${adminName} ».`);
    if ((await q.query('select 1 from tariffs limit 1')).rows.length) {
      throw new Error('Des prix existent déjà : modifiez-les depuis l\'application (Prix & tarifs).');
    }
    const from = `${new Date().getFullYear()}-01-01`;
    for (const [kind, value, label] of [['cost', c, 'Prix de confection'], ['sale', s, 'Prix de vente']]) {
      await q.query(
        "insert into tariffs (kind, value, effective_date, reason, created_by) values ($1,$2,$3,'Prix initial',$4)",
        [kind, value, from, admin.id],
      );
      await q.query(
        "insert into audit_log (user_id, user_name, role, action, object, new_value, reason) values ($1,$2,'Admin','Modification du tarif',$3,$4,'Prix initial')",
        [admin.id, admin.name, label, `${value} FCFA dès le ${from.slice(8)}/${from.slice(5, 7)}/${from.slice(0, 4)}`],
      );
    }
    console.log(`Prix définis : confection ${c} FCFA, vente ${s} FCFA (dès le ${from}).`);
  });
} catch (e) {
  console.error(e.message);
  process.exitCode = 1;
} finally {
  await db.close();
}
