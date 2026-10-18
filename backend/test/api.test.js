import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { startTestApp } from './helpers.js';
import { fakePhoto } from './fixtures.js';

let ctx;
let admin;     // Admin 1
let sup1;      // Ouédraogo Issa (équipe 1)
let sup2;      // Tapsoba Idrissa (équipe 2)
let T1; let T2; // équipes de démo

const DAY = '2025-06-10'; // mois passé : tarifs 2025-01-01 en vigueur

/** Corps de saisie : `present` premiers présents, `absent` suivants absents, le reste non saisi. */
const dayBody = (team, date, { bricks = 100, present = 10, absent = 0 } = {}) => ({
  teamId: team.id,
  date,
  bricks,
  presences: team.workerIds.map((id, i) => ({
    workerId: id,
    status: i < present ? 'present' : i < present + absent ? 'absent' : 'unset',
  })),
});

before(async () => {
  ctx = await startTestApp();
  [T1, T2] = ctx.seed.teams;
  admin = await ctx.login('Admin 1', '1234');
  sup1 = await ctx.login('Ouédraogo Issa', '1111');
  sup2 = await ctx.login('Tapsoba Idrissa', '2222');
});
after(() => ctx.close());

test('connexion : message identique pour nom inconnu et PIN faux', async () => {
  const a = await ctx.api('POST', '/api/auth/login', { body: { name: 'Inconnu', pin: '0000' } });
  const b = await ctx.api('POST', '/api/auth/login', { body: { name: 'Admin 2', pin: '0000' } });
  assert.equal(a.status, 401);
  assert.equal(b.status, 401);
  assert.match(a.body.error, /Nom ou code incorrect/);
  assert.match(b.body.error, /Nom ou code incorrect/);
});

test('connexion : verrouillage après 5 PIN erronés puis refus même avec le bon PIN', async () => {
  for (let i = 0; i < 5; i++) {
    const r = await ctx.api('POST', '/api/auth/login', { body: { name: 'Admin 3', pin: '9999' } });
    assert.ok([401, 423].includes(r.status));
  }
  const ok = await ctx.api('POST', '/api/auth/login', { body: { name: 'Admin 3', pin: '3456' } });
  assert.equal(ok.status, 423);
});

test('routes protégées : jeton obligatoire', async () => {
  assert.equal((await ctx.api('GET', '/api/teams')).status, 401);
  assert.equal((await ctx.api('GET', '/api/teams', { token: 'faux' })).status, 401);
});

test('stockage : les PIN sont hachés (bcrypt), jamais en clair', async () => {
  const { rows } = await ctx.db.query('select pin_hash from users');
  for (const r of rows) assert.match(r.pin_hash, /^\$2[aby]\$/);
});

test('superviseur : voit son équipe (10 membres dont lui-même), aucun montant', async () => {
  const r = await ctx.api('GET', `/api/days?teamId=${T1.id}&date=${DAY}`, { token: sup1 });
  assert.equal(r.status, 200);
  assert.equal(r.body.members.length, 10);
  assert.equal(r.body.members.filter((m) => m.isSelf).length, 1);
  assert.equal(r.body.members.find((m) => m.isSelf).fullName, 'Ouédraogo Issa');
  assert.ok(!('calc' in r.body), 'le superviseur ne doit recevoir aucun calcul');
  assert.ok(!JSON.stringify(r.body).match(/tarif|rate|value|total|share|cost|sale|margin|prix/i));
});

test('superviseur : refusé sur les tarifs, l\'aperçu admin, la paie (et tracé)', async () => {
  for (const path of ['/api/tariffs', `/api/overview?date=${DAY}`, '/api/payroll/2025-06', '/api/audit', '/api/supervisors']) {
    const r = await ctx.api('GET', path, { token: sup1 });
    assert.equal(r.status, 403, path);
  }
  const post = await ctx.api('POST', '/api/tariffs', { token: sup1, body: { kind: 'cost', value: 999, effectiveDate: DAY, reason: 'tentative' } });
  assert.equal(post.status, 403);
  const audit = await ctx.api('GET', '/api/audit?securityOnly=true', { token: admin });
  assert.ok(audit.body.items.some((a) => a.action === 'Accès refusé' && a.security));
});

test('superviseur : ne peut pas accéder à l\'équipe d\'un autre', async () => {
  const r = await ctx.api('GET', `/api/days?teamId=${T2.id}&date=${DAY}`, { token: sup1 });
  assert.equal(r.status, 403);
  const w = await ctx.api('PUT', '/api/days', { token: sup1, body: dayBody(T2, DAY) });
  assert.equal(w.status, 403);
});

test('saisie complète (T01) puis aperçu admin : 17 500 FCFA, part 1 750', async () => {
  const put = await ctx.api('PUT', '/api/days', { token: sup1, body: dayBody(T1, DAY, { bricks: 100, present: 10 }) });
  assert.equal(put.status, 200, JSON.stringify(put.body));
  assert.ok(!('calc' in put.body));
  assert.equal(put.body.counts.present, 10);

  const ov = await ctx.api('GET', `/api/overview?date=${DAY}`, { token: admin });
  assert.equal(ov.status, 200);
  const t = ov.body.teams.find((x) => x.teamId === T1.id);
  assert.equal(t.status, 'ok');
  assert.equal(t.bricks, 100);
  assert.equal(t.cost.value, '17500.00');   // 100 × 175 : payé à l'équipe
  assert.equal(t.sale.value, '25000.00');   // 100 × 250 : valeur de vente
  assert.equal(t.share.exact, '1750/1');    // 17 500 ÷ 10 présents
  const p = ov.body.production;
  assert.equal(p.bricks, 100);
  assert.equal(p.costRate, 175);
  assert.equal(p.saleRate, 250);
  assert.equal(p.margin.value, '7500.00');  // vente − confection
  assert.equal(ov.body.totals.present, 10);
  assert.equal(ov.body.totals.teamsWithoutEntry, 1);
});

test('« non saisi » reste « non saisi » : membres oubliés ne deviennent jamais absents', async () => {
  const body = dayBody(T2, '2025-06-11', { bricks: 50, present: 5 });
  body.presences = body.presences.slice(0, 5); // 5 présents seulement envoyés
  const r = await ctx.api('PUT', '/api/days', { token: sup2, body });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.counts.present, 5);
  assert.equal(r.body.counts.absent, 0);
  assert.equal(r.body.counts.unset, 5);
  assert.equal(r.body.complete, false);
});

test('double présence le même jour dans deux équipes refusée par la base', async () => {
  // L'ouvrier w0 de l'équipe 1 est déjà présent dans l'équipe 1 le DAY.
  const intruder = T1.workerIds[1];
  const admin2 = await ctx.api('PUT', '/api/days', {
    token: admin,
    body: {
      teamId: T2.id, date: DAY, bricks: 10,
      presences: [
        ...T2.workerIds.map((id) => ({ workerId: id, status: 'present' })),
        { workerId: intruder, status: 'present', isSubstitute: true },
      ],
    },
  });
  assert.equal(admin2.status, 409);
  assert.equal(admin2.body.code, 'double_presence');
});

