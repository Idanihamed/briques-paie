/**
 * Sauvegarde de toutes les données métier en un fichier JSON lisible (archive, contrôle, migration).
 * Les secrets n'y figurent jamais : ni PIN (même hachés), ni signatures de visage, ni compteurs de connexion.
 */
const TABLES = [
  ['teams', 'select * from teams order by created_at'],
  ['workers', `select id, full_name, phone, village, mobile_operator, mobile_number, team_id, active, face_enrolled, created_at
                 from workers order by created_at`],
  ['users', 'select id, name, role, worker_id, active, created_at from users order by created_at'],
  ['tariffs', 'select * from tariffs order by created_at'],
  ['app_settings', 'select * from app_settings order by key'],
  ['calendar_days', 'select * from calendar_days order by work_date, id'],
  ['day_entries', 'select * from day_entries order by work_date, id'],
  ['day_presences', 'select * from day_presences order by work_date, entry_id'],
  ['payroll_versions', 'select * from payroll_versions order by month, version'],
  ['payments', 'select * from payments order by paid_at'],
  ['advances', 'select * from advances order by created_at'],
  ['clients', 'select * from clients order by created_at'],
  ['invoices', 'select * from invoices order by issued_on, number'],
  ['audit_log', 'select * from audit_log order by id'],
];

export async function buildBackup(db) {
  const tables = {};
  const counts = {};
  for (const [name, sql] of TABLES) {
    const { rows } = await db.query(sql);
    tables[name] = rows;
    counts[name] = rows.length;
  }
  return { app: 'briques-paie', format: 1, createdAt: new Date().toISOString(), counts, tables };
}
