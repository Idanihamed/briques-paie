const UNITS = ['zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf', 'dix', 'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize'];
const TENS = ['', '', 'vingt', 'trente', 'quarante', 'cinquante', 'soixante'];

function below100(n, final) {
  if (n < 17) return UNITS[n];
  if (n < 20) return `dix-${UNITS[n - 10]}`;
  if (n < 70) {
    const t = Math.floor(n / 10);
    const u = n % 10;
    return u === 0 ? TENS[t] : u === 1 ? `${TENS[t]} et un` : `${TENS[t]}-${UNITS[u]}`;
  }
  if (n < 80) return n === 71 ? 'soixante et onze' : `soixante-${below100(n - 60, false)}`;
  if (n === 80) return final ? 'quatre-vingts' : 'quatre-vingt';
  return `quatre-vingt-${below100(n - 80, false)}`;
}

function below1000(n, final) {
  const h = Math.floor(n / 100);
  const r = n % 100;
  if (h === 0) return below100(r, final);
  const head = h === 1 ? 'cent' : `${UNITS[h]} cent`;
  if (r === 0) return h > 1 && final ? `${head}s` : head;
  return `${head} ${below100(r, final)}`;
}

/** Entier (0 à 999 999 999) en lettres, orthographe française classique : 287 200 → « deux cent quatre-vingt-sept mille deux cents ». */
export function numberToFrench(n) {
  if (!Number.isInteger(n) || n < 0 || n > 999_999_999) throw new RangeError('Nombre hors limites.');
  if (n === 0) return 'zéro';
  const m = Math.floor(n / 1_000_000);
  const k = Math.floor((n % 1_000_000) / 1000);
  const r = n % 1000;
  const parts = [];
  if (m) parts.push(m === 1 ? 'un million' : `${below1000(m, false)} millions`);
  if (k) parts.push(k === 1 ? 'mille' : `${below1000(k, false)} mille`);
  if (r) parts.push(below1000(r, true));
  return parts.join(' ');
}

const group = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');

/** « Deux cent quatre-vingt-sept mille deux cents (287 200) francs CFA » */
export function amountInWords(n) {
  const w = numberToFrench(n);
  return `${w[0].toUpperCase()}${w.slice(1)} (${group(n)}) francs CFA`;
}
