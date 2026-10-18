import { Router } from 'express';
import { z } from 'zod';
import { ah, conflict, HttpError, notFound } from '../lib/errors.js';
import { logAudit } from '../lib/audit.js';
import { decryptTemplate, encryptTemplate } from '../lib/crypto.js';
import { teamsOf } from '../services/access.js';
import { assertMonth, monthLabel, todayStr } from '../lib/dates.js';
import { Rational } from '../lib/rational.js';
import { computeDay, payrollForMonth } from '../services/payroll.js';
import { assertMobileConsistency, contactFields } from '../lib/contact.js';
import { averageDescriptor, fromBuffer, toBuffer } from '../services/faces.js';
import { imageSchema, decodeImage } from './faces.js';
import { parseWorkers } from '../services/importer.js';

const uuid = z.string().uuid();
// Les coordonnées (téléphone, village, mobile money) sont réservées à l'admin : un superviseur
// ne voit que ce qui est nécessaire à son travail.
const toDto = (w, withContact) => ({
  id: w.id,
  fullName: w.full_name,
  teamId: w.team_id,
  teamName: w.team_name,
  active: w.active,
  faceEnrolled: w.face_enrolled,
  isSupervisor: Boolean(w.user_id),
  ...(withContact
    ? { phone: w.phone, village: w.village, mobileOperator: w.mobile_operator, mobileNumber: w.mobile_number }
    : {}),
});