test('remplaçant : l\'admin désigne un autre superviseur qui accède avec son propre PIN', async () => {
  assert.equal((await ctx.api('GET', `/api/days?teamId=${T1.id}&date=${DAY}`, { token: sup2 })).status, 403);
  const r = await ctx.api('PUT', `/api/teams/${T1.id}/interim`, { token: admin, body: { userId: T2.supervisorId } });
  assert.equal(r.status, 200);
  assert.equal((await ctx.api('GET', `/api/days?teamId=${T1.id}&date=${DAY}`, { token: sup2 })).status, 200);
  // le titulaire ne peut pas être son propre remplaçant
  const same = await ctx.api('PUT', `/api/teams/${T1.id}/interim`, { token: admin, body: { userId: T1.supervisorId } });
  assert.equal(same.status, 409);
  // fin du remplacement
  assert.equal((await ctx.api('PUT', `/api/teams/${T1.id}/interim`, { token: admin, body: { userId: null } })).status, 200);
  assert.equal((await ctx.api('GET', `/api/days?teamId=${T1.id}&date=${DAY}`, { token: sup2 })).status, 403);
});

test('création d\'un superviseur : un ouvrier existant + PIN, puis connexion par nom', async () => {
  const worker = T2.workerIds[3];
  const bad = await ctx.api('POST', '/api/supervisors', { token: admin, body: { workerId: worker, pin: '12' } });
  assert.equal(bad.status, 400);
  const ok = await ctx.api('POST', '/api/supervisors', { token: admin, body: { workerId: worker, pin: '5678' } });
  assert.equal(ok.status, 201);
  assert.ok(!JSON.stringify(ok.body).includes('5678'));
  const dup = await ctx.api('POST', '/api/supervisors', { token: admin, body: { workerId: worker, pin: '5678' } });
  assert.equal(dup.status, 409);
  const tok = await ctx.login('Belem Roch', '5678');
  const me = await ctx.api('GET', '/api/auth/me', { token: tok });
  assert.equal(me.body.user.role, 'chief');
  assert.deepEqual(me.body.teams, []); // pas encore d'équipe à superviser
});

test('tarifs : changement avec date d\'effet, motif obligatoire, historique conservé', async () => {
  const noReason = await ctx.api('POST', '/api/tariffs', { token: admin, body: { kind: 'cost', value: 200, effectiveDate: '2025-06-15', reason: '' } });
  assert.equal(noReason.status, 400);
  const ok = await ctx.api('POST', '/api/tariffs', { token: admin, body: { kind: 'cost', value: 200, effectiveDate: '2025-06-15', reason: 'Hausse du ciment' } });
  assert.equal(ok.status, 201, JSON.stringify(ok.body));

  // T05 : ancien tarif avant la date d'effet, nouveau ensuite
  const before = await ctx.api('GET', `/api/overview?date=2025-06-10`, { token: admin });
  assert.equal(before.body.production.costRate, 175);
  const list = await ctx.api('GET', '/api/tariffs', { token: admin });
  assert.equal(list.body.find((b) => b.kind === 'cost').history.length, 2);

  // les tarifs sont en ajout seul (trigger)
  await assert.rejects(ctx.db.query("update tariffs set value = 1 where value = 200"), /ajout seul/);
});

test('cycle de paie : blocage, validation, verrouillage, déverrouillage motivé, nouvelle version', async () => {
  const month = '2025-06';

  // Complète toutes les journées existantes du mois : équipe 2 le 11 juin est incomplète (5 non saisis).
  const blocked = await ctx.api('POST', `/api/payroll/${month}/validate`, { token: admin });
  assert.equal(blocked.status, 409);
  assert.equal(blocked.body.code, 'blocking_anomalies');

  // Le superviseur ne peut pas valider
  assert.equal((await ctx.api('POST', `/api/payroll/${month}/validate`, { token: sup1 })).status, 403);

  // Correction par l'admin : 11 juin équipe 2 complète
  const fix = await ctx.api('PUT', '/api/days', { token: admin, body: dayBody(T2, '2025-06-11', { bricks: 50, present: 9, absent: 1 }) });
  assert.equal(fix.status, 200, JSON.stringify(fix.body));

  const before = await ctx.api('GET', `/api/payroll/${month}`, { token: admin });
  assert.equal(before.body.hasBlocking, false);
  assert.equal(before.body.locked, false);

  const v1 = await ctx.api('POST', `/api/payroll/${month}/validate`, { token: admin });
  assert.equal(v1.status, 201, JSON.stringify(v1.body));
  assert.equal(v1.body.version, 1);
  assert.equal((await ctx.api('POST', `/api/payroll/${month}/validate`, { token: admin })).status, 409);

  // Mois verrouillé : plus aucune modification ordinaire (API ET base)
  const edit = await ctx.api('PUT', '/api/days', { token: sup1, body: dayBody(T1, DAY, { bricks: 1 }) });
  assert.equal(edit.status, 409);
  await assert.rejects(ctx.db.query("update day_entries set entered_by = entered_by where work_date = '2025-06-10'"), /verrouillée/);
  await assert.rejects(ctx.db.query("update day_entries set bricks = 1 where work_date = '2025-06-10'"), /verrouillée/);
  await assert.rejects(ctx.db.query("delete from day_presences where work_date = '2025-06-10'"), /verrouillée/);
  // pas de tarif rétroactif sous un mois verrouillé
  const tar = await ctx.api('POST', '/api/tariffs', { token: admin, body: { kind: 'sale', value: 300, effectiveDate: '2025-06-20', reason: 'test' } });
  assert.equal(tar.status, 409);

  // Déverrouillage : motif obligatoire, admin seulement
  assert.equal((await ctx.api('POST', `/api/payroll/${month}/unlock`, { token: admin, body: { reason: '' } })).status, 400);
  assert.equal((await ctx.api('POST', `/api/payroll/${month}/unlock`, { token: sup1, body: { reason: 'je veux' } })).status, 403);
  assert.equal((await ctx.api('POST', `/api/payroll/${month}/unlock`, { token: admin, body: { reason: 'Erreur de saisie le 10 juin' } })).status, 200);

  // Correction possible, puis nouvelle version SANS supprimer l'ancienne
  assert.equal((await ctx.api('PUT', '/api/days', { token: sup1, body: dayBody(T1, DAY, { bricks: 120 }) })).status, 200);
  const v2 = await ctx.api('POST', `/api/payroll/${month}/validate`, { token: admin });
  assert.equal(v2.body.version, 2);

  const final = await ctx.api('GET', `/api/payroll/${month}`, { token: admin });
  assert.equal(final.body.versions.length, 2);
  assert.equal(final.body.versions[1].unlockReason, 'Erreur de saisie le 10 juin');
  assert.equal(final.body.locked, true);
  await assert.rejects(ctx.db.query('delete from payroll_versions'), /ne se supprime pas/);
});

