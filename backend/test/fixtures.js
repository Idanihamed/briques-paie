import { hashPin } from '../src/lib/pin.js';
import { HttpError } from '../src/lib/errors.js';
import { faceDistance } from '../src/services/faces.js';

/**
 * Données de TEST uniquement (jamais utilisées par l'application) :
 * 3 admins, 2 équipes de 10 ouvriers dont le premier est superviseur,
 * prix de confection 175 et prix de vente 250.
 */
export async function seedFixtures(db, { cost = 4, year = 2025 } = {}) {
  return db.tx(async (q) => {
    const admins = [];
    for (const [name, pin] of [['Admin 1', '1234'], ['Admin 2', '2345'], ['Admin 3', '3456']]) {
      const { rows } = await q.query(
        "insert into users (name, role, pin_hash) values ($1, 'admin', $2) returning id",
        [name, await hashPin(pin, cost)],
      );
      admins.push(rows[0].id);
    }
    const names = [
      ['Ouédraogo Issa', 'Sawadogo Paul', 'Kaboré Adama', 'Zongo Moussa', 'Compaoré Luc',
        'Traoré Salif', 'Ilboudo Karim', 'Sankara Boureima', 'Nikièma Jean', 'Ouattara Seydou'],
      ['Tapsoba Idrissa', 'Yaméogo Alain', 'Savadogo Habib', 'Belem Roch', 'Kinda Souleymane',
        'Zoungrana Eric', 'Bambara Ali', 'Konaté Drissa', 'Diallo Mamadou', 'Sow Oumar'],
    ];
    const out = { teams: [], adminIds: admins };
    for (let i = 0; i < names.length; i++) {
      const team = (await q.query('insert into teams (name) values ($1) returning id', [`Équipe ${i + 1}`])).rows[0];
      const ids = [];
      for (const n of names[i]) {
        ids.push((await q.query('insert into workers (full_name, team_id) values ($1, $2) returning id', [n, team.id])).rows[0].id);
      }
      const pin = String(i + 1).repeat(4);
      const sup = (await q.query(
        "insert into users (name, role, worker_id, pin_hash) values ($1, 'chief', $2, $3) returning id",
        [names[i][0], ids[0], await hashPin(pin, cost)],
      )).rows[0];
      await q.query('update teams set chief_id = $2 where id = $1', [team.id, sup.id]);
      out.teams.push({ id: team.id, supervisorId: sup.id, supervisorName: names[i][0], workerIds: ids, pin });
    }
    for (const [kind, value] of [['cost', 175], ['sale', 250]]) {
      await q.query(
        "insert into tariffs (kind, value, effective_date, reason, created_by) values ($1,$2,$3,'Tarif initial',$4)",
        [kind, value, `${year}-01-01`, admins[0]],
      );
    }
    return out;
  });
}

/**
 * Faux service de reconnaissance faciale, déterministe, pour tester l'API sans
 * modèle. « Image » = texte `personne#variante` encodé en base64 : même personne =
 * signatures presque identiques ; personnes différentes = signatures éloignées.
 */
export function fakeFaces(threshold = 0.5) {
  const seeded = (text, scale = 1) => {
    let h = 2166136261;
    for (const ch of text) h = Math.imul(h ^ ch.charCodeAt(0), 16777619) >>> 0;
    const v = new Float32Array(128);
    for (let i = 0; i < v.length; i++) {
      h = Math.imul(h ^ (h >>> 15), 2246822507) >>> 0;
      v[i] = ((h % 2000) / 1000 - 1) * scale;
    }
    return v;
  };
  return {
    threshold,
    distance: faceDistance,
    async describe(buf) {
      const text = buf.toString('utf8');
      if (text.startsWith('noface')) throw new HttpError(422, 'Aucun visage détecté.', 'no_face');
      if (text.startsWith('many')) throw new HttpError(422, 'Plusieurs visages détectés.', 'many_faces');
      const [person, variant = ''] = text.split('#');
      const base = seeded(person);
      const noise = seeded(variant, 0.01);
      return base.map((x, i) => x + noise[i]);
    },
  };
}

/** Fabrique une « image » de test pour fakeFaces. */
export const fakePhoto = (person, variant = 'a') =>
  Buffer.from(`${person}#${variant}#${'x'.repeat(300)}`).toString('base64');
