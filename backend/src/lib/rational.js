const abs = (x) => (x < 0n ? -x : x);
const gcd = (a, b) => {
  while (b) [a, b] = [b, a % b];
  return a;
};

/**
 * Rationnel exact (BigInt). Une part de 175 000 / 8 ou 17 500 / 3 reste exacte
 * dans tous les calculs : aucun arrondi journalier, aucun flottant binaire.
 */
export class Rational {
  constructor(n, d = 1n) {
    n = BigInt(n);
    d = BigInt(d);
    if (d === 0n) throw new RangeError('Division par zéro');
    if (d < 0n) {
      n = -n;
      d = -d;
    }
    const g = gcd(abs(n), d);
    this.n = g > 1n ? n / g : n;
    this.d = g > 1n ? d / g : d;
  }

  static int(v) {
    return new Rational(BigInt(v), 1n);
  }

  static parse(s) {
    const [n, d] = String(s).split('/');
    return new Rational(BigInt(n), BigInt(d ?? 1));
  }

  static ZERO = new Rational(0n, 1n);

  add(o) { return new Rational(this.n * o.d + o.n * this.d, this.d * o.d); }
  sub(o) { return new Rational(this.n * o.d - o.n * this.d, this.d * o.d); }
  mul(o) { return new Rational(this.n * o.n, this.d * o.d); }
  div(o) { return new Rational(this.n * o.d, this.d * o.n); }
  cmp(o) { const l = this.n * o.d, r = o.n * this.d; return l < r ? -1 : l > r ? 1 : 0; }
  eq(o) { return this.n === o.n && this.d === o.d; }
  get isZero() { return this.n === 0n; }
  get isNegative() { return this.n < 0n; }

  /** Entier le plus proche, 0,5 arrondi vers le haut (règle à confirmer, point 19 du cahier). */
  roundHalfUp() {
    return Number(this.#scaledRound(0));
  }

  isExactAt(places) {
    return (abs(this.n) * 10n ** BigInt(places)) % this.d === 0n;
  }

  /** Écriture décimale avec `places` décimales (point séparateur). */
  toFixed(places = 2) {
    const q = this.#scaledRound(places);
    const scale = 10n ** BigInt(places);
    const sign = this.n < 0n && q !== 0n ? '-' : '';
    const int = abs(q) / scale;
    if (places === 0) return `${sign}${int}`;
    return `${sign}${int}.${(abs(q) % scale).toString().padStart(places, '0')}`;
  }

  #scaledRound(places) {
    const scaled = abs(this.n) * 10n ** BigInt(places);
    const q = (scaled * 2n + this.d) / (this.d * 2n);
    return this.n < 0n ? -q : q;
  }

  toString() {
    return `${this.n}/${this.d}`;
  }

  /** Représentation JSON : valeur exacte + affichage décimal. Jamais d'arrondi caché. */
  toJSON() {
    return { exact: this.toString(), value: this.toFixed(2), approx: !this.isExactAt(2) };
  }
}

export const sum = (items) => items.reduce((a, b) => a.add(b), Rational.ZERO);