export function workersRouter({ db, config, auth, admin, faces }) {
  const r = Router();
  r.use(auth);

  const SELECT = `select w.id, w.full_name, w.phone, w.village, w.mobile_operator, w.mobile_number, w.team_id, t.name as team_name, w.active, w.face_enrolled, u.id as user_id
                    from workers w left join teams t on t.id = w.team_id left join users u on u.worker_id = w.id`;

  // Admin : tous. Superviseur : uniquement les membres de ses équipes.
  r.get('/', ah(async (req, res) => {
    if (req.user.role === 'admin') {
      const { rows } = await db.query(`${SELECT} order by w.full_name`);
      return res.json(rows.map((w) => toDto(w, true)));
    }
    const ids = (await teamsOf(db, req.user)).map((t) => t.id);
    const { rows } = await db.query(`${SELECT} where w.team_id = any($1::uuid[]) and w.active order by w.full_name`, [ids]);
    res.json(rows.map((w) => toDto(w, false)));
  }));

  // Fiche d'un ouvrier pour un mois : présences jour par jour, motifs d'absence, gains exacts, paiements.
  r.get('/:id/sheet', admin, ah(async (req, res) => {
    const month = assertMonth(String(req.query.month ?? todayStr().slice(0, 7)));
    const w = (await db.query(`${SELECT} where w.id = $1`, [req.params.id])).rows[0];
    if (!w) throw notFound('Ouvrier introuvable.');

    const p = await payrollForMonth(db, month, todayStr());
    const teamNames = new Map(p.teams.map((t) => [t.id, t.name]));
    const lines = [];
    for (const e of p.entries) {
      if (!(w.id in e.presence)) continue;
      const status = e.presence[w.id];
      const meta = e.meta[w.id];
      const day = computeDay(e, p.tariffs);
      lines.push({
        date: e.date,
        teamId: e.teamId,
        teamName: teamNames.get(e.teamId) ?? null,
        status,
        isSubstitute: meta.isSubstitute,
        faceVerified: meta.faceVerified,
        absenceReason: meta.absenceReason ?? null,
        dayStatus: day.status,
        share: status === 'present' && day.status === 'ok' ? day.share : null,
      });
    }
    lines.sort((a, b) => a.date.localeCompare(b.date));

    const count = (s) => lines.filter((l) => l.status === s).length;
    const present = count('present');
    const absent = count('absent');
    const absences = { sick: 0, permission: 0, unjustified: 0, other: 0, unspecified: 0 };
    for (const l of lines) if (l.status === 'absent') absences[l.absenceReason ?? 'unspecified']++;

    const payments = (await db.query(
      'select paid_at, paid, mode from payments where worker_id = $1 and month = $2 order by paid_at', [w.id, month],
    )).rows.map((x) => ({ paidAt: x.paid_at, paid: x.paid, mode: x.mode }));
    const paid = payments.reduce((s, x) => s + x.paid, 0);
    const advances = (await db.query(
      'select id, amount, given_at, mode, note from advances where worker_id = $1 and month = $2 order by given_at, created_at', [w.id, month],
    )).rows.map((x) => ({ id: x.id, amount: x.amount, givenAt: x.given_at, mode: x.mode, note: x.note }));
    const advanced = advances.reduce((s, x) => s + x.amount, 0);
    const earned = p.workers.get(w.id)?.total ?? Rational.ZERO;
    const locked = (await db.query('select 1 from payroll_versions where month = $1 and unlocked_at is null', [month])).rows.length > 0;

    res.json({
      worker: toDto(w, true),
      month,
      label: monthLabel(month),
      locked,
      stats: {
        present,
        absent,
        unset: count('unset'),
        attendanceRate: present + absent > 0 ? Number((present / (present + absent)).toFixed(4)) : null,
        absences,
      },
      earned,
      paid,
      advances,
      advanced,
      balance: earned.sub(Rational.int(paid + advanced)),
      lines,
      payments,
    });
  }));

  // Import en masse : tableau collé depuis Excel ou CSV. `dryRun` = simple vérification (rien n'est écrit).
  r.post('/import', admin, ah(async (req, res) => {
    const b = z.object({ text: z.string().max(500_000), dryRun: z.boolean().default(true) }).parse(req.body);
    const norm = (s) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]/g, '');
    const out = await db.tx(async (q) => {
      const teams = new Map((await q.query('select id, name from teams')).rows.map((t) => [norm(t.name), t.id]));
      const existing = new Set((await q.query('select full_name from workers')).rows.map((w) => norm(w.full_name)));
      const rows = parseWorkers(b.text, { teams, existing });
      if (rows.length > 500) throw new HttpError(400, 'Import limité à 500 lignes à la fois.');
      let imported = 0;
      if (!b.dryRun) {
        for (const r0 of rows.filter((x) => x.status === 'ok')) {
          const d = r0.data;
          await q.query(
            `insert into workers (full_name, team_id, phone, village, mobile_operator, mobile_number) values ($1,$2,$3,$4,$5,$6)`,
            [d.fullName, d.teamId, d.phone ?? null, d.village ?? null, d.mobileOperator ?? null, d.mobileNumber ?? null],
          );
          imported++;
        }
        await logAudit(q, req.user, { action: 'Import d\'ouvriers', object: `${imported} ouvrier(s)`, newValue: `${rows.length - imported} ligne(s) ignorée(s)` });
      }
      return {
        dryRun: b.dryRun,
        imported,
        counts: { ok: rows.filter((x) => x.status === 'ok').length, duplicate: rows.filter((x) => x.status === 'duplicate').length, error: rows.filter((x) => x.status === 'error').length },
        rows: rows.map(({ line, name, status, message }) => ({ line, name, status, message })),
      };
    });
    res.json(out);
  }));

  r.post('/', admin, ah(async (req, res) => {
    const b = z.object({
      fullName: z.string().trim().min(1).max(120),
      teamId: uuid,
      ...contactFields,
    }).parse(req.body);
    assertMobileConsistency(b);
    const w = await db.tx(async (q) => {
      const team = (await q.query('select name from teams where id = $1', [b.teamId])).rows[0];
      if (!team) throw notFound('Équipe introuvable.');
      const { rows } = await q.query(
        `insert into workers (full_name, team_id, phone, village, mobile_operator, mobile_number)
         values ($1, $2, $3, $4, $5, $6) returning id`,
        [b.fullName, b.teamId, b.phone ?? null, b.village ?? null, b.mobileOperator ?? null, b.mobileNumber ?? null],
      );
      // Le journal ne recopie pas les numéros : seulement le fait que des coordonnées ont été saisies.
      const given = [b.phone && 'téléphone', b.village && 'village', b.mobileNumber && 'mobile money'].filter(Boolean);
      await logAudit(q, req.user, {
        action: "Création d'ouvrier",
        object: b.fullName,
        newValue: given.length ? `${team.name} · coordonnées : ${given.join(', ')}` : team.name,
      });
      return rows[0];
    });
    res.status(201).json({ id: w.id });
  }));

  // Changement d'équipe / désactivation. L'historique des journées reste intact
  // (les présences sont liées à la journée de l'équipe, pas à l'équipe actuelle).
  r.patch('/:id', admin, ah(async (req, res) => {
    const b = z.object({
      fullName: z.string().trim().min(1).max(120).optional(),
      ...contactFields,
      teamId: uuid.nullable().optional(),
      active: z.boolean().optional(),
    }).refine((o) => Object.keys(o).length > 0, 'Aucune modification fournie.').parse(req.body);

    await db.tx(async (q) => {
      const old = (await q.query(
        'select w.*, t.name as team_name from workers w left join teams t on t.id = w.team_id where w.id = $1 for update of w',
        [req.params.id],
      )).rows[0];
      if (!old) throw notFound('Ouvrier introuvable.');
      const pick = (key, col) => (b[key] === undefined ? old[col] : b[key]);
      const next = {
        full_name: b.fullName ?? old.full_name,
        phone: pick('phone', 'phone'),
        village: pick('village', 'village'),
        mobile_operator: pick('mobileOperator', 'mobile_operator'),
        mobile_number: pick('mobileNumber', 'mobile_number'),
        team_id: b.teamId === undefined ? old.team_id : b.teamId,
        active: b.active ?? old.active,
      };
      assertMobileConsistency({ mobileOperator: next.mobile_operator, mobileNumber: next.mobile_number });
      await q.query(
        `update workers set full_name=$2, phone=$3, village=$4, mobile_operator=$5, mobile_number=$6, team_id=$7, active=$8
          where id=$1`,
        [old.id, next.full_name, next.phone, next.village, next.mobile_operator, next.mobile_number, next.team_id, next.active],
      );
      const contactChanged = [
        next.phone !== old.phone && 'téléphone',
        next.village !== old.village && 'village',
        (next.mobile_number !== old.mobile_number || next.mobile_operator !== old.mobile_operator) && 'mobile money',
      ].filter(Boolean);
      const newTeam = next.team_id ? (await q.query('select name from teams where id=$1', [next.team_id])).rows[0]?.name : null;
      await logAudit(q, req.user, {
        action: "Modification d'ouvrier",
        object: next.full_name,
        oldValue: `${old.team_name ?? '—'}, ${old.active ? 'actif' : 'inactif'}`,
        newValue: `${newTeam ?? '—'}, ${next.active ? 'actif' : 'inactif'}`
          + (contactChanged.length ? ` · coordonnées modifiées : ${contactChanged.join(', ')}` : ''),
      });
    });
    res.json({ ok: true });
  }));

  // Enregistrement du visage : 1 à 5 photos du MÊME visage. Le serveur calcule une signature
  // moyenne, la chiffre (AES-256-GCM) et jette les photos. Un visage déjà enregistré pour un
  // autre ouvrier est refusé (empêche qu'une personne soit inscrite sous deux noms).
  r.put('/:id/face', admin, ah(async (req, res) => {
    const { images } = z.object({ images: z.array(imageSchema).min(1).max(5) }).parse(req.body);
    const w = (await db.query('select id, full_name from workers where id = $1', [req.params.id])).rows[0];
    if (!w) throw notFound('Ouvrier introuvable.');

    const descriptors = [];
    for (const img of images) descriptors.push(await faces.describe(decodeImage(img)));
    for (const d of descriptors.slice(1)) {
      if (faces.distance(descriptors[0], d) > 0.6) {
        throw new HttpError(422, 'Les photos ne montrent pas la même personne. Recommencez.', 'inconsistent');
      }
    }
    const template = averageDescriptor(descriptors);

    const others = (await db.query(
      'select id, full_name, face_template from workers where face_template is not null and id <> $1', [w.id],
    )).rows;
    for (const o of others) {
      if (faces.distance(template, fromBuffer(decryptTemplate(config.faceKey, o.face_template))) <= faces.threshold * 0.9) {
        throw conflict(`Ce visage est déjà enregistré pour « ${o.full_name} ».`, 'duplicate_face');
      }
    }

    await db.tx(async (q) => {
      await q.query('update workers set face_template = $2, face_enrolled = true where id = $1',
        [w.id, encryptTemplate(config.faceKey, toBuffer(template))]);
      await logAudit(q, req.user, { action: 'Enregistrement de visage', object: w.full_name, newValue: `${images.length} photo(s)` });
    });
    res.json({ ok: true });
  }));

  // Suppression d'une signature (retrait du consentement, départ de l'ouvrier).
  r.delete('/:id/face', admin, ah(async (req, res) => {
    await db.tx(async (q) => {
      const w = (await q.query('select full_name from workers where id = $1', [req.params.id])).rows[0];
      if (!w) throw notFound('Ouvrier introuvable.');
      await q.query('update workers set face_template = null, face_enrolled = false where id = $1', [req.params.id]);
      await logAudit(q, req.user, { action: 'Suppression de visage', object: w.full_name });
    });
    res.json({ ok: true });
  }));

  return r;
}
