import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { PGlite, types } from '@electric-sql/pglite';
import { createApp } from '../src/app.js';
import { fakeFaces, seedFixtures } from './fixtures.js';

/** Base de test : le VRAI schema.sql exécuté dans PGlite (PostgreSQL en WebAssembly). */
export async function createTestDb() {
  const pg = new PGlite({ parsers: { [types.DATE]: (v) => v } });
  const sql = await readFile(fileURLToPath(new URL('../db/schema.sql', import.meta.url)), 'utf8');
  await pg.exec(sql);
  const wrap = async (p) => {
    const r = await p;
    return { ...r, rowCount: r.rows.length };
  };
  return {
    query: (t, p) => wrap(pg.query(t, p)),
    tx: (fn) => pg.transaction((tx) => fn({ query: (t, p) => wrap(tx.query(t, p)) })),
    close: () => pg.close(),
  };
}

export const TEST_CONFIG = {
  port: 0,
  jwtSecret: 'x'.repeat(40),
  jwtTtl: '1h',
  faceKey: Buffer.alloc(32, 7),
  faceThreshold: 0.5,
  corsOrigins: [],
  isProd: false,
};

/** Application + base + données de démonstration + petit client HTTP. */
export async function startTestApp() {
  const db = await createTestDb();
  const seed = await seedFixtures(db, { cost: 4, year: 2025 });
  const app = createApp({ db, config: TEST_CONFIG, pinCost: 4, faces: fakeFaces() });
  const server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  const base = `http://127.0.0.1:${server.address().port}`;

  async function api(method, path, { token, body } = {}) {
    const res = await fetch(base + path, {
      method,
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    let json;
    try { json = JSON.parse(text); } catch { json = text; }
    return { status: res.status, body: json };
  }

  async function login(name, pin) {
    const r = await api('POST', '/api/auth/login', { body: { name, pin } });
    assert(r.status === 200, `login ${name} : ${r.status} ${JSON.stringify(r.body)}`);
    return r.body.token;
  }

  return {
    db, seed, api, login,
    close: async () => { server.close(); await db.close(); },
  };
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}
