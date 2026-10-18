import 'package:app/core/documents.dart';
import 'package:app/core/invoice_pdf.dart';
import 'package:app/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _m(String v) => {'exact': '$v/1', 'value': '$v.00', 'approx': false};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pdfSafe retire seulement ce que la police ne sait pas afficher (les accents restent)', () {
    expect(pdfSafe('≈ 1 000 ✓ é Ê'), '≈ 1 000  é Ê');
  });

  test('fiche de paie, état mensuel et période : PDF valides', () async {
    final sheet = WorkerSheet.fromJson({
      'worker': {'id': 'w', 'fullName': 'Awa Traoré', 'active': true, 'faceEnrolled': true, 'isSupervisor': false, 'teamId': null, 'teamName': null},
      'month': '2026-03',
      'locked': false,
      'stats': {'present': 1, 'absent': 1, 'unset': 0, 'attendanceRate': 0.5, 'absences': {'sick': 1}},
      'earned': _m('1750'),
      'paid': 0,
      'advanced': 500,
      'advances': [
        {'id': 'a', 'amount': 500, 'givenAt': '2026-03-05', 'mode': 'cash', 'note': 'Quinzaine'},
      ],
      'balance': _m('1250'),
      'lines': [
        {'date': '2026-03-02', 'teamName': 'Équipe A', 'status': 'present', 'isSubstitute': false, 'faceVerified': true, 'absenceReason': null, 'dayStatus': 'ok', 'share': _m('1750')},
        {'date': '2026-03-03', 'teamName': 'Équipe A', 'status': 'absent', 'isSubstitute': false, 'faceVerified': false, 'absenceReason': 'sick', 'dayStatus': 'ok', 'share': null},
      ],
      'payments': [],
    });
    final a = await payslipPdf(sheet);
    expect(String.fromCharCodes(a.take(5)), '%PDF-');

    final period = PeriodReport.fromJson({
      'from': '2026-03-01', 'to': '2026-03-07', 'label': '01/03/2026 au 07/03/2026', 'days': 7, 'bricks': 100,
      'cost': _m('17500'), 'sale': _m('25000'), 'margin': _m('7500'), 'incompleteDays': 1,
      'teams': [{'name': 'Équipe A', 'total': _m('17500')}],
      'workers': [{'workerId': 'w', 'fullName': 'Awa Traoré', 'days': 1, 'total': _m('1750')}],
    });
    expect(String.fromCharCodes((await periodPdf(period)).take(5)), '%PDF-');
  });

  test('facture : PDF valide avec en-tête, client et montant en lettres', () async {
    final inv = Invoice.fromJson({
      'id': 'i', 'number': 'ABM/SOPAMIB/2026-07-001', 'issuedOn': '2026-07-15', 'place': 'Ouagadougou',
      'subject': 'Production hebdomadaire de briques BTC (08 au 12 juillet 2026)', 'unitPrice': 200,
      'lines': [
        {'date': '2026-07-08', 'label': 'Brique BTC', 'qty': 169},
        {'date': '2026-07-11', 'label': 'Brique BTC', 'qty': 0},
        {'date': null, 'label': 'Brique BTC (Echantillons)', 'qty': 243},
      ],
      'totalQty': 412, 'totalAmount': 82400, 'amountWords': 'Quatre-vingt-deux mille quatre cents (82 400) francs CFA',
      'signer': 'Le Trésorier',
      'client': {'id': 'c', 'code': 'SOPAMIB', 'name': 'SOPAMIB BOUBOULOU S.A.', 'status': "Société d'État", 'rccm': 'N° BF OUA 01 2024 B30 14310', 'ifu': 'N° 00248483L', 'capital': '10 000 000 Francs CFA', 'address': 'Ouaga 2000', 'active': true},
      'letterhead': {'name': 'ASSOCIATION BAYIIR MÊTBA', 'footer': 'Siege social: YAKO, village Rawinma   Tél: 76 68 47 73 / 62 38 60 56   Passoré - Burkina Faso', 'place': 'Ouagadougou', 'signer': 'Le Trésorier'},
      'status': 'issued',
    });
    final bytes = await invoicePdf(inv);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(20000)); // polices et logo embarqués
  });
}
