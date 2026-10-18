import { Router } from 'express';
import { z } from 'zod';
import { ah, conflict } from '../lib/errors.js';
import { logAudit } from '../lib/audit.js';
import { assertMonth, monthLabel, todayStr } from '../lib/dates.js';
import { Rational } from '../lib/rational.js';
import { payrollForMonth } from '../services/payroll.js';
import { advancesByWorker } from '../services/advances.js';

const csvField = (v) => (/[;"\n]/.test(String(v)) ? `"${String(v).replaceAll('"', '""')}"` : String(v));

/** Paie mensuelle : calcul provisoire, validation/verrouillage, déverrouillage motivé, export CSV. */
export function payrollRouter({ db, auth, admin }) {
  const r = Router();
  r.use(auth, admin);

  const versionsOf = async (q, month) =>
    (await q.query(
      `select v.version, v.total_exact, v.validated_at, v.unlocked_at, v.unlock_reason,
              a.name as validated_by, b.name as unlocked_by
         from payroll_versions v join users a on a.id = v.validated_by left join users b on b.id = v.unlocked_by
        where v.month = $1 order by v.version desc`,
      [month],
    )).rows;

  const paidByWorker = async (q, month) =>
    new Map((await q.query('select worker_id, sum(paid)::int as paid from payments where month = $1 group by worker_id', [month]))
      .rows.map((x) => [x.worker_id, x.paid]));

  r.get('/:month', ah(async (req, res) => {
    const month = assertMonth(req.params.month);
    const p = await payrollForMonth(db, month, todayStr());
    const versions = await versionsOf(db, month);
    const current = versions[0];
    const paid = await paidByWorker(db, month);
    const adv = await advancesByWorker(db, month);

    const names = new Map((await db.query('select id, full_name from workers')).rows.map((w) => [w.id, w.full_name]));
    const workers = [...p.workers.entries()]
      .map(([id, w]) => {
        const paidTotal = paid.get(id) ?? 0;
        const advance = adv.get(id) ?? 0;
        return {
          workerId: id,
          fullName: names.get(id),
          days: w.lines.length,
          total: w.total,
          advances: advance,
          paid: paidTotal,
          balance: w.total.sub(Rational.int(advance + paidTotal)),
          lines: w.lines,
        };
      })
      .sort((a, b) => a.fullName.localeCompare(b.fullName, 'fr'));

    res.json({
      month,
      label: monthLabel(month),
      locked: Boolean(current && !current.unlocked_at),
      currentVersion: current?.version ?? null,
      total: p.total,
      hasBlocking: p.hasBlocking,
      teams: p.teams.map((t) => ({ teamId: t.id, name: t.name, total: p.teamTotals.get(t.id) ?? Rational.ZERO })),
      workers,
      anomalies: p.anomalies,
      versions: versions.map((v) => ({
        version: v.version, total: Rational.parse(v.total_exact), validatedBy: v.validated_by, validatedAt: v.validated_at,
        unlockedBy: v.unlocked_by, unlockedAt: v.unlocked_at, unlockReason: v.unlock_reason,
      })),
    });
  }));

  // Validation + verrouillage : bloquée tant qu'une anomalie bloquante subsiste.
  r.post('/:month/validate', ah(async (req, res) => {
    const month = assertMonth(req.params.month);
    const out = await db.tx(async (q) => {
      if ((await q.query('select 1 from payroll_versions where month = $1 and unlocked_at is null', [month])).rowCount) {
        throw conflict('Cette paie est déjà verrouillée.', 'already_locked');
      }
      const p = await payrollForMonth(q, month, todayStr());
      if (p.hasBlocking) {
        const n = p.anomalies.filter((a) => a.blocking).length;
        throw conflict(`Validation bloquée : ${n} anomalie(s) bloquante(s).`, 'blocking_anomalies');
      }
      const version = (await q.query('select coalesce(max(version), 0) + 1 as v from payroll_versions where month = $1', [month])).rows[0].v;
      await q.query(
        'insert into payroll_versions (month, version, total_exact, validated_by) values ($1,$2,$3,$4)',
        [month, version, p.total.toString(), req.user.id],
      );
      await logAudit(q, req.user, {
        action: 'Validation et verrouillage de paie',
        object: monthLabel(month),
        newValue: `v${version} · ${p.total.toFixed(2)} FCFA`,
      });
      return { version, total: p.total };
    });
    res.status(201).json(out);
  }));

  // Déverrouillage : motif obligatoire ; la version précédente reste conservée.
  r.post('/:month/unlock', ah(async (req, res) => {
    const month = assertMonth(req.params.month);
    const { reason } = z.object({ reason: z.string().trim().min(3, 'Le motif est obligatoire.').max(300) }).parse(req.body);
    await db.tx(async (q) => {
      const v = (await q.query('select version from payroll_versions where month = $1 and unlocked_at is null for update', [month])).rows[0];
      if (!v) throw conflict("Cette paie n'est pas verrouillée.", 'not_locked');
      await q.query(
        'update payroll_versions set unlocked_by = $3, unlocked_at = now(), unlock_reason = $4 where month = $1 and version = $2',
        [month, v.version, req.user.id, reason],
      );
      await logAudit(q, req.user, {
        action: 'Déverrouillage de paie',
        object: monthLabel(month),
        oldValue: `v${v.version} verrouillée`,
        reason,
      });
    });
    res.json({ ok: true });
  }));

  // Export CSV de contrôle (montants exacts, sans donnée sensible).
  r.get('/:month/csv', ah(async (req, res) => {
    const month = assertMonth(req.params.month);
    const p = await payrollForMonth(db, month, todayStr());
    const paid = await paidByWorker(db, month);
    const adv = await advancesByWorker(db, month);
    const names = new Map((await db.query('select id, full_name from workers')).rows.map((w) => [w.id, w.full_name]));
    const dec = (r) => r.toFixed(2).replace('.', ',');

    const lines = ['Ouvrier;Jours;Total exact (FCFA);Avances (FCFA);Payé (FCFA);Solde exact (FCFA)'];
    for (const [id, w] of [...p.workers.entries()].sort((a, b) => names.get(a[0]).localeCompare(names.get(b[0]), 'fr'))) {
      const pd = paid.get(id) ?? 0;
      const av = adv.get(id) ?? 0;
      lines.push([csvField(names.get(id)), w.lines.length, dec(w.total), av, pd, dec(w.total.sub(Rational.int(av + pd)))].join(';'));
    }
    await logAudit(db, req.user, { action: 'Export CSV', object: `Paie ${monthLabel(month)}` });
    res.set({
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="paie-${month}.csv"`,
    });
    res.send('﻿' + lines.join('\n') + '\n');
  }));

  return r;
}
