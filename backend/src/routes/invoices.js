import { Router } from 'express';
import { z } from 'zod';
import { ah, badRequest, conflict, notFound } from '../lib/errors.js';
import { logAudit } from '../lib/audit.js';
import { assertDate, frDate, todayStr } from '../lib/dates.js';
import { nextDay } from '../services/days.js';
import { loadEntries, loadTariffs, rateFor } from '../services/payroll.js';
import { amountInWords } from '../services/words.js';

const uuid = z.string().uuid();
const MAX_DAYS = 93;

/** En-tête par défaut : exactement celui des factures actuelles de l'association. */
export const DEFAULT_LETTERHEAD = {
  name: 'ASSOCIATION BAYIIR MÊTBA',
  footer: 'Siege social: YAKO, village Rawinma   Tél: 76 68 47 73 / 62 38 60 56   Passoré - Burkina Faso',
  place: 'Ouagadougou',
  signer: 'Le Trésorier',
};

const letterheadSchema = z.object({
  name: z.string().trim().min(1).max(120),
  footer: z.string().trim().max(300),
  place: z.string().trim().min(1).max(60),
  signer: z.string().trim().min(1).max(80),
});

export async function loadLetterhead(q) {
  const v = (await q.query("select value from app_settings where key = 'letterhead'")).rows[0]?.value;
  const o = typeof v === 'string' ? JSON.parse(v) : v;
  return { ...DEFAULT_LETTERHEAD, ...(o ?? {}) };
}

const optionalText = (max) => z.preprocess((v) => (typeof v === 'string' && v.trim() === '' ? null : v), z.string().trim().max(max).nullable().optional());

const clientSchema = z.object({
  code: z.string().trim().toUpperCase().regex(/^[A-Z0-9]{2,12}$/, 'Code : 2 à 12 lettres ou chiffres (ex. SOPAMIB).'),
  name: z.string().trim().min(1).max(160),
  status: optionalText(200),
  rccm: optionalText(80),
  ifu: optionalText(60),
  capital: optionalText(80),
  address: optionalText(300),
});

const clientDto = (c) => ({
  id: c.id, code: c.code, name: c.name, status: c.status, rccm: c.rccm, ifu: c.ifu, capital: c.capital, address: c.address, active: c.active,
});

const invoiceDto = (i, full) => ({
  id: i.id,
  number: i.number,
  clientId: i.client_id,
  clientName: i.client_snapshot?.name,
  issuedOn: i.issued_on,
  totalQty: i.total_qty,
  totalAmount: Number(i.total_amount),
  status: i.status,
  ...(full ? {
    place: i.place, subject: i.subject, periodFrom: i.period_from, periodTo: i.period_to, unitPrice: i.unit_price,
    lines: i.lines, amountWords: i.amount_words, signer: i.signer, client: i.client_snapshot, letterhead: i.letterhead_snapshot,
    cancelReason: i.cancel_reason,
  } : {}),
});

const lineSchema = z.object({
  date: z.string().nullable().optional(),
  label: z.string().trim().min(1).max(80),
  qty: z.number().int().min(0).max(100_000_000),
});

/**
 * Factures : en-tête et clients modifiables, numérotation automatique (ABM/CLIENT/AAAA-MM-NNN),
 * lignes préremplies avec la production saisie, total en lettres calculé par le serveur.
 * Une facture émise garde une copie de l'en-tête et du client : les modifier plus tard ne la change pas.
 */
