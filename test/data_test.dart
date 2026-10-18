import 'dart:convert';

import 'package:app/data/api_client.dart';
import 'package:app/data/app_store.dart';
import 'package:app/ui/admin/data_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('import : vérification affichée avant tout enregistrement', (tester) async {
    final bodies = <Map<String, dynamic>>[];
    final store = AppStore(ApiClient(
      baseUrl: 'http://test.local',
      client: MockClient((r) async {
        bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
        return http.Response(
            jsonEncode({
              'dryRun': true,
              'imported': 0,
              'counts': {'ok': 1, 'duplicate': 0, 'error': 1},
              'rows': [
                {'line': 1, 'name': 'Awa Traore', 'status': 'ok', 'message': ''},
                {'line': 2, 'name': 'Paul', 'status': 'error', 'message': 'Équipe inconnue « X ».'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    ));
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(StoreScope(store: store, child: const MaterialApp(home: Scaffold(body: DataScreen()))));

    await tester.enterText(find.byType(TextField), 'Awa Traore\nPaul\t\t\t\t\tX');
    await tester.pump();
    await tester.tap(find.text('Vérifier'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(bodies.single['dryRun'], isTrue);
    expect(find.textContaining('1 prêt(s) à importer'), findsOneWidget);
    expect(find.text('Importer 1 ouvrier'), findsOneWidget);
    expect(find.textContaining('Équipe inconnue'), findsOneWidget);
  });
}
