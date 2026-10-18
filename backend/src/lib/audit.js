/**
 * Écrit une ligne du journal d'audit. `q` est une transaction (ou le pool) :
 * dans une transaction, l'audit est validé ou annulé avec l'action elle-même.
 * La table est en ajout seul (trigger en base) : aucune suppression ordinaire.
 */
export async function logAudit(q, actor, { action, object, oldValue, newValue, reason, security = false }) {
  await q.query(
    `insert into audit_log (user_id, user_name, role, action, object, old_value, new_value, reason, security)
     values ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
    [
      actor?.id ?? null,
      actor?.name ?? 'Système',
      actor?.role ?? '-',
      action,
      object,
      oldValue ?? null,
      newValue ?? null,
      reason ?? null,
      security,
    ],
  );
}
