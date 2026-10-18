import { z } from 'zod';
import { badRequest } from './errors.js';

// Un champ vide envoyé par un formulaire équivaut à « non renseigné ».
const empty = (v) => (typeof v === 'string' && v.trim() === '' ? null : v);

const phone = z
  .string()
  .trim()
  .regex(/^\+?[0-9][0-9 .-]{5,19}$/, 'Numéro de téléphone invalide (chiffres, espaces et + autorisés).');

/** Coordonnées d'un ouvrier : toutes facultatives. */
export const contactFields = {
  phone: z.preprocess(empty, phone.nullable().optional()),
  village: z.preprocess(empty, z.string().trim().max(80).nullable().optional()),
  mobileOperator: z.preprocess(empty, z.enum(['orange', 'moov', 'telecel', 'other']).nullable().optional()),
  mobileNumber: z.preprocess(empty, phone.nullable().optional()),
};

/** Le numéro mobile money n'a de sens qu'avec son opérateur (et inversement). */
export function assertMobileConsistency({ mobileOperator, mobileNumber }) {
  if (Boolean(mobileOperator) !== Boolean(mobileNumber)) {
    throw badRequest("Indiquez à la fois l'opérateur et le numéro mobile money.");
  }
}
