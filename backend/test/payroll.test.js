import test from 'node:test';
import assert from 'node:assert/strict';
import { Rational } from '../src/lib/rational.js';
import { computeDay, computeMonth, rateFor, productionValue, DayStatus } from '../src/services/payroll.js';

const tariffs = [
  { kind: 'cost', value: 175, effective_date: '2026-01-01', created_at: '2026-01-01' },
  { kind: 'sale', value: 250, effective_date: '2026-01-01', created_at: '2026-01-01' },
];

const workers = (n, status = 'present') => Object.fromEntries(Array.from({ length: n }, (_, i) => [`w${i}`, status]));
const entry = (bricks, presence, date = '2026-10-14', teamId = 't1') => ({ teamId, date, bricks, presence });

test('Rational : exactitude et arrondi', () => {
  const third = new Rational(17500n, 3n);
  assert.equal(third.toString(), '17500/3');
  assert.equal(third.toFixed(2), '5833.33');
  assert.equal(third.roundHalfUp(), 5833);
  assert.equal(third.mul(Rational.int(3)).toString(), '17500/1');
  assert.equal(third.isExactAt(2), false);
  assert.equal(new Rational(5n, 2n).roundHalfUp(), 3);
  assert.equal(new Rational(-5n, 2n).roundHalfUp(), -3);
  assert.deepEqual(JSON.parse(JSON.stringify(third)), { exact: '17500/3', value: '5833.33', approx: true });
});

test('T01 : 100 briques à 175, 10 présents -> 17 500 / part 1 750', () => {
  const r = computeDay(entry(100, workers(10)), tariffs);
  assert.equal(r.status, DayStatus.OK);
  assert.equal(r.total.toString(), '17500/1');
  assert.equal(r.share.toString(), '1750/1');
});

test('le prix de vente (250) n\'entre jamais dans la paie', () => {
  const r = computeDay(entry(100, workers(10)), tariffs);
  assert.equal(r.total.toString(), '17500/1'); // 100 × 175 (confection), pas 250
  assert.equal(productionValue(tariffs, 'sale', '2026-10-14', 100).toString(), '25000/1');
});

test('Annexe A : 1000 briques, 8 présents -> 21 875', () => {
  const r = computeDay(entry(1000, workers(8)), tariffs);
  assert.equal(r.share.toString(), '21875/1');
});

test('T02 : production nulle -> alerte, aucune part', () => {
  const r = computeDay(entry(0, workers(10)), tariffs);
  assert.equal(r.status, DayStatus.ZERO_PRODUCTION);
  assert.ok(r.share.isZero);
});

test('T03 : production > 0 et aucun présent -> bloquant', () => {
  const r = computeDay(entry(100, workers(10, 'absent')), tariffs);
  assert.equal(r.status, DayStatus.NO_PRESENT);
});

test('T04 : « non saisi » n\'est jamais une absence', () => {
  const r = computeDay(entry(100, { ...workers(6), x1: 'absent', x2: 'unset' }), tariffs);
  assert.equal(r.status, DayStatus.INCOMPLETE);
  const noQty = computeDay(entry(null, workers(10)), tariffs);
  assert.equal(noQty.status, DayStatus.INCOMPLETE);
});

test('T05 : changement de tarif en cours de mois', () => {
  const t = [...tariffs, { kind: 'cost', value: 200, effective_date: '2026-10-15', created_at: '2026-10-10' }];
  assert.equal(rateFor(t, 'cost', '2026-10-14'), 175);
  assert.equal(rateFor(t, 'cost', '2026-10-15'), 200);
  assert.equal(rateFor(t, 'cost', '2026-10-31'), 200);
  assert.equal(rateFor(t, 'cost', '2025-12-31'), null);
});

test('tarif manquant -> bloquant', () => {
  const r = computeDay(entry(10, workers(2), '2025-01-01'), tariffs);
  assert.equal(r.status, DayStatus.NO_TARIFF);
});

test('T08 : parts exactes, la somme des parts égale le total (pas d\'arrondi journalier)', () => {
  const e = entry(100, workers(3));
  const r = computeDay(e, tariffs);
  assert.equal(r.share.toString(), '17500/3');
  const month = computeMonth({
    month: '2026-10',
    entries: [e, entry(100, workers(3), '2026-10-15')],
    tariffs,
    teams: [{ id: 't1', name: 'Équipe 1' }],
    today: '2026-10-16',
  });
  const w0 = month.workers.get('w0');
  assert.equal(w0.total.toString(), '35000/3'); // 2 × 17500/3, exact
  const all = [...month.workers.values()].reduce((a, w) => a.add(w.total), Rational.ZERO);
  assert.equal(all.toString(), '35000/1');
  assert.equal(month.total.toString(), '35000/1');
});

test('computeMonth : anomalies bloquantes / non bloquantes et jours sans saisie', () => {
  const month = computeMonth({
    month: '2026-10',
    entries: [
      entry(100, workers(10), '2026-10-12'),
      entry(0, workers(10), '2026-10-13'),
      entry(5, workers(10, 'absent'), '2026-10-14'),
    ],
    tariffs,
    teams: [{ id: 't1', name: 'Équipe 1' }],
    today: '2026-10-15',
  });
  assert.equal(month.hasBlocking, true);
  const kinds = new Set(month.anomalies.map((a) => a.kind));
  assert.ok(kinds.has('zero_production') && kinds.has('no_present') && kinds.has('missing_day'));
  // dimanche 4 octobre : jamais signalé comme jour manquant
  assert.ok(!month.anomalies.some((a) => a.date === '2026-10-04'));
});