export function invoicesRouter({ db, auth, admin }) {
  const r = Router();
  r.use(auth, admin);

  // ── En-tête ──
  r.get('/letterhead', ah(async (_req, res) => res.json(await loadLetterhead(db))));

  r.put('/letterhead', ah(async (req, res) => {
    const b = letterheadSchema.parse(req.body);
    await db.tx(async (q) => {
      const old = await loadLetterhead(q);
      await q.query(
        `insert into app_settings (key, value, updated_by) values ('letterhead', $1::jsonb, $2)
         on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = excluded.updated_by`,
        [JSON.stringify(b), req.user.id],
      );
      await logAudit(q, req.user, { action: "Modification de l'en-tête de facture", object: b.name, oldValue: JSON.stringify(old), newValue: JSON.stringify(b) });
    });
    res.json(b);
  }));

  // ── Clients ──
  r.get('/clients', ah(async (_req, res) => {
    const { rows } = await db.query('select * from clients order by active desc, name');
    res.json(rows.map(clientDto));
  }));

  r.post('/clients', ah(async (req, res) => {
    const b = clientSchema.parse(req.body);
    const out = await db.tx(async (q) => {
      if ((await q.query('select 1 from clients where code = $1', [b.code])).rowCount) throw conflict(`Le code ${b.code} est déjà utilisé.`, 'code_taken');
      const row = (await q.query(
        'insert into clients (code, name, status, rccm, ifu, capital, address) values ($1,$2,$3,$4,$5,$6,$7) returning id',
        [b.code, b.name, b.status ?? null, b.rccm ?? null, b.ifu ?? null, b.capital ?? null, b.address ?? null],
      )).rows[0];
      await logAudit(q, req.user, { action: 'Création de client', object: b.name, newValue: b.code });
      return row;
    });
    res.status(201).json({ id: out.id });
  }));

  r.patch('/clients/:id', ah(async (req, res) => {
    const b = clientSchema.omit({ code: true }).partial().extend({ active: z.boolean().optional() }).parse(req.body);
    await db.tx(async (q) => {
      const c = (await q.query('select * from clients where id = $1 for update', [req.params.id])).rows[0];
      if (!c) throw notFound('Client introuvable.');
      const next = { ...c, ...Object.fromEntries(Object.entries(b).filter(([, v]) => v !== undefined)) };
      await q.query(
        'update clients set name=$2, status=$3, rccm=$4, ifu=$5, capital=$6, address=$7, active=$8 where id=$1',
        [c.id, next.name, next.status ?? null, next.rccm ?? null, next.ifu ?? null, next.capital ?? null, next.address ?? null, next.active],
      );
      await logAudit(q, req.user, { action: 'Modification de client', object: c.name, newValue: Object.keys(b).join(', ') });
    });
    res.json({ ok: true });
  }));

  // ── Brouillon : lignes préremplies avec la production saisie sur la période ──
  r.get('/draft', ah(async (req, res) => {
    const { from, to } = z.object({ from: z.string(), to: z.string() }).parse(req.query);
    assertDate(from, 'début');
    assertDate(to, 'fin');
    if (to < from) throw badRequest('La date de fin précède le début.');
    if ((Date.parse(to) - Date.parse(from)) / 86_400_000 + 1 > MAX_DAYS) throw badRequest(`Période trop longue (${MAX_DAYS} jours au maximum).`);

    const [entries, tariffs] = await Promise.all([loadEntries(db, from, nextDay(to)), loadTariffs(db)]);
    const byDate = new Map();
    for (const e of entries) if (e.bricks != null) byDate.set(e.date, (byDate.get(e.date) ?? 0) + e.bricks);
    res.json({
      from, to,
      suggestedUnitPrice: rateFor(tariffs, 'sale', to),
      lines: [...byDate.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([date, qty]) => ({ date, label: 'Brique BTC', qty })),
    });
  }));

  // ── Factures ──
  r.get('/', ah(async (_req, res) => {
    const { rows } = await db.query('select * from invoices order by issued_on desc, number desc limit 200');
    res.json(rows.map((i) => invoiceDto(i, false)));
  }));

  r.get('/:id', ah(async (req, res) => {
    if (!uuid.safeParse(req.params.id).success) throw notFound('Facture introuvable.');
    const i = (await db.query('select * from invoices where id = $1', [req.params.id])).rows[0];
    if (!i) throw notFound('Facture introuvable.');
    res.json(invoiceDto(i, true));
  }));

  r.post('/', ah(async (req, res) => {
    const b = z.object({
      clientId: uuid,
      issuedOn: z.string().optional(),
      subject: z.string().trim().min(1).max(300),
      periodFrom: z.string().nullable().optional(),
      periodTo: z.string().nullable().optional(),
      unitPrice: z.number().int().min(1).max(10_000_000),
      lines: z.array(lineSchema).min(1, 'Ajoutez au moins une ligne.').max(120),
    }).parse(req.body);
    const issuedOn = assertDate(b.issuedOn ?? todayStr(), "date d'émission");
    for (const l of b.lines) if (l.date) assertDate(l.date, 'date de ligne');
    if (b.periodFrom) assertDate(b.periodFrom, 'début');
    if (b.periodTo) assertDate(b.periodTo, 'fin');

    const totalQty = b.lines.reduce((s, l) => s + l.qty, 0);
    const totalAmount = totalQty * b.unitPrice;
    if (totalAmount > 999_999_999) throw badRequest('Montant trop élevé.');

    // Le numéro suit l'ordre d'émission du mois ; en cas de course, on recommence avec le numéro suivant.
    for (let attempt = 0; attempt < 4; attempt++) {
      try {
        const out = await db.tx(async (q) => {
          const client = (await q.query('select * from clients where id = $1', [b.clientId])).rows[0];
          if (!client) throw notFound('Client introuvable.');
          if (!client.active) throw conflict('Ce client est désactivé.', 'client_inactive');
          const letterhead = await loadLetterhead(q);
          const prefix = `ABM/${client.code}/${issuedOn.slice(0, 7)}-`;
          const last = (await q.query(
            "select coalesce(max(substring(number from '[0-9]+$')::int), 0) as n from invoices where number like $1",
            [`${prefix}%`],
          )).rows[0].n;
          const number = `${prefix}${String(last + 1).padStart(3, '0')}`;
          const row = (await q.query(
            `insert into invoices (number, client_id, issued_on, place, subject, period_from, period_to, unit_price, lines,
                                   total_qty, total_amount, amount_words, signer, client_snapshot, letterhead_snapshot, created_by)
             values ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,$10,$11,$12,$13,$14::jsonb,$15::jsonb,$16) returning id`,
            [number, client.id, issuedOn, letterhead.place, b.subject, b.periodFrom ?? null, b.periodTo ?? null, b.unitPrice,
              JSON.stringify(b.lines.map((l) => ({ date: l.date ?? null, label: l.label, qty: l.qty }))),
              totalQty, totalAmount, amountInWords(totalAmount), letterhead.signer,
              JSON.stringify(clientDto(client)), JSON.stringify(letterhead), req.user.id],
          )).rows[0];
          await logAudit(q, req.user, { action: 'Émission de facture', object: number, newValue: `${totalQty} briques × ${b.unitPrice} = ${totalAmount} FCFA (${client.name}, ${frDate(issuedOn)})` });
          return { id: row.id, number, totalAmount };
        });
        return res.status(201).json(out);
      } catch (e) {
        if (/invoices_number_key|unique/i.test(e?.message ?? '') && attempt < 3) continue;
        throw e;
      }
    }
  }));

  r.post('/:id/cancel', ah(async (req, res) => {
    const { reason } = z.object({ reason: z.string().trim().min(3, 'Indiquez le motif.').max(200) }).parse(req.body);
    await db.tx(async (q) => {
      const i = (await q.query('select number, status from invoices where id = $1 for update', [req.params.id])).rows[0];
      if (!i) throw notFound('Facture introuvable.');
      if (i.status === 'cancelled') throw conflict('Cette facture est déjà annulée.', 'already_cancelled');
      await q.query("update invoices set status = 'cancelled', cancel_reason = $2 where id = $1", [req.params.id, reason]);
      await logAudit(q, req.user, { action: 'Annulation de facture', object: i.number, newValue: reason });
    });
    res.json({ ok: true });
  }));

  return r;
}
