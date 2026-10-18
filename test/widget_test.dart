import 'dart:convert';

import 'package:app/core/format.dart';
import 'package:app/data/api_client.dart';
import 'package:app/data/app_store.dart';
import 'package:app/domain/models.dart';
import 'package:app/main.dart';
import 'package:app/ui/admin/worker_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// ───────── Faux serveur (données de TEST uniquement, l'application n'en contient aucune) ─────────

const _supId = 'u-sup';
const _teamId = 'team-1';

Map<String, dynamic> _member(String id, String name, {String status = 'unset', bool self = false}) => {
      'workerId': id,
      'fullName': name,
      'status': status,
      'isSubstitute': false,
      'faceVerified': false,
      'faceEnrolled': true,
      'isSelf': self,
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

class FakeServer {
  final List<String> calls = [];
  String? lastAuth;
  Map<String, dynamic>? savedBody;

  Future<http.Response> handle(http.Request r) async {
    calls.add('${r.method} ${r.url.path}');
    lastAuth = r.headers['Authorization'];
    final path = r.url.path;

    if (path == '/api/auth/login') {
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      if (b['name'] == 'Chef Test' && b['pin'] == '1111') {
        return _json({
          'token': 'jeton-test',
          'user': {'id': _supId, 'name': 'Chef Test', 'role': 'chief', 'workerId': 'w0'},
        });
      }
      return _json({'error': 'Nom ou code incorrect (4 essai(s) restant(s)).', 'code': 'unauthorized'}, 401);
    }
    if (path == '/api/auth/me') {
      return _json({
        'user': {'id': _supId, 'name': 'Chef Test', 'role': 'chief', 'workerId': 'w0'},
        'teams': [
          {'id': _teamId, 'name': 'Équipe Test', 'role': 'titulaire'},
        ],
      });
    }
    if (path == '/api/days' && r.method == 'GET') {
      return _json({
        'teamId': _teamId,
        'date': r.url.queryParameters['date'],
        'saved': false,
        'locked': false,
        'complete': false,
        'bricks': null,
        'members': [
          _member('w0', 'Chef Test', self: true),
          _member('w1', 'Ouvrier Un'),
          _member('w2', 'Ouvrier Deux'),
        ],
        'counts': {'present': 0, 'absent': 0, 'unset': 3},
        // Pas de « calc » : le serveur n'envoie aucun prix à un superviseur.
      });
    }
    if (path == '/api/days' && r.method == 'PUT') {
      savedBody = jsonDecode(r.body) as Map<String, dynamic>;
      final members = (savedBody!['presences'] as List).cast<Map<String, dynamic>>();
      return _json({
        'teamId': _teamId,
        'date': savedBody!['date'],
        'saved': true,
        'locked': false,
        'complete': true,
        'bricks': savedBody!['bricks'],
        'enteredBy': 'Chef Test',
        'members': [
          for (final m in members)
            _member(m['workerId'] as String, m['workerId'] == 'w0' ? 'Chef Test' : 'Ouvrier ${m['workerId']}',
                status: m['status'] as String, self: m['workerId'] == 'w0'),
        ],
        'counts': {'present': 3, 'absent': 0, 'unset': 0},
      });
    }
    return _json({'error': 'Route introuvable.', 'code': 'not_found'}, 404);
  }
}

AppStore _store(FakeServer s) =>
    AppStore(ApiClient(baseUrl: 'http://test.local', client: MockClient(s.handle)));

Future<void> _tapKeys(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.text(d).first);
    await tester.pump();
  }
}