test('paiements : dû exact conservé, arrondi proposé séparé, solde visible, jamais sur paie non validée', async () => {
  const month = '2025-06';
  const pay = await ctx.api('GET', `/api/payments?month=${month}`, { token: admin });
  assert.equal(pay.status, 200);
  assert.equal(pay.body.locked, true);
  // Équipe 2, 11 juin : 50 briques × 175 = 8 750 / 9 présents = 8750/9 (non entier)
  const w = pay.body.workers.find((x) => x.workerId === T2.workerIds[0]);
  assert.equal(w.due.exact, '8750/9');
  assert.equal(w.due.approx, true);
  assert.equal(w.proposed, 972); // 972.22 arrondi à l'unité

  const r = await ctx.api('POST', '/api/payments', { token: admin, body: { workerId: w.workerId, month, paid: 900, mode: 'cash' } });
  assert.equal(r.status, 201, JSON.stringify(r.body));
  assert.equal(r.body.proposed, 972);
  assert.equal(r.body.paid, 900);
  assert.equal(r.body.newBalance.exact, '650/9'); // 8750/9 − 900 : l'écart reste visible, jamais masqué

  assert.equal((await ctx.api('POST', '/api/payments', { token: sup1, body: { workerId: w.workerId, month, paid: 10, mode: 'cash' } })).status, 403);
  // mois non validé
  const no = await ctx.api('POST', '/api/payments', { token: admin, body: { workerId: w.workerId, month: '2025-07', paid: 10, mode: 'cash' } });
  assert.equal(no.status, 409);
  // les paiements sont en ajout seul
  await assert.rejects(ctx.db.query('delete from payments'), /ajout seul/);
});

test('T07 : changer un ouvrier d\'équipe ne modifie pas la paie passée', async () => {
  const month = '2025-06';
  const before = await ctx.api('GET', `/api/payroll/${month}`, { token: admin });
  const w = T1.workerIds[2];
  const move = await ctx.api('PATCH', `/api/workers/${w}`, { token: admin, body: { teamId: T2.id } });
  assert.equal(move.status, 200);
  const after = await ctx.api('GET', `/api/payroll/${month}`, { token: admin });
  const get = (b) => b.workers.find((x) => x.workerId === w).total.exact;
  assert.equal(get(after.body), get(before.body));
  assert.equal(after.body.total.exact, before.body.total.exact);
  // l'historique de la journée reste celui de l'équipe 1
  const day = await ctx.api('GET', `/api/days?teamId=${T1.id}&date=${DAY}`, { token: admin });
  assert.ok(day.body.members.some((m) => m.workerId === w));
});

test('visage : enregistrement par photos, signature chiffrée, doublons et incohérences refusés', async () => {
  const worker = T2.workerIds[5];
  const other = T2.workerIds[6];

  // seul l'admin enregistre un visage
  assert.equal((await ctx.api('PUT', `/api/workers/${worker}/face`, { token: sup2, body: { images: [fakePhoto('alice')] } })).status, 403);

  // aucune photo exploitable
  const none = await ctx.api('PUT', `/api/workers/${worker}/face`, { token: admin, body: { images: [fakePhoto('noface')] } });
  assert.equal(none.status, 422);
  assert.equal(none.body.code, 'no_face');

  // photos de deux personnes différentes : refusé
  const mixed = await ctx.api('PUT', `/api/workers/${worker}/face`, { token: admin, body: { images: [fakePhoto('alice', '1'), fakePhoto('bob', '2')] } });
  assert.equal(mixed.status, 422);
  assert.equal(mixed.body.code, 'inconsistent');

  // enregistrement valide : 3 photos de la même personne
  const ok = await ctx.api('PUT', `/api/workers/${worker}/face`, { token: admin, body: { images: [fakePhoto('alice', '1'), fakePhoto('alice', '2'), fakePhoto('alice', '3')] } });
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
  const { rows } = await ctx.db.query('select face_template, face_enrolled from workers where id = $1', [worker]);
  assert.equal(rows[0].face_enrolled, true);
  assert.equal(Buffer.from(rows[0].face_template).length, 12 + 16 + 128 * 4, 'iv + tag + 128 flottants chiffrés');

  // le même visage ne peut pas être inscrit sous un autre nom
  const dup = await ctx.api('PUT', `/api/workers/${other}/face`, { token: admin, body: { images: [fakePhoto('alice', '9')] } });
  assert.equal(dup.status, 409);
  assert.equal(dup.body.code, 'duplicate_face');

  // la signature n'est jamais exposée
  const list = await ctx.api('GET', '/api/workers', { token: sup2 });
  assert.ok(!JSON.stringify(list.body).match(/template|descriptor/i));
  assert.equal(list.body.find((w) => w.id === worker).faceEnrolled, true);
});

test('visage : vérification (même personne, autre personne, non enregistré, sans visage)', async () => {
  const worker = T2.workerIds[5]; // « alice » enregistrée au test précédent
  const verify = (body) => ctx.api('POST', '/api/faces/verify', { token: sup2, body });

  const yes = await verify({ workerId: worker, image: fakePhoto('alice', 'nouvelle-photo') });
  assert.equal(yes.status, 200, JSON.stringify(yes.body));
  assert.equal(yes.body.match, true);
  assert.ok(yes.body.distance < 0.5);

  const no = await verify({ workerId: worker, image: fakePhoto('bob', 'x') });
  assert.equal(no.body.match, false);
  assert.ok(no.body.distance > 0.5);
  const sec = await ctx.api('GET', '/api/audit?securityOnly=true', { token: admin });
  assert.ok(sec.body.items.some((a) => a.action === 'Visage non reconnu'));

  assert.equal((await verify({ workerId: T2.workerIds[7], image: fakePhoto('alice') })).body.code, 'not_enrolled');
  assert.equal((await verify({ workerId: worker, image: fakePhoto('noface') })).body.code, 'no_face');
  assert.equal((await ctx.api('POST', '/api/faces/verify', { body: { workerId: worker, image: fakePhoto('alice') } })).status, 401);

  // retrait du consentement : la signature est supprimée
  assert.equal((await ctx.api('DELETE', `/api/workers/${worker}/face`, { token: admin })).status, 200);
  assert.equal((await verify({ workerId: worker, image: fakePhoto('alice') })).body.code, 'not_enrolled');
});

test("remplaçants possibles : ni dans l'équipe du jour, ni présents ailleurs ce jour-là", async () => {
  const r = await ctx.api('GET', `/api/days/substitutes?teamId=${T2.id}&date=${DAY}`, { token: sup2 });
  assert.equal(r.status, 200);
  const ids = r.body.map((w) => w.workerId);
  assert.ok(!ids.some((id) => T2.workerIds.includes(id) && id !== T1.workerIds[2]), "pas les membres de l'équipe");
  assert.ok(!ids.includes(T1.workerIds[0]), 'T1 est présente ce jour-là : ses membres ne sont pas disponibles');
  assert.equal((await ctx.api('GET', `/api/days/substitutes?teamId=${T1.id}&date=${DAY}`, { token: sup2 })).status, 403);
});

test('audit : actions tracées, journal immuable', async () => {
  const log = await ctx.api('GET', '/api/audit?limit=200', { token: admin });
  const actions = new Set(log.body.items.map((a) => a.action));
  for (const a of ['Connexion', 'Saisie de journée', 'Modification du tarif', 'Validation et verrouillage de paie', 'Déverrouillage de paie', 'Enregistrement de paiement', 'Remplacement de superviseur']) {
    assert.ok(actions.has(a), `audit manquant : ${a}`);
  }
  const unlock = log.body.items.find((a) => a.action === 'Déverrouillage de paie');
  assert.equal(unlock.reason, 'Erreur de saisie le 10 juin');
  await assert.rejects(ctx.db.query("update audit_log set action = 'x'"), /ajout seul/);
  await assert.rejects(ctx.db.query('delete from audit_log'), /ajout seul/);
});

