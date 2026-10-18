import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/models.dart';
import 'documents.dart';
import 'format.dart';

/// Facture au format de l'association : logo et nom en en-tête, bloc client, tableau vert,
/// montant en lettres, signature, pied de page. L'en-tête, le client et le signataire sont ceux
/// enregistrés dans la facture au moment de son émission.
const _green = PdfColor.fromInt(0xFF1F5C2E);
const _greenLight = PdfColor.fromInt(0xFFE8F0E9);
const _blue = PdfColor.fromInt(0xFF3A5A9B);

String _zero(int n) => n == 0 ? '00' : fmtInt(n);

pw.Widget _kv(String k, String v) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 1.5),
      child: pw.RichText(
        text: pw.TextSpan(style: const pw.TextStyle(fontSize: 10), children: [
          pw.TextSpan(text: '$k : ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.TextSpan(text: pdfSafe(v)),
        ]),
      ),
    );

pw.Widget _cell(String t, {pw.Alignment align = pw.Alignment.center, bool bold = false, PdfColor? color, double size = 10}) => pw.Container(
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(pdfSafe(t), style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null, color: color)),
    );

Future<Uint8List> invoicePdf(Invoice inv, {Uint8List? logo}) async {
  final logoBytes = logo ?? (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
  final doc = pw.Document(title: 'Facture ${inv.number}', theme: await pdfTheme());
  final c = inv.client;
  final lh = inv.letterhead;

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 32, 40, 36),
    footer: (_) => pw.Column(children: [
      pw.Divider(height: 8, thickness: 0.6, color: PdfColors.grey700),
      pw.Text(pdfSafe(lh.footer), style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
    ]),
    build: (_) => [
      pw.Image(pw.MemoryImage(logoBytes), width: 82, height: 82, alignment: pw.Alignment.centerLeft),
      pw.SizedBox(height: 4),
      pw.Text(pdfSafe(lh.name), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
      pw.Divider(height: 8, thickness: 0.8, color: PdfColors.black),
      pw.SizedBox(height: 26),
      pw.Text(pdfSafe('FACTURE N° ${inv.number}'), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _blue)),
      pw.SizedBox(height: 4),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(pdfSafe('${inv.place}, le ${fmtDate(inv.issuedOn)}'),
            style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic)),
      ),
      pw.SizedBox(height: 10),
      pw.Text(pdfSafe('DOIT : ${c.name}'), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _green)),
      pw.SizedBox(height: 4),
      if ((c.status ?? '').isNotEmpty) _kv('Statut', c.status!),
      if ((c.rccm ?? '').isNotEmpty) _kv('RCCM', c.rccm!),
      if ((c.ifu ?? '').isNotEmpty) _kv('IFU', c.ifu!),
      if ((c.capital ?? '').isNotEmpty) _kv('Capital social', c.capital!),
      if ((c.address ?? '').isNotEmpty) _kv('Siège social', c.address!),
      pw.SizedBox(height: 12),
      pw.Text(pdfSafe('Objet : ${inv.subject}'), style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder.all(width: 0.6),
        columnWidths: const {
          0: pw.FlexColumnWidth(1.4),
          1: pw.FlexColumnWidth(2.2),
          2: pw.FlexColumnWidth(1.1),
          3: pw.FlexColumnWidth(1.3),
          4: pw.FlexColumnWidth(1.6),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _green),
            children: [
              for (final h in ['Date', 'Désignation', 'Quantité', 'Prix Unitaire', 'Montant (FCFA)'])
                _cell(h, bold: true, color: PdfColors.white),
            ],
          ),
          for (final l in inv.lines)
            pw.TableRow(children: [
              _cell(l.date == null ? '' : fmtDate(l.date!)),
              _cell(l.label),
              _cell(_zero(l.qty)),
              _cell(fmtInt(inv.unitPrice)),
              _cell(_zero(l.qty * inv.unitPrice), align: pw.Alignment.centerRight),
            ]),
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _greenLight),
            children: [
              _cell('', bold: true),
              _cell('MONTANT TOTAL', bold: true, align: pw.Alignment.centerRight),
              _cell(fmtInt(inv.totalQty), bold: true),
              _cell(fmtInt(inv.unitPrice), bold: true),
              _cell('${fmtInt(inv.totalAmount)} FCFA', bold: true, align: pw.Alignment.centerRight),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.RichText(
        text: pw.TextSpan(style: const pw.TextStyle(fontSize: 10), children: [
          const pw.TextSpan(text: 'Arrêtée la présente facture à la somme de: '),
          pw.TextSpan(text: '${pdfSafe(inv.amountWords)}.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ]),
      ),
      if (inv.status == 'cancelled')
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(pdfSafe('FACTURE ANNULÉE${inv.cancelReason == null ? '' : ' : ${inv.cancelReason}'}'),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
        ),
      pw.SizedBox(height: 34),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text("Pour l'${pdfSafe(_assoc(lh.name))},", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 34),
          pw.Text(pdfSafe(inv.signer), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ]),
      ),
    ],
  ));
  return doc.save();
}

/// « ASSOCIATION BAYIIR MÊTBA » → « Association Bayiir Mêtba » pour la formule « Pour l'… ».
String _assoc(String name) => name
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');
