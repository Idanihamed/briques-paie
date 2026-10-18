import { badRequest } from './errors.js';

export const isDate = (s) => /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(`${s}T00:00:00Z`));
export const isMonth = (s) => /^\d{4}-(0[1-9]|1[0-2])$/.test(s);

/** Date du jour (UTC, = heure du Burkina Faso). */
export const todayStr = () => new Date().toISOString().slice(0, 10);

export function assertDate(s, label = 'date') {
  if (!isDate(s)) throw badRequest(`${label} invalide (format AAAA-MM-JJ).`);
  return s;
}

export function assertMonth(s) {
  if (!isMonth(s)) throw badRequest('Mois invalide (format AAAA-MM).');
  return s;
}

export const monthOf = (date) => date.slice(0, 7);

export function monthBounds(month) {
  const [y, m] = month.split('-').map(Number);
  const next = new Date(Date.UTC(y, m, 1));
  const nextStr = `${next.getUTCFullYear()}-${String(next.getUTCMonth() + 1).padStart(2, '0')}-01`;
  const days = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return { start: `${month}-01`, endExclusive: nextStr, days };
}

export const isSunday = (date) => new Date(`${date}T00:00:00Z`).getUTCDay() === 0;

const MONTHS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
export const monthLabel = (month) => {
  const [y, m] = month.split('-').map(Number);
  return `${MONTHS[m - 1]} ${y}`;
};
export const frDate = (d) => `${d.slice(8, 10)}/${d.slice(5, 7)}/${d.slice(0, 4)}`;
