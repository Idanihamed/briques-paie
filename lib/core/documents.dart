import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/models.dart';
import 'format.dart';

/// Documents PDF (fiche de paie, état mensuel, paie sur période), générés sur l'appareil à partir
/// des chiffres exacts du serveur. Réservés à l'admin : ils contiennent des montants.

/// Polices Roboto embarquées (licence Apache 2.0) : accents, « Ê », « € » etc. s'impriment correctement.
pw.ThemeData? _theme;

Future<pw.ThemeData> pdfTheme() async {
  if (_theme != null) return _theme!;
  Future<pw.Font> load(String f) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$f'));
  return _theme = pw.ThemeData.withFont(
    base: await load('Roboto-Regular.ttf'),
    bold: await load('Roboto-Bold.ttf'),
    italic: await load('Roboto-Italic.ttf'),
    boldItalic: await load('Roboto-BoldItalic.ttf'),
  );
}

/// Nettoie un texte avant impression : espaces insécables et coches ne sont pas dans la police.
String pdfSafe(String s) => s
    .replaceAll(' ', ' ')
    .replaceAll(' ', ' ')
    .replaceAll('✓', '')
    .replaceAll('✔', '');

String _monthLabel(String month) => fmtMonth(int.parse(month.substring(0, 4)), int.parse(month.substring(5, 7)));

pw.Widget _header(String title, String subtitle) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Briques & Paie', style: const pw.TextStyle(fontSize: 11, color: PdfColors.blueGrey700)),
      pw.SizedBox(height: 4),
      pw.Text(pdfSafe(title), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.Text(pdfSafe(subtitle), style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
      pw.SizedBox(height: 14),
    ]);

pw.Widget _table(List<String> headers, List<List<String>> rows, {Map<int, pw.Alignment>? align}) => pw.TableHelper.fromTextArray(
      headers: headers.map(pdfSafe).toList(),
      data: [for (final r in rows) r.map(pdfSafe).toList()],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
      cellStyle: const pw.TextStyle(fontSize: 10),
      cellAlignments: align ?? {for (var i = 1; i < headers.length; i++) i: pw.Alignment.centerRight},
      rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
    );

pw.Widget _totals(List<(String, String, bool)> rows) => pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 14),
      child: pw.SizedBox(
        width: 260,
        child: pw.Column(children: [
          for (final (k, v, bold) in rows)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text(pdfSafe(k), style: pw.TextStyle(fontSize: 11, fontWeight: bold ? pw.FontWeight.bold : null)),
                pw.Text(pdfSafe(v), style: pw.TextStyle(fontSize: 11, fontWeight: bold ? pw.FontWeight.bold : null)),
              ]),
            ),
        ]),
      ),
    );

pw.Widget _signatures() => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 40),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text("Signature de l'ouvrier", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.Text('Signature du responsable', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      ]),
    );

pw.Widget _footer(pw.Context c) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Page ${c.pageNumber}/${c.pagesCount}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
    );

/// Fiche de paie d'un ouvrier pour un mois.
Future<Uint8List> payslipPdf(WorkerSheet s) async {
  final doc = pw.Document(title: 'Fiche de paie ${s.worker.fullName}', theme: await pdfTheme());
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    footer: _footer,
    build: (_) => [
      _header('Fiche de paie', '${s.worker.fullName} - ${_monthLabel(s.month)}'),
      pw.Text(
          pdfSafe('Présent ${s.present} j - Absent ${s.absent} j - Taux de présence ${s.attendanceRate == null ? '-' : '${(s.attendanceRate! * 100).round()} %'}'),
          style: const pw.TextStyle(fontSize: 11)),
      pw.SizedBox(height: 10),
      _table(
        ['Date', 'Équipe', 'Situation', 'Part (FCFA)'],
        [
          for (final l in s.lines)
            [
              fmtDate(l.date),
              l.teamName ?? '',
              l.status == Presence.present
                  ? 'Présent${l.isSubstitute ? ' (remplaçant)' : ''}'
                  : l.status == Presence.absent
                      ? 'Absent${l.absenceReason != null ? ' - ${absenceReasonLabels[l.absenceReason] ?? ''}' : ''}'
                      : 'Non saisi',
              l.share == null ? '' : fmtMoney(l.share!, unit: false),
            ],
        ],
        align: {3: pw.Alignment.centerRight},
      ),
      _totals([
        ('Total gagné', fmtMoney(s.earned), false),
        if (s.advanced > 0) ('Avances déduites', fmtFcfa(s.advanced), false),
        ('Déjà payé', fmtFcfa(s.paid), false),
        ('Solde à payer', fmtMoney(s.balance), true),
      ]),
      if (s.advances.isNotEmpty) ...[
        pw.SizedBox(height: 14),
        pw.Text('Avances', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        for (final a in s.advances)
          pw.Text('${fmtDate(a.givenAt.substring(0, 10))} - ${fmtFcfa(a.amount)}${a.note == null ? '' : ' - ${pdfSafe(a.note!)}'}',
              style: const pw.TextStyle(fontSize: 10)),
      ],
      _signatures(),
    ],
  ));
  return doc.save();
}

/// État de paie du mois : tous les ouvriers, avances, paiements et soldes.
Future<Uint8List> payrollPdf(PayrollView v) async {
  final doc = pw.Document(title: 'Paie ${_monthLabel(v.month)}', theme: await pdfTheme());
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(28),
    footer: _footer,
    build: (_) => [
      _header('État de paie', '${_monthLabel(v.month)}${v.locked ? ' - validée' : ' - provisoire'}'),
      _table(
        ['Ouvrier', 'Jours', 'Total (FCFA)', 'Avances', 'Payé', 'Solde (FCFA)'],
        [
          for (final w in v.workers)
            [w.fullName, '${w.days}', fmtMoney(w.total, unit: false), fmtInt(w.advances), fmtInt(w.paid), fmtMoney(w.balance, unit: false)],
        ],
      ),
      _totals([('Total de la paie', fmtMoney(v.total), true)]),
      if (v.teams.isNotEmpty) ...[
        pw.SizedBox(height: 14),
        pw.Text('Par équipe', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        for (final t in v.teams) pw.Text('${pdfSafe(t.name)} : ${pdfSafe(fmtMoney(t.total))}', style: const pw.TextStyle(fontSize: 10)),
      ],
      _signatures(),
    ],
  ));
  return doc.save();
}

/// Paie sur une période libre (à titre d'information).
Future<Uint8List> periodPdf(PeriodReport r) async {
  final doc = pw.Document(title: 'Paie ${r.label}', theme: await pdfTheme());
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    footer: _footer,
    build: (_) => [
      _header('Paie sur période', "${r.label} (${r.days} jours) - à titre d'information"),
      _table(
        ['Ouvrier', 'Jours', 'Montant (FCFA)'],
        [for (final w in r.workers) [w.fullName, '${w.days}', fmtMoney(w.total, unit: false)]],
      ),
      _totals([
        ('Briques confectionnées', fmtInt(r.bricks), false),
        ('Total payé aux équipes', fmtMoney(r.cost), true),
      ]),
      if (r.incompleteDays > 0)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Text('${r.incompleteDays} journée(s) incomplète(s) non comptée(s) dans ce total.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.red800)),
        ),
      _signatures(),
    ],
  ));
  return doc.save();
}

Future<void> sharePdf(Uint8List bytes, String filename) => Printing.sharePdf(bytes: bytes, filename: filename);