test('export CSV de la paie : montants exacts, sans donnée sensible', async () => {
  const r = await ctx.api('GET', '/api/payroll/2025-06/csv', { token: admin });
  assert.equal(r.status, 200);
  assert.match(r.body, /Ouvrier;Jours;Total exact/);
  assert.match(r.body, /972,22/);
  assert.ok(!/cnib|face/i.test(r.body));
  assert.equal((await ctx.api('GET', '/api/payroll/2025-06/csv', { token: sup1 })).status, 403);
});

test('validation des entrées : dates, mois, types inconnus', async () => {
  assert.equal((await ctx.api('GET', `/api/days?teamId=${T1.id}&date=pas-une-date`, { token: sup1 })).status, 400);
  assert.equal((await ctx.api('GET', '/api/payroll/2025-13', { token: admin })).status, 400);
  const negative = dayBody(T1, '2025-06-12', { bricks: -5 });
  assert.equal((await ctx.api('PUT', '/api/days', { token: sup1, body: negative })).status, 400);
  const decimal = dayBody(T1, '2025-06-12', { bricks: 10.5 });
  assert.equal((await ctx.api('PUT', '/api/days', { token: sup1, body: decimal })).status, 400);
  const future = dayBody(T1, '2999-01-01');
  assert.equal((await ctx.api('PUT', '/api/days', { token: sup1, body: future })).status, 400);
  assert.equal((await ctx.api('GET', '/api/inconnu', { token: admin })).status, 404);
});

test("admin : nombre d'ouvriers enregistrés et personnes connectées en ce moment", async () => {
  const ov = await ctx.api('GET', `/api/overview?date=${DAY}`, { token: admin });
  assert.equal(ov.status, 200);

  // 2 équipes × 10 ouvriers ; 3 superviseurs (2 de départ + « Belem Roch » créé plus haut)
  assert.equal(ov.body.workers.active, 20);
  assert.equal(ov.body.workers.total, 20);
  assert.equal(ov.body.workers.supervisors, 3);
  assert.equal(typeof ov.body.workers.withFace, 'number');

  // connectés : ceux qui se sont connectés dans ce test (Admin 1, 3 superviseurs), pas Admin 2 ni Admin 3
  const names = ov.body.online.map((u) => u.name).sort();
  assert.deepEqual(names, ['Admin 1', 'Belem Roch', 'Ouédraogo Issa', 'Tapsoba Idrissa']);
  assert.equal(ov.body.online.find((u) => u.name === 'Admin 1').isMe, true);
  assert.match(ov.body.online.find((u) => u.name === 'Ouédraogo Issa').teams, /Équipe 1/);
  assert.equal(ov.body.onlineWindowMinutes, 5);

  // un superviseur ne voit pas qui est connecté
  assert.equal((await ctx.api('GET', `/api/overview?date=${DAY}`, { token: sup1 })).status, 403);

  // déconnexion : il disparaît de la liste
  assert.equal((await ctx.api('POST', '/api/auth/logout', { token: sup1 })).status, 200);
  const after = await ctx.api('GET', `/api/overview?date=${DAY}`, { token: admin });
  assert.ok(!after.body.online.some((u) => u.name === 'Ouédraogo Issa'));
  assert.ok(after.body.online.some((u) => u.name === 'Tapsoba Idrissa'));
});

test("contact : coordonnées saisies à l'enregistrement, visibles de l'admin seulement", async () => {
  const create = await ctx.api('POST', '/api/workers', {
    token: admin,
    body: {
      fullName: 'Nouvel Ouvrier', teamId: T2.id, phone: '+226 70 12 34 56', village: 'Koudougou',
      mobileOperator: 'orange', mobileNumber: '70 12 34 56',
    },
  });
  assert.equal(create.status, 201, JSON.stringify(create.body));

  // l'admin voit toutes les coordonnées
  const all = await ctx.api('GET', '/api/workers', { token: admin });
  const w = all.body.find((x) => x.fullName === 'Nouvel Ouvrier');
  assert.equal(w.phone, '+226 70 12 34 56');
  assert.equal(w.village, 'Koudougou');
  assert.equal(w.mobileOperator, 'orange');
  assert.equal(w.mobileNumber, '70 12 34 56');

  // le superviseur de l'équipe voit l'ouvrier mais AUCUNE coordonnée
  const mine = await ctx.api('GET', '/api/workers', { token: sup2 });
  const seen = mine.body.find((x) => x.fullName === 'Nouvel Ouvrier');
  assert.ok(seen, "le superviseur voit l'ouvrier de son équipe");
  for (const k of ['phone', 'village', 'mobileOperator', 'mobileNumber']) assert.ok(!(k in seen), `${k} masqué`);
  assert.ok(!JSON.stringify(mine.body).includes('70 12 34 56'));

  // validation
  const bad = (body) => ctx.api('POST', '/api/workers', { token: admin, body: { fullName: 'X', teamId: T2.id, ...body } });
  assert.equal((await bad({ phone: 'abc' })).status, 400);
  assert.equal((await bad({ mobileNumber: '70 00 00 00' })).status, 400); // numéro sans opérateur
  assert.equal((await bad({ mobileOperator: 'orange' })).status, 400);    // opérateur sans numéro
  assert.equal((await bad({ mobileOperator: 'inconnu', mobileNumber: '70 00 00 00' })).status, 400);
  assert.equal((await bad({ phone: '' })).status, 201);                    // champ vide = non renseigné

  // modification : seul ce qui est envoyé change ; une valeur vide efface
  assert.equal((await ctx.api('PATCH', `/api/workers/${w.id}`, { token: admin, body: { village: 'Ouagadougou' } })).status, 200);
  let after = (await ctx.api('GET', '/api/workers', { token: admin })).body.find((x) => x.id === w.id);
  assert.equal(after.village, 'Ouagadougou');
  assert.equal(after.phone, '+226 70 12 34 56');

  assert.equal((await ctx.api('PATCH', `/api/workers/${w.id}`, { token: admin, body: { phone: '', mobileOperator: null, mobileNumber: null } })).status, 200);
  after = (await ctx.api('GET', '/api/workers', { token: admin })).body.find((x) => x.id === w.id);
  assert.equal(after.phone, null);
  assert.equal(after.mobileOperator, null);
  assert.equal(after.mobileNumber, null);

  // règle de cohérence aussi à la modification
  assert.equal((await ctx.api('PATCH', `/api/workers/${w.id}`, { token: admin, body: { mobileNumber: '70 11 22 33' } })).status, 400);
  // seul l'admin modifie des coordonnées
  assert.equal((await ctx.api('PATCH', `/api/workers/${w.id}`, { token: sup2, body: { phone: '70 00 00 01' } })).status, 403);

  // le journal d'audit garde la trace du changement, sans recopier les numéros
  const log = JSON.stringify((await ctx.api('GET', '/api/audit?limit=200', { token: admin })).body);
  assert.match(log, /coordonnées/);
  assert.ok(!log.includes('70 12 34 56'), 'les numéros ne doivent pas apparaître dans le journal');
});

