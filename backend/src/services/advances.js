/** Avances d'un mois, par ouvrier : Map(workerId -> montant total). */
export async function advancesByWorker(q, month) {
  const rows = (await q.query('select worker_id, sum(amount)::int as s from advances where month = $1 group by worker_id', [month])).rows;
  return new Map(rows.map((x) => [x.worker_id, x.s]));
}