void main() {
  group('Formats', () {
    test('montants exacts : séparateurs, virgule, ≈ pour les valeurs non exactes', () {
      expect(fmtMoney(const Money('17500/1', '17500.00', false)), '17 500 FCFA');
      expect(fmtMoney(const Money('2469/2', '1234.50', false)), '1 234,50 FCFA');
      expect(fmtMoney(const Money('17500/3', '5833.33', true)), '≈ 5 833,33 FCFA');
      expect(fmtMoney(const Money('-650/9', '-72.22', true)), '≈ -72,22 FCFA');
      expect(fmtMoney(const Money('0/1', '0.00', false), unit: false), '0');
    });

    test('dates et mois', () {
      expect(fmtDate('2026-10-17'), '17/10/2026');
      expect(dateKey(DateTime(2026, 3, 5)), '2026-03-05');
      expect(monthKey(2026, 3), '2026-03');
      expect(fmtMonth(2026, 10), 'Octobre 2026');
    });
  });

  group('Modèles', () {
    test('un superviseur ne reçoit pas de calcul : calc est absent', () {
      final day = DayView.fromJson({
        'teamId': 't', 'date': '2026-10-17', 'saved': false, 'locked': false, 'bricks': null,
        'members': [_member('a', 'A')],
      });
      expect(day.calc, isNull);
      expect(day.members.single.status, Presence.unset);
    });

    test('la charge utile de présence ne marque « visage » que pour un présent', () {
      final m = Member.fromJson(_member('a', 'A', status: 'absent'))..faceVerified = true;
      expect(m.toPayload()['faceVerified'], false);
      m.status = Presence.present;
      expect(m.toPayload()['faceVerified'], true);
    });
  });

  group('Client API', () {
    test('envoie le jeton Bearer et lit le JSON', () async {
      final s = FakeServer();
      final api = ApiClient(baseUrl: 'http://test.local', client: MockClient(s.handle))..token = 'abc';
      final j = await api.get('/auth/me') as Map<String, dynamic>;
      expect(s.lastAuth, 'Bearer abc');
      expect(j['user']['name'], 'Chef Test');
    });

    test('message d\'erreur du serveur repris tel quel', () async {
      final api = ApiClient(baseUrl: 'http://test.local', client: MockClient(FakeServer().handle));
      await expectLater(
        api.post('/auth/login', body: {'name': 'x', 'pin': '0'}),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Nom ou code incorrect'))),
      );
    });

    test('serveur injoignable -> message clair', () async {
      final api = ApiClient(baseUrl: 'http://test.local', client: MockClient((_) async => throw Exception('réseau')));
      await expectLater(
          api.get('/teams'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('injoignable'))));
    });

    test('401 avec session ouverte -> déconnexion automatique', () async {
      final expired = ApiClient(
          baseUrl: 'http://test.local', client: MockClient((_) async => _json({'error': 'Session expirée.'}, 401)))
        ..token = 'vieux';
      var called = false;
      expired.onSessionExpired = () => called = true;
      await expectLater(expired.get('/teams'), throwsA(isA<ApiException>()));
      expect(called, isTrue);
    });
  });


  group('Tableau de bord admin', () {
    Map<String, dynamic> overviewJson({List<Map<String, dynamic>> online = const [], bool prices = true}) => {
          'date': '2026-10-17',
          'workers': {'total': 20, 'active': 18, 'withFace': 7, 'supervisors': 3},
          'online': online,
          'onlineWindowMinutes': 5,
          'totals': {'present': 8, 'absent': 2, 'unset': 0, 'teamsWithoutEntry': 1},
          'production': {
            'bricks': 1240,
            'costRate': prices ? 175 : null,
            'saleRate': prices ? 250 : null,
            'cost': {'exact': '217000/1', 'value': '217000.00', 'approx': false},
            'sale': {'exact': '310000/1', 'value': '310000.00', 'approx': false},
            'margin': {'exact': '93000/1', 'value': '93000.00', 'approx': false},
          },
          'teams': [],
        };

    test('lit le nombre d\'ouvriers enregistrés et les prix 175 / 250', () {
      final o = Overview.fromJson(overviewJson());
      expect(o.workersActive, 18);
      expect(o.workersTotal, 20);
      expect(o.workersWithFace, 7);
      expect(o.supervisors, 3);
      expect(o.costRate, 175);
      expect(o.saleRate, 250);
      expect(fmtMoney(o.margin), '93\u202f000 FCFA');
    });

    test('lit les personnes connectées (nom, rôle, équipe, dernière activité)', () {
      final o = Overview.fromJson(overviewJson(online: [
        {'id': 'u1', 'name': 'Admin Test', 'role': 'admin', 'teams': null, 'lastSeenAt': '2026-10-17T10:00:00.000Z', 'isMe': true},
        {'id': 'u2', 'name': 'Paul Sawadogo', 'role': 'chief', 'teams': 'Équipe A', 'lastSeenAt': '2026-10-17T10:01:00.000Z', 'isMe': false},
      ]));
      expect(o.online.length, 2);
      expect(o.online.first.isMe, isTrue);
      expect(o.online.last.role, Role.chief);
      expect(o.online.last.teams, 'Équipe A');
      expect(o.onlineWindowMinutes, 5);
    });

    test('la déconnexion prévient le serveur (avec le jeton) pour retirer la personne des connectés', () async {
      final calls = <String>[];
      String? auth;
      final store = AppStore(ApiClient(
        baseUrl: 'http://test.local',
        client: MockClient((r) async {
          calls.add('${r.method} ${r.url.path}');
          auth = r.headers['Authorization'];
          if (r.url.path == '/api/auth/login') {
            return _json({'token': 'jeton-xyz', 'user': {'id': 'u', 'name': 'A', 'role': 'admin', 'workerId': null}});
          }
          return _json({'ok': true});
        }),
      ));
      await store.login('A', '1234');
      store.logout();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls, contains('POST /api/auth/logout'));
      expect(auth, 'Bearer jeton-xyz');
      expect(store.user, isNull);
      expect(store.api.token, isNull);
    });

    test('une session expirée ne rappelle pas le serveur (pas de boucle)', () async {
      var logoutCalls = 0;
      final store = AppStore(ApiClient(
        baseUrl: 'http://test.local',
        client: MockClient((r) async {
          if (r.url.path == '/api/auth/login') {
            return _json({'token': 't', 'user': {'id': 'u', 'name': 'A', 'role': 'admin', 'workerId': null}});
          }
          if (r.url.path == '/api/auth/logout') logoutCalls++;
          return _json({'error': 'Session expirée.'}, 401);
        }),
      ));
      await store.login('A', '1234');
      await expectLater(store.repo.teams(), throwsA(isA<ApiException>()));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.user, isNull);
      expect(store.notice, contains('expirée'));
      expect(logoutCalls, 0);
    });

    Future<void> showAdminDashboard(WidgetTester tester, Size size, {required bool withPrices}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final json = overviewJson(prices: withPrices, online: [
        {'id': 'u1', 'name': 'Admin Test', 'role': 'admin', 'teams': null,
         'lastSeenAt': DateTime.now().toUtc().toIso8601String(), 'isMe': true},
        {'id': 'u2', 'name': 'Paul Sawadogo', 'role': 'chief', 'teams': 'Équipe A',
         'lastSeenAt': DateTime.now().toUtc().subtract(const Duration(minutes: 3)).toIso8601String(), 'isMe': false},
      ]);
      final store = AppStore(ApiClient(
        baseUrl: 'http://test.local',
        client: MockClient((r) async {
          if (r.url.path == '/api/auth/login') {
            return _json({'token': 't', 'user': {'id': 'u1', 'name': 'Admin Test', 'role': 'admin', 'workerId': null}});
          }
          if (r.url.path == '/api/overview') return _json(json);
          return _json({'error': 'Route introuvable.'}, 404);
        }),
      ));
      await store.login('Admin Test', '1234');
      await tester.pumpWidget(BriquesApp(store: store));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('web (grand écran) : 6 indicateurs, connectés, prix 175 / 250, sans débordement', (tester) async {
      await showAdminDashboard(tester, const Size(1366, 820), withPrices: true);
      expect(tester.takeException(), isNull);
      expect(find.text('18'), findsOneWidget); // ouvriers enregistrés
      expect(find.text('Ouvriers enregistrés · 7 avec visage'), findsOneWidget);
      expect(find.text('Connectés maintenant'), findsOneWidget);
      expect(find.text('Connectés maintenant (2)'), findsOneWidget);
      expect(find.text('Admin Test (vous)'), findsOneWidget);
      expect(find.text('Paul Sawadogo'), findsOneWidget);
      expect(find.textContaining('Superviseur · Équipe A'), findsOneWidget);
      expect(find.textContaining('1\u202f240 × 175 FCFA'), findsOneWidget);
      expect(find.textContaining('1\u202f240 × 250 FCFA'), findsOneWidget);
      expect(find.textContaining('Prix non défini'), findsNothing);
    });

    testWidgets('téléphone : mêmes informations, sans débordement', (tester) async {
      await showAdminDashboard(tester, const Size(390, 844), withPrices: true);
      expect(tester.takeException(), isNull);
      expect(find.text('Ouvriers enregistrés · 7 avec visage'), findsOneWidget);
      expect(find.text('Connectés maintenant'), findsOneWidget);
    });

    testWidgets('prix manquant : avertissement clair au lieu de « × 0 FCFA »', (tester) async {
      await showAdminDashboard(tester, const Size(1366, 820), withPrices: false);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Prix non défini'), findsOneWidget);
      expect(find.text('Confection : prix non défini'), findsOneWidget);
      expect(find.text('Vente : prix non défini'), findsOneWidget);
      expect(find.textContaining('× 0 FCFA'), findsNothing);
    });
  });


  group("Enregistrement d'un ouvrier : contact", () {
    test('lit les coordonnées renvoyées par le serveur (admin)', () {
      final w = WorkerInfo.fromJson({
        'id': 'w1', 'fullName': 'Issa Ouédraogo', 'teamId': 't', 'teamName': 'Équipe A', 'active': true,
        'faceEnrolled': false, 'isSupervisor': false,
        'phone': '+226 70 12 34 56', 'village': 'Koudougou', 'mobileOperator': 'orange', 'mobileNumber': '70 12 34 56',
      });
      expect(w.phone, '+226 70 12 34 56');
      expect(w.village, 'Koudougou');
      expect(w.mobileOperator, 'orange');
      expect(w.mobileNumber, '70 12 34 56');
    });

    test('un superviseur ne reçoit aucune coordonnée : les champs restent vides', () {
      final w = WorkerInfo.fromJson({
        'id': 'w1', 'fullName': 'Issa', 'teamId': 't', 'teamName': 'A', 'active': true,
        'faceEnrolled': false, 'isSupervisor': false,
      });
      expect(w.phone, isNull);
      expect(w.village, isNull);
      expect(w.mobileNumber, isNull);
    });

    test('validation du téléphone', () {
      expect(validatePhone(''), isNull); // facultatif
      expect(validatePhone('+226 70 12 34 56'), isNull);
      expect(validatePhone('70-12-34-56'), isNull);
      expect(validatePhone('abc'), isNotNull);
      expect(validatePhone('12'), isNotNull);
    });

    testWidgets("formulaire d'enregistrement : champs de contact, validation, envoi au serveur", (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Map<String, dynamic>? posted;
      final store = AppStore(ApiClient(
        baseUrl: 'http://test.local',
        client: MockClient((r) async {
          switch ('${r.method} ${r.url.path}') {
            case 'POST /api/auth/login':
              return _json({'token': 't', 'user': {'id': 'u1', 'name': 'Admin Test', 'role': 'admin', 'workerId': null}});
            case 'GET /api/teams':
              return _json([
                {'id': 't1', 'name': 'Équipe A', 'chief': null, 'interim': null, 'members': 1},
              ]);
            case 'GET /api/workers':
              return _json([
                {
                  'id': 'w1', 'fullName': 'Issa Ouédraogo', 'teamId': 't1', 'teamName': 'Équipe A', 'active': true,
                  'faceEnrolled': false, 'isSupervisor': false,
                  'phone': '+226 70 12 34 56', 'village': 'Koudougou', 'mobileOperator': 'orange', 'mobileNumber': '70 12 34 56',
                },
              ]);
            case 'GET /api/supervisors':
              return _json([]);
            case 'POST /api/workers':
              posted = jsonDecode(r.body) as Map<String, dynamic>;
              return _json({'id': 'w2'}, 201);
          }
          return _json({'error': 'Route introuvable.'}, 404);
        }),
      ));
      await store.login('Admin Test', '1234');
      await tester.pumpWidget(BriquesApp(store: store));
      Future<void> settle([int n = 4]) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
      }

      await settle();
      await tester.tap(find.text('Équipes & superviseurs').first);
      await settle();
      await tester.tap(find.text('Équipe A'));
      await settle();

      // les coordonnées de l'ouvrier existant s'affichent dans la liste
      expect(find.textContaining('+226 70 12 34 56'), findsOneWidget);
      expect(find.textContaining('Koudougou'), findsOneWidget);
      expect(find.textContaining('Orange Money 70 12 34 56'), findsOneWidget);

      // ouverture du formulaire
      await tester.tap(find.text('Ajouter un membre'));
      await settle();
      expect(find.text('Enregistrer un ouvrier'), findsOneWidget);
      expect(find.text('CONTACT'), findsOneWidget);
      expect(find.text('Téléphone'), findsOneWidget);
      expect(find.text('Village / quartier'), findsOneWidget);
      expect(find.text('PAIEMENT MOBILE MONEY (FACULTATIF)'), findsOneWidget);

      // le nom est obligatoire
      await tester.tap(find.text('Ajouter'));
      await settle(2);
      expect(find.text('Le nom est obligatoire.'), findsOneWidget);
      expect(posted, isNull);

      // téléphone invalide refusé
      await tester.enterText(find.widgetWithText(TextFormField, 'Nom complet *'), 'Nouvel Ouvrier');
      await tester.enterText(find.widgetWithText(TextFormField, 'Téléphone'), 'abc');
      await tester.tap(find.text('Ajouter'));
      await settle(2);
      expect(find.textContaining('Numéro invalide'), findsOneWidget);
      expect(posted, isNull);

      // numéro valide + village + mobile money
      await tester.enterText(find.widgetWithText(TextFormField, 'Téléphone'), '+226 70 11 22 33');
      await tester.enterText(find.widgetWithText(TextFormField, 'Village / quartier'), 'Ouagadougou');
      await tester.tap(find.text('Aucun'));
      await settle(2);
      await tester.tap(find.text('Moov Money').last);
      await settle(2);

      // un opérateur choisi => le numéro de réception devient obligatoire
      await tester.tap(find.text('Ajouter'));
      await settle(2);
      expect(find.text('Indiquez le numéro de réception.'), findsOneWidget);
      expect(posted, isNull);

      await tester.tap(find.text('Même numéro que le téléphone'));
      await settle(2);
      await tester.tap(find.text('Ajouter'));
      await settle();

      expect(posted, isNotNull);
      expect(posted!['fullName'], 'Nouvel Ouvrier');
      expect(posted!['teamId'], 't1');
      expect(posted!['phone'], '+226 70 11 22 33');
      expect(posted!['village'], 'Ouagadougou');
      expect(posted!['mobileOperator'], 'moov');
      expect(posted!['mobileNumber'], '+226 70 11 22 33');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('connexion superviseur : liste des autres membres, un seul champ de briques, aucun prix', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final server = FakeServer();
    await tester.pumpWidget(BriquesApp(store: _store(server)));
    await tester.pump(const Duration(milliseconds: 300));

    // écran de connexion, sans aucune indication de compte de démonstration
    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.textContaining('Démo'), findsNothing);

    // mauvais code : message du serveur affiché
    await tester.enterText(find.byType(TextField), 'Chef Test');
    await _tapKeys(tester, '9999');
    await tester.tap(find.text('Se connecter'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Nom ou code incorrect'), findsOneWidget);

    // bon code
    await _tapKeys(tester, '1111');
    await tester.tap(find.text('Se connecter'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Chef Test'), findsWidgets); // titre de la barre
    expect(find.text('Ouvrier Un'), findsOneWidget);
    expect(find.text('Ouvrier Deux'), findsOneWidget);
    expect(find.textContaining('Membres de l\'équipe (2)'), findsOneWidget); // lui-même n'est pas dans la liste
    expect(find.text('Nombre de briques confectionnées'), findsOneWidget);

    // aucun prix ni montant côté superviseur
    expect(find.textContaining('FCFA'), findsNothing);
    expect(find.textContaining('Marge'), findsNothing);
    expect(find.textContaining('Part par présent'), findsNothing);

    // saisie : briques + présences, puis enregistrement
    await tester.enterText(find.widgetWithText(TextField, 'Nombre de briques confectionnées'), '120');
    await tester.pump();
    await tester.tap(find.text('Non saisis : présents'));
    await tester.pump();
    await tester.tap(find.text('Enregistrer la journée'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(server.savedBody, isNotNull);
    expect(server.savedBody!['bricks'], 120);
    final presences = (server.savedBody!['presences'] as List).cast<Map<String, dynamic>>();
    expect(presences.length, 3);
    expect(presences.every((p) => p['status'] == 'present'), isTrue,
        reason: 'le superviseur connecté est présent d\'office');
    expect(server.calls, contains('GET /api/auth/me'));
  });
}