// L'ouvrier n° 3 de l'équipe 1 a été déplacé dans l'équipe 2 par un test précédent : l'équipe 1 compte donc 9 membres.
const t1b = () => ({ ...T1, workerIds: T1.workerIds.filter((_, i) => i !== 2) });

// ───────────────────────── Calendrier de travail ─────────────────────────
// Août 2025 : dim. 3, lun. 4, mar. 5, mer. 6, jeu. 7, ven. 8, sam. 9, dim. 10

test('calendrier : dimanche = repos par défaut, saisie refusée un jour non travaillé', async () => {
  const cal = await ctx.api('GET', '/api/calendar?month=2025-08', { token: admin });
  assert.equal(cal.status, 200);
  assert.deepEqual(cal.body.restWeekdays, [0]);
  const sunday = cal.body.days.find((d) => d.date === '2025-08-03');
  assert.equal(sunday.weekday, 0);
  assert.equal(sunday.teams[0].working, false);
  assert.equal(sunday.teams[0].state, 'off');
  assert.equal(sunday.teams[0].source, 'weekly');
  assert.equal(cal.body.days.find((d) => d.date === '2025-08-04').teams[0].state, 'missing'); // lundi passé, rien saisi

  // un superviseur ne voit que son équipe, sans montant
  const mine = await ctx.api('GET', '/api/calendar?month=2025-08', { token: sup1 });
  assert.equal(mine.body.teams.length, 1);
  assert.ok(!JSON.stringify(mine.body).match(/cost|sale|margin|prix/i));

  const sunEntry = await ctx.api('PUT', '/api/days', { token: sup1, body: dayBody(t1b(), '2025-08-03') });
  assert.equal(sunEntry.status, 409);
  assert.equal(sunEntry.body.code, 'non_working_day');
});

test('calendrier : jours fériés en plage, priorité équipe > global, refus si une saisie existe', async () => {
  // seul l'admin modifie le calendrier
  assert.equal((await ctx.api('POST', '/api/calendar/days', { token: sup1, body: { from: '2025-08-05', kind: 'holiday' } })).status, 403);
  assert.equal((await ctx.api('PUT', '/api/calendar/settings', { token: sup1, body: { restWeekdays: [0] } })).status, 403);

  const mark = await ctx.api('POST', '/api/calendar/days', {
    token: admin, body: { from: '2025-08-05', to: '2025-08-06', kind: 'holiday', reason: 'Fête test' },
  });
  assert.equal(mark.status, 201, JSON.stringify(mark.body));
  assert.equal(mark.body.days, 2);

  let cal = (await ctx.api('GET', '/api/calendar?month=2025-08', { token: admin })).body;
  const aug5 = cal.days.find((d) => d.date === '2025-08-05');
  assert.equal(aug5.teams[0].working, false);
  assert.equal(aug5.teams[0].kind, 'holiday');
  assert.equal(aug5.teams[0].source, 'global');
  assert.equal(aug5.teams[0].reason, 'Fête test');
  assert.equal(cal.days.find((d) => d.date === '2025-08-07').teams[0].working, true);

  // saisie refusée ce jour-là, avec le motif dans le message
  const refused = await ctx.api('PUT', '/api/calendar-non-existent', { token: sup1, body: {} }); // route inconnue = 404
  assert.equal(refused.status, 404);
  const blocked = await ctx.api('PUT', '/api/days', { token: sup1, body: dayBody(t1b(), '2025-08-05') });
  assert.equal(blocked.status, 409);
  assert.match(blocked.body.error, /Fête test/);

  // une exception d'équipe l'emporte sur l'exception globale
  assert.equal((await ctx.api('POST', '/api/calendar/days', {
    token: admin, body: { from: '2025-08-05', teamId: T2.id, kind: 'work', reason: 'Équipe 2 travaille' },
  })).status, 201);
  cal = (await ctx.api('GET', '/api/calendar?month=2025-08', { token: admin })).body;
  const t = (day, team) => cal.days.find((d) => d.date === day).teams.find((x) => x.teamId === team.id);
  assert.equal(t('2025-08-05', T2).working, true);
  assert.equal(t('2025-08-05', T2).source, 'team');
  assert.equal(t('2025-08-05', T1).working, false);
  assert.equal((await ctx.api('PUT', '/api/days', { token: sup2, body: dayBody(T2, '2025-08-05') })).status, 200);

  // maintenant qu'une saisie existe, on ne peut plus déclarer ce jour non travaillé
  const late = await ctx.api('POST', '/api/calendar/days', { token: admin, body: { from: '2025-08-05', kind: 'weather' } });
  assert.equal(late.status, 409);
  assert.equal(late.body.code, 'entries_exist');
  assert.equal((await ctx.api('POST', '/api/calendar/days', { token: admin, body: { from: '2025-08-06', to: '2025-08-01', kind: 'rest' } })).status, 400);
});

test('calendrier : repos hebdomadaire modifiable, jour exceptionnel travaillé, rétablissement', async () => {
  // le samedi devient un jour de repos
  assert.equal((await ctx.api('PUT', '/api/calendar/settings', { token: admin, body: { restWeekdays: [0, 6] } })).status, 200);
  let cal = (await ctx.api('GET', '/api/calendar?month=2025-08', { token: admin })).body;
  assert.equal(cal.days.find((d) => d.date === '2025-08-09').teams[0].working, false);
  assert.equal((await ctx.api('PUT', '/api/days', { token: sup1, body: dayBody(t1b(), '2025-08-09') })).body.code, 'non_working_day');

  // … sauf exception : ce samedi-là, on travaille
  assert.equal((await ctx.api('POST', '/api/calendar/days', { token: admin, body: { from: '2025-08-09', kind: 'work', reason: 'Commande urgente' } })).status, 201);
  assert.equal((await ctx.api('PUT', '/api/days', { token: sup1, body: dayBody(t1b(), '2025-08-09') })).status, 200);

  // retour au repos du dimanche seul ; rétablissement d'un jour férié
  assert.equal((await ctx.api('PUT', '/api/calendar/settings', { token: admin, body: { restWeekdays: [0] } })).status, 200);
  assert.equal((await ctx.api('POST', '/api/calendar/days/clear', { token: admin, body: { from: '2025-08-06' } })).status, 200);
  cal = (await ctx.api('GET', '/api/calendar?month=2025-08', { token: admin })).body;
  assert.equal(cal.days.find((d) => d.date === '2025-08-06').teams[0].working, true);

  // un jour férié n'est plus signalé « sans saisie » dans la paie ; un jour travaillé oui
  const pay = await ctx.api('GET', '/api/payroll/2025-08', { token: admin });
  const msgs = pay.body.anomalies.map((a) => a.message).join('\n');
  assert.ok(!msgs.includes('Équipe 1, 03/08/2025'), 'dimanche : pas de fausse alerte');
  assert.ok(!msgs.includes('Équipe 1, 05/08/2025'), 'férié : pas de fausse alerte');
  assert.ok(msgs.includes('Équipe 1, 06/08/2025'), 'jour rétabli et non saisi : alerte');
  assert.ok(msgs.includes('Équipe 1, 04/08/2025'), 'lundi non saisi : alerte');

  // le calendrier d'un mois verrouillé ne change plus (règle appliquée par la base)
  const locked = await ctx.api('POST', '/api/calendar/days', { token: admin, body: { from: '2025-06-30', kind: 'rest' } });
  assert.equal(locked.status, 409);
  assert.match(locked.body.error, /verrouillée/);
});

