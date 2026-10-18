import bcrypt from 'bcryptjs';
import { z } from 'zod';

export const PIN_COST = 10;

/** PIN : 4 à 6 chiffres. Jamais stocké en clair (bcrypt). */
export const pinSchema = z.string().regex(/^\d{4,6}$/, 'Le code PIN doit contenir 4 à 6 chiffres.');

export const hashPin = (pin, cost = PIN_COST) => bcrypt.hash(pin, cost);
export const verifyPin = (pin, hash) => bcrypt.compare(pin, hash);
