import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

/**
 * Chiffrement AES-256-GCM de la signature faciale (donnée biométrique sensible).
 * Format stocké : iv(12) | tag(16) | données chiffrées.
 * Seule la signature (vecteur de nombres calculé sur l'appareil) est conservée,
 * jamais la photo.
 */
export function encryptTemplate(key, plain) {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const enc = Buffer.concat([cipher.update(plain), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), enc]);
}

export function decryptTemplate(key, blob) {
  const buf = Buffer.from(blob);
  const decipher = createDecipheriv('aes-256-gcm', key, buf.subarray(0, 12));
  decipher.setAuthTag(buf.subarray(12, 28));
  return Buffer.concat([decipher.update(buf.subarray(28)), decipher.final()]);
}
