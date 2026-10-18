import '../domain/models.dart';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String two(int v) => v.toString().padLeft(2, '0');

/// « AAAA-MM-JJ » : format d'échange avec l'API.
String dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
String monthKey(int year, int month) => '$year-${two(month)}';
DateTime parseDate(String s) => DateTime.parse(s.length > 10 ? s : '${s}T00:00:00');

/// Date « AAAA-MM-JJ » ou ISO complet -> JJ/MM/AAAA.
String fmtDate(String iso) => '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}';
String fmtDateTime(String iso) {
  final d = DateTime.parse(iso).toLocal();
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

const _months = [
  'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août',
  'Septembre', 'Octobre', 'Novembre', 'Décembre',
];
const _weekdays = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

String fmtMonth(int year, int month) => '${_months[month - 1]} $year';
String fmtLongDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1].toLowerCase()} ${d.year}';

String _group(String digits) {
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(' ');
    b.write(digits[i]);
  }
  return b.toString();
}

String fmtInt(int v) => (v < 0 ? '-' : '') + _group(v.abs().toString());

/// Montant exact renvoyé par le serveur. Le serveur calcule en fractions exactes ;
/// si la valeur n'est pas exacte à 2 décimales elle est préfixée de « ≈ » (jamais d'arrondi caché).
String fmtMoney(Money m, {bool unit = true}) {
  var s = m.value;
  final neg = s.startsWith('-');
  if (neg) s = s.substring(1);
  final parts = s.split('.');
  var out = _group(parts[0]);
  if (parts.length > 1 && parts[1] != '00') out += ',${parts[1]}';
  if (neg) out = '-$out';
  if (m.approx) out = '≈ $out';
  return unit ? '$out FCFA' : out;
}

String fmtFcfa(int v) => '${fmtInt(v)} FCFA';
