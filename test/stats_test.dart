import 'dart:convert';

import 'package:app/data/api_client.dart';
import 'package:app/data/app_store.dart';
import 'package:app/ui/admin/stats_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _m(String v) => {'exact': '$v/1', 'value': '$v.00', 'approx': false};

void main() {
  testWidgets('statistiques : totaux, tendance, classements équipes et ouvriers', (tester) async {
    final body = {
      'month': '2026-03',
      'label': 'Mars 2026',
      'totals': {
        'bricks': 1500, 'workedDays': 2, 'attendanceRate': 0.9, 'avgBricksPerDay': 750,
        'bestDay': {'date': '2026-03-02', 'bricks': 900},
        'cost': _m('262500'), 'sale': _m('375000'), 'margin': _m('112500'),
      },
      'trend': [
        for (var i = 0; i < 6; i++)
          {'month': '2026-0${i + 1}', 'label': 'Mois $i', 'bricks': 100 * i, 'workedDays': i, 'attendanceRate': 0.8,
           'cost': _m('0'), 'sale': _m('0'), 'margin': _m('0')},
      ],
      'teams': [
        {'teamId': 't', 'name': 'Équipe A', 'bricks': 1500, 'workedDays': 2, 'avgBricksPerDay': 750, 'bricksPerPresent': 75, 'attendanceRate': 0.9},
      ],
      'workers': [
        {'workerId': 'w', 'fullName': 'Awa Traore', 'present': 2, 'absent': 0, 'attendanceRate': 1.0, 'earned': _m('26250')},
      ],
      'daily': [
        {'date': '2026-03-02', 'bricks': 900},
        {'date': '2026-03-03', 'bricks': 600},
      ],
    };
    final store = AppStore(ApiClient(
      baseUrl: 'http://test.local',
      client: MockClient((r) async => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'})),
    ));
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(StoreScope(store: store, child: const MaterialApp(home: Scaffold(body: StatsScreen()))));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Classement des équipes'), findsOneWidget);
    expect(find.text('Équipe A'), findsOneWidget);
    expect(find.text('Awa Traore'), findsOneWidget);
    expect(find.text('100 %'), findsOneWidget);
    expect(find.text('02/03/2026 · 900'), findsOneWidget);
  });
}
