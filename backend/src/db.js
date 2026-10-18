import pg from 'pg';

// Les dates restent des chaînes « YYYY-MM-DD » (pas de décalage de fuseau).
pg.types.setTypeParser(1082, (v) => v);

/**
 * Interface minimale utilisée par toute l'application :
 *   db.query(text, params)          -> { rows }
 *   db.tx(async (q) => { ... })     -> transaction ; q.query(text, params)
 *   db.close()
 * Les tests fournissent une implémentation PGlite avec la même forme.
 */
export function createPgDb({ databaseUrl, ssl = true }) {
  const pool = new pg.Pool({
    connectionString: databaseUrl,
    ssl: ssl ? { rejectUnauthorized: false } : false, // certificat géré par Supabase
    max: 10,
    idleTimeoutMillis: 30_000,
  });

  return {
    query: (text, params) => pool.query(text, params),

    async tx(fn) {
      const client = await pool.connect();
      try {
        await client.query('begin');
        const result = await fn({ query: (t, p) => client.query(t, p) });
        await client.query('commit');
        return result;
      } catch (e) {
        await client.query('rollback').catch(() => {});
        throw e;
      } finally {
        client.release();
      }
    },

    close: () => pool.end(),
  };
}