// ───────────────────────── Motifs d'absence & fiche ouvrier ─────────────────────────

test("motif d'absence : enregistré, restitué, refusé pour un présent ; fiche ouvrier", async () => {
  const date = '2025-08-12'; // mardi
  const body = dayBody(t1b(), date, { bricks: 80, present: 7, absent: 2 });
  body.presences[7].absenceReason = 'sick';
  body.presences[8].absenceReason = 'permission';
  const ok = await ctx.api('PUT', '/api/days', { token: sup1, body });
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
  const reasons = Object.fromEntries(ok.body.members.filter((m) => m.status === 'absent').map((m) => [m.workerId, m.absenceReason]));
  assert.equal(reasons[t1b().workerIds[7]], 'sick');
  assert.equal(reasons[t1b().workerIds[8]], 'permission');

  const bad = dayBody(t1b(), '2025-08-13', { present: 10 });
  bad.presences[0].absenceReason = 'sick'; // présent + motif d'absence
  assert.equal((await ctx.api('PUT', '/api/days', { token: sup1, body: bad })).status, 400);

  // fiche de l'ouvrier absent « maladie »
  const sheet = await ctx.api('GET', `/api/workers/${t1b().workerIds[7]}/sheet?month=2025-08`, { token: admin });
  assert.equal(sheet.status, 200, JSON.stringify(sheet.body));
  assert.equal(sheet.body.stats.absent, 1);
  assert.equal(sheet.body.stats.absences.sick, 1);
  // présent le samedi travaillé (09/08), absent le 12/08 : 1 jour sur 2
  assert.equal(sheet.body.stats.present, 1);
  assert.equal(sheet.body.stats.attendanceRate, 0.5);
  const line = sheet.body.lines.find((l) => l.date === date);
  assert.equal(line.status, 'absent');
  assert.equal(line.absenceReason, 'sick');
  assert.equal(line.share, null);

  // un ouvrier présent : gain exact = part du jour, taux de présence 100 %
  const present = await ctx.api('GET', `/api/workers/${t1b().workerIds[1]}/sheet?month=2025-08`, { token: admin });
  const pl = present.body.lines.find((l) => l.date === date);
  assert.equal(pl.status, 'present');
  assert.equal(pl.dayStatus, 'ok');
  assert.equal(pl.share.exact, '16000/7'); // prix de confection 200 depuis le 15/06/2025 : 80 × 200 = 16 000, ÷ 7 présents (fraction exacte)
  assert.ok(present.body.stats.attendanceRate > 0);
  assert.equal(present.body.balance.exact, present.body.earned.exact); // rien payé ce mois-là

  // la fiche contient des coordonnées : réservée à l'admin
  assert.equal((await ctx.api('GET', `/api/workers/${t1b().workerIds[1]}/sheet?month=2025-08`, { token: sup1 })).status, 403);
  assert.equal((await ctx.api('GET', `/api/workers/${t1b().workerIds[1]}/sheet?month=2025-13`, { token: admin })).status, 400);
});

// ───────────────────────── Synchronisation hors ligne ─────────────────────────

test('synchronisation : version, rejeu sans doublon, conflit « stale », arbitrage « force »', async () => {
  const date = '2025-08-14'; // jeudi
  const url = `/api/days?teamId=${T1.id}&date=${date}`;

  // aucune saisie : version nulle
  const empty = (await ctx.api('GET', url, { token: sup1 })).body;
  assert.equal(empty.version, null);
  assert.equal(empty.workingDay.working, true);

  // 1re saisie envoyée depuis un appareil (version connue : aucune)
  const r1 = randomUUID();
  const first = await ctx.api('PUT', '/api/days', { token: sup1, body: { ...dayBody(t1b(), date, { bricks: 100 }), baseVersion: null, requestId: r1 } });
  assert.equal(first.status, 200, JSON.stringify(first.body));
  const v1 = first.body.version;
  assert.ok(v1);
  assert.equal(first.body.bricks, 100);

  // la réponse s'est perdue : l'appareil renvoie la MÊME saisie -> appliquée une seule fois
  const replay = await ctx.api('PUT', '/api/days', { token: sup1, body: { ...dayBody(t1b(), date, { bricks: 999 }), baseVersion: null, requestId: r1 } });
  assert.equal(replay.status, 200);
  assert.equal(replay.body.bricks, 100, 'le rejeu ne réécrit rien');
  assert.equal(replay.body.version, v1);

  // un autre appareil modifie la journée à partir de la version v1
  const second = await ctx.api('PUT', '/api/days', { token: sup1, body: { ...dayBody(t1b(), date, { bricks: 200 }), baseVersion: v1, requestId: randomUUID() } });
  assert.equal(second.status, 200);
  const v2 = second.body.version;
  assert.notEqual(v2, v1);

  // un appareil resté hors ligne renvoie sa saisie basée sur v1 -> conflit
  const stale = await ctx.api('PUT', '/api/days', { token: sup1, body: { ...dayBody(t1b(), date, { bricks: 300 }), baseVersion: v1, requestId: randomUUID() } });
  assert.equal(stale.status, 409);
  assert.equal(stale.body.code, 'stale');
  assert.equal((await ctx.api('GET', url, { token: sup1 })).body.bricks, 200, 'la version du serveur est intacte');

  // « je croyais qu'il n'y avait rien » alors qu'une saisie existe -> conflit aussi
  const ghost = await ctx.api('PUT', '/api/days', { token: sup1, body: { ...dayBody(t1b(), date, { bricks: 50 }), baseVersion: null, requestId: randomUUID() } });
  assert.equal(ghost.status, 409);
  assert.match(ghost.body.error, /déjà été saisie/);

  // arbitrage de l'utilisateur : « garder ma saisie »
  const forced = await ctx.api('PUT', '/api/days', { token: sup1, body: { ...dayBody(t1b(), date, { bricks: 300 }), baseVersion: v1, requestId: randomUUID(), force: true } });
  assert.equal(forced.status, 200);
  assert.equal(forced.body.bricks, 300);
  const log = (await ctx.api('GET', '/api/audit?limit=50', { token: admin })).body.items;
  assert.ok(log.some((a) => /conservée après conflit/.test(a.newValue ?? '')));

  // anciens clients (sans baseVersion) : toujours acceptés
  assert.equal((await ctx.api('PUT', '/api/days', { token: sup1, body: dayBody(t1b(), date, { bricks: 310 }) })).status, 200);

  // jour verrouillé : refusé même avec « force »
  const locked = await ctx.api('PUT', '/api/days', { token: sup1, body: { ...dayBody(t1b(), DAY, { bricks: 1 }), baseVersion: null, force: true } });
  assert.equal(locked.status, 409);
  assert.equal(locked.body.code, 'locked');
});

