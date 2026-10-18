import 'dart:convert';

import 'package:app/data/api_client.dart';
import 'package:app/data/app_store.dart';
import 'package:app/ui/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _cell(String state, {bool working = true, String kind = 'work', int? bricks}) => {
      'teamId': 't1',
      'working': working,
      'kind': kind,
      'reason': null,
      'source': working ? 'default' : 'weekly',
      'state': state,
      'bricks': bricks,
    };

void main() {
  testWidgets('calendrier : états des jours, repos hebdomadaire et actions admin', (tester) async {
    final now = DateTime.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final days = [
      for (var d = 1; d <= DateTime(now.year, now.month + 1, 0).day; d++)
        {
          'date': '$month-${d.toString().padLeft(2, '0')}',
          'weekday': DateTime(now.year, now.month, d).weekday % 7,
          'teams': [
            d == 1 ? _cell('complete', bricks: 900) : d == 2 ? _cell('off', working: false, kind: 'rest') : _cell('future'),
          ],
        },
    ];
    final store = AppStore(ApiClient(
      baseUrl: 'http://test.local',
      client: MockClient((r) async {
        if (r.url.path == '/api/calendar') {
          return _json({
            'month': month,
            'today': '$month-15',
            'restWeekdays': [0],
            'teams': [
              {'id': 't1', 'name': 'Équipe A'},
            ],
            'days': days,
          });
        }
        return _json({'error': 'Route introuvable.'}, 404);
      }),
    ));

    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(
        home: Scaffold(body: CalendarView(isAdmin: true, onOpenDay: (_, _, _) {})),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('Repos hebdomadaire : Dim'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsWidgets); // le 1er : saisie complète
    expect(find.text('Déclarer des jours non travaillés'), findsOneWidget);
    expect(find.text('Jours de repos'), findsOneWidget);
  });
}