test('statistiques : tendance sur 6 mois, classements cohérents, réservé à l\'admin', async () => {
  const s = await ctx.api('GET', '/api/stats?month=2025-06', { token: admin });
  assert.equal(s.status, 200, JSON.stringify(s.body));
  assert.equal(s.body.trend.length, 6);
  assert.equal(s.body.trend.at(-1).month, '2025-06');
  assert.ok(s.body.totals.bricks >= 100);
  assert.equal(s.body.daily.reduce((a, d) => a + d.bricks, 0), s.body.totals.bricks);
  assert.equal(s.body.teams.reduce((a, t) => a + t.bricks, 0), s.body.totals.bricks);
  const b = s.body.teams.map((t) => t.bricks);
  assert.deepEqual(b, [...b].sort((x, y) => y - x));
  for (const w of s.body.workers) assert.ok(w.attendanceRate === null || (w.attendanceRate >= 0 && w.attendanceRate <= 1));
  // La marge = vente − confection, et elle n'est jamais envoyée à un superviseur.
  assert.equal(s.body.totals.margin.value, (Number(s.body.totals.sale.value) - Number(s.body.totals.cost.value)).toFixed(2));
  assert.equal((await ctx.api('GET', '/api/stats?month=2025-06', { token: sup1 })).status, 403);
  assert.equal((await ctx.api('GET', '/api/stats?month=2025-13', { token: admin })).status, 400);
});

test('avances : déduites du solde, refusées sur un mois verrouillé, annulables avant verrouillage', async () => {
  const wid = T1.workerIds[3];
  const body = { workerId: wid, month: '2025-07', amount: 5000, mode: 'cash', note: 'Avance de quinzaine' };
  assert.equal((await ctx.api('POST', '/api/payments/advances', { token: sup1, body })).status, 403);
  const a = await ctx.api('POST', '/api/payments/advances', { token: admin, body });
  assert.equal(a.status, 201, JSON.stringify(a.body));

  const list = await ctx.api('GET', '/api/payments/advances?month=2025-07', { token: admin });
  assert.equal(list.body.advances.length, 1);
  assert.equal(list.body.advances[0].amount, 5000);

  // Sans gain : le solde est négatif (avance à récupérer), visible dans la vue des paiements.
  const pay = await ctx.api('GET', '/api/payments?month=2025-07', { token: admin });
  const row = pay.body.workers.find((x) => x.workerId === wid);
  assert.equal(row.advances, 5000);
  assert.equal(row.balance.exact, '-5000/1');

  // Mois verrouillé (juin 2025) : ni création ni annulation.
  const locked = await ctx.api('POST', '/api/payments/advances', { token: admin, body: { ...body, month: '2025-06' } });
  assert.equal(locked.status, 409);
  assert.equal(locked.body.code, 'locked');

  assert.equal((await ctx.api('DELETE', `/api/payments/advances/${a.body.id}`, { token: admin })).status, 200);
  assert.equal((await ctx.api('GET', '/api/payments/advances?month=2025-07', { token: admin })).body.advances.length, 0);
  assert.equal((await ctx.api('POST', '/api/payments/advances', { token: admin, body: { ...body, amount: 0 } })).status, 400);
});

test('avances : déduites de la paie du mois et de la fiche ouvrier', async () => {
  const month = '2025-06';
  const wid = T2.workerIds[0];
  // juin est verrouillé : on insère directement pour vérifier le calcul du solde.
  await ctx.db.query(
    "insert into advances (worker_id, month, amount, mode, created_by) values ($1, $2, 1000, 'cash', (select id from users where name = 'Admin 1'))",
    [wid, month],
  );
  const p = await ctx.api('GET', `/api/payroll/${month}`, { token: admin });
  const w = p.body.workers.find((x) => x.workerId === wid);
  assert.equal(w.advances, 1000);
  const sheet = await ctx.api('GET', `/api/workers/${wid}/sheet?month=${month}`, { token: admin });
  assert.equal(sheet.body.advanced, 1000);
  assert.equal(sheet.body.balance.exact, w.balance.exact);
  await ctx.db.query('delete from advances');
});

test('paie sur une période libre : mêmes règles, bornes contrôlées, admin seulement', async () => {
  const ok = await ctx.api('GET', '/api/reports/period?from=2025-06-10&to=2025-06-11', { token: admin });
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
  assert.equal(ok.body.days, 2);
  assert.ok(ok.body.bricks >= 100);
  const sum = ok.body.workers.reduce((a, w) => a + Number(w.total.value), 0);
  assert.ok(Math.abs(sum - Number(ok.body.cost.value)) < 0.05);
  assert.equal((await ctx.api('GET', '/api/reports/period?from=2025-06-11&to=2025-06-10', { token: admin })).status, 400);
  assert.equal((await ctx.api('GET', '/api/reports/period?from=2025-01-01&to=2025-12-31', { token: admin })).status, 400);
  assert.equal((await ctx.api('GET', '/api/reports/period?from=2025-06-10&to=2025-06-11', { token: sup1 })).status, 403);
});

test('alertes : liste triée par gravité, admin seulement', async () => {
  const a = await ctx.api('GET', '/api/alerts', { token: admin });
  assert.equal(a.status, 200, JSON.stringify(a.body));
  assert.equal(a.body.count, a.body.alerts.length);
  const order = { high: 0, medium: 1, info: 2 };
  const levels = a.body.alerts.map((x) => order[x.level]);
  assert.deepEqual(levels, [...levels].sort((x, y) => x - y));
  for (const x of a.body.alerts) assert.ok(x.title && x.kind);
  assert.equal((await ctx.api('GET', '/api/alerts', { token: sup1 })).status, 403);
});

test('import d\'ouvriers : vérification sans écriture, doublons et erreurs signalés, import des lignes valides', async () => {
  const text = [
    'Nom\tTéléphone\tVillage\tOpérateur\tNuméro mobile\tÉquipe',
    `Kaboré Ali\t70 11 22 33\tKoudougou\tOrange\t70 11 22 33\tÉquipe 1`,
    'Sawadogo Fati\t\t\t\t\t',
    `${T1.name === 'x' ? '' : 'Kaboré Ali'}\t\t\t\t\t`,
    'Zongo Paul\t\t\tOrange\t\t',
    'Ouedraogo Marie\t\t\t\t\tÉquipe inexistante',
  ].join('\n');
  const before = (await ctx.api('GET', '/api/workers', { token: admin })).body.length;

  assert.equal((await ctx.api('POST', '/api/workers/import', { token: sup1, body: { text } })).status, 403);
  const dry = await ctx.api('POST', '/api/workers/import', { token: admin, body: { text, dryRun: true } });
  assert.equal(dry.status, 200, JSON.stringify(dry.body));
  assert.deepEqual(dry.body.counts, { ok: 2, duplicate: 1, error: 2 }, JSON.stringify(dry.body.rows));
  assert.equal(dry.body.imported, 0);
  assert.equal((await ctx.api('GET', '/api/workers', { token: admin })).body.length, before);

  const real = await ctx.api('POST', '/api/workers/import', { token: admin, body: { text, dryRun: false } });
  assert.equal(real.body.imported, 2);
  const list = (await ctx.api('GET', '/api/workers', { token: admin })).body;
  assert.equal(list.length, before + 2);
  const ali = list.find((w) => w.fullName === 'Kaboré Ali');
  assert.equal(ali.village, 'Koudougou');
  assert.equal(ali.mobileOperator, 'orange');
  assert.equal(ali.teamId, T1.id);

  // Relancer le même import ne crée aucun doublon.
  const again = await ctx.api('POST', '/api/workers/import', { token: admin, body: { text, dryRun: false } });
  assert.equal(again.body.imported, 0);
});

test('sauvegarde : toutes les tables, sans PIN ni signature de visage, admin seulement', async () => {
  assert.equal((await ctx.api('GET', '/api/backup', { token: sup1 })).status, 403);
  const b = await ctx.api('GET', '/api/backup', { token: admin });
  assert.equal(b.status, 200);
  assert.ok(b.body.counts.workers >= 20);
  assert.ok(b.body.counts.day_entries > 0);
  const raw = JSON.stringify(b.body);
  assert.ok(!raw.includes('pin_hash') && !raw.includes('face_template'));
  assert.ok(b.body.tables.users.every((u) => !('pin_hash' in u)));
});

test('factures : en-tête, clients, brouillon depuis la production, numérotation, total en lettres, immuabilité', async () => {
  const lh = await ctx.api('GET', '/api/invoices/letterhead', { token: admin });
  assert.equal(lh.status, 200);
  assert.equal(lh.body.name, 'ASSOCIATION BAYIIR MÊTBA');
  assert.equal((await ctx.api('GET', '/api/invoices/letterhead', { token: sup1 })).status, 403);

  const cl = await ctx.api('POST', '/api/invoices/clients', {
    token: admin,
    body: { code: 'sopamib', name: 'SOPAMIB BOUBOULOU S.A.', status: "Société d'État", rccm: 'N° BF OUA 01 2024 B30 14310', ifu: 'N° 00248483L', capital: '10 000 000 Francs CFA', address: 'Ouaga 2000' },
  });
  assert.equal(cl.status, 201, JSON.stringify(cl.body));
  assert.equal((await ctx.api('POST', '/api/invoices/clients', { token: admin, body: { code: 'SOPAMIB', name: 'Doublon' } })).status, 409);
  const clientId = cl.body.id;

  // Brouillon : briques saisies le 10 juin 2025 (toutes équipes confondues), prix de vente en vigueur.
  const d = await ctx.api('GET', '/api/invoices/draft?from=2025-06-10&to=2025-06-11', { token: admin });
  assert.equal(d.status, 200, JSON.stringify(d.body));
  assert.ok(d.body.lines.length >= 1);
  assert.equal(d.body.suggestedUnitPrice, 250);

  const body = {
    clientId, issuedOn: '2026-07-15', subject: 'Production hebdomadaire de briques BTC (08 au 12 juillet 2026)',
    unitPrice: 200,
    lines: [
      { date: '2026-07-08', label: 'Brique BTC', qty: 169 }, { date: '2026-07-09', label: 'Brique BTC', qty: 359 },
      { date: '2026-07-10', label: 'Brique BTC', qty: 665 }, { date: '2026-07-11', label: 'Brique BTC', qty: 0 },
      { date: null, label: 'Brique BTC (Echantillons)', qty: 243 },
    ],
  };
  const inv = await ctx.api('POST', '/api/invoices', { token: admin, body });
  assert.equal(inv.status, 201, JSON.stringify(inv.body));
  assert.equal(inv.body.number, 'ABM/SOPAMIB/2026-07-001');
  assert.equal(inv.body.totalAmount, 287200); // 1 436 × 200, comme la facture papier
  const inv2 = await ctx.api('POST', '/api/invoices', { token: admin, body: { ...body, issuedOn: '2026-07-20' } });
  assert.equal(inv2.body.number, 'ABM/SOPAMIB/2026-07-002');

  const full = (await ctx.api('GET', `/api/invoices/${inv.body.id}`, { token: admin })).body;
  assert.equal(full.totalQty, 1436);
  assert.equal(full.amountWords, 'Deux cent quatre-vingt-sept mille deux cents (287 200) francs CFA');
  assert.equal(full.client.rccm, 'N° BF OUA 01 2024 B30 14310');
  assert.equal(full.signer, 'Le Trésorier');

  // La modification du client ou de l'en-tête ne change pas une facture déjà émise.
  assert.equal((await ctx.api('PATCH', `/api/invoices/clients/${clientId}`, { token: admin, body: { name: 'Autre nom' } })).status, 200);
  const again = (await ctx.api('GET', `/api/invoices/${inv.body.id}`, { token: admin })).body;
  assert.equal(again.client.name, 'SOPAMIB BOUBOULOU S.A.');

  // Immuable en base : ni suppression ni modification ; seule l'annulation motivée.
  await assert.rejects(ctx.db.query('delete from invoices'), /ne se supprime pas/);
  await assert.rejects(ctx.db.query("update invoices set total_amount = 1 where id = $1", [inv.body.id]), /ne se modifie pas/);
  assert.equal((await ctx.api('POST', `/api/invoices/${inv.body.id}/cancel`, { token: admin, body: { reason: 'x' } })).status, 400);
  assert.equal((await ctx.api('POST', `/api/invoices/${inv.body.id}/cancel`, { token: admin, body: { reason: 'Erreur de client' } })).status, 200);
  assert.equal((await ctx.api('POST', `/api/invoices/${inv.body.id}/cancel`, { token: admin, body: { reason: 'Encore' } })).status, 409);

  assert.equal((await ctx.api('POST', '/api/invoices', { token: admin, body: { ...body, lines: [] } })).status, 400);
  assert.equal((await ctx.api('POST', '/api/invoices', { token: sup1, body })).status, 403);
  const list = (await ctx.api('GET', '/api/invoices', { token: admin })).body;
  assert.equal(list.length, 2);

  // En-tête modifiable (copie figée dans les factures suivantes).
  const put = await ctx.api('PUT', '/api/invoices/letterhead', { token: admin, body: { ...lh.body, signer: 'Le Président' } });
  assert.equal(put.status, 200);
  const inv3 = await ctx.api('POST', '/api/invoices', { token: admin, body: { ...body, issuedOn: '2026-08-02' } });
  assert.equal(inv3.body.number, 'ABM/SOPAMIB/2026-08-001');
  assert.equal((await ctx.api('GET', `/api/invoices/${inv3.body.id}`, { token: admin })).body.signer, 'Le Président');
  assert.equal((await ctx.api('GET', `/api/invoices/${inv2.body.id}`, { token: admin })).body.signer, 'Le Trésorier');
});

test('montants en lettres : orthographe française', async () => {
  const { numberToFrench } = await import('../src/services/words.js');
  const cases = { 0: 'zéro', 21: 'vingt et un', 71: 'soixante et onze', 80: 'quatre-vingts', 91: 'quatre-vingt-onze', 200: 'deux cents',
    1000: 'mille', 80000: 'quatre-vingt mille', 598800: 'cinq cent quatre-vingt-dix-huit mille huit cents', 2200000: 'deux millions deux cent mille' };
  for (const [n, w] of Object.entries(cases)) assert.equal(numberToFrench(Number(n)), w);
});
