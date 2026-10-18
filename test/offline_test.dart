import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/data/api_client.dart';
import 'package:app/data/app_store.dart';
import 'package:app/data/offline.dart';
import 'package:app/domain/models.dart';

const _team = '11111111-1111-4111-8111-111111111111';
const _w1 = '22222222-2222-4222-8222-222222222222';
const _date = '2026-03-10';

Map<String, dynamic> _day({String? version, int? bricks, String status = 'unset'}) => {
      'teamId': _team,
      'date': _date,
      'saved': version != null,
      'locked': false,
      'version': version,
      'workingDay': {'working': true, 'kind': 'work', 'reason': null, 'source': 'default'},
      'bricks': bricks,
      'enteredBy': null,
      'members': [
        {
          'workerId': _w1,
          'fullName': 'Awa Traore',
          'status': status,
          'faceVerified': false,
          'isSubstitute': false,
          'faceEnrolled': false,
          'isSelf': false,
          'absenceReason': null,
        },
      ],
    };

class _Server {
  bool up = true;
  String? serverVersion; // version actuelle de la journée côté serveur
  Map<String, dynamic>? failWith; // {status, code, error} pour forcer un refus sur PUT /days
  final puts = <Map<String, dynamic>>[];

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  Future<http.Response> handle(http.Request r) async {
    if (!up) throw http.ClientException('offline');
    final path = r.url.path;
    if (path == '/api/auth/login') {
      final b = jsonDecode(r.body) as Map;
      if (b['pin'] != '1234') return _json({'error': 'Nom ou code incorrect.'}, 401);
      return _json({
        'token': 'tok',
        'user': {'id': 'u1', 'name': 'Moussa', 'role': 'chief', 'workerId': null},
      });
    }
    if (path == '/api/auth/me') {
      return _json({
        'teams': [
          {'id': _team, 'name': 'Equipe A', 'role': 'titulaire'},
        ],
      });
    }
    if (path == '/api/days' && r.method == 'GET') return _json(_day(version: serverVersion));
    if (path == '/api/days' && r.method == 'PUT') {
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      puts.add(b);
      if (failWith != null) {
        return _json({'error': failWith!['error'], 'code': failWith!['code']}, failWith!['status'] as int);
      }
      serverVersion = '2026-03-10T10:00:0${puts.length}.000000Z';
      return _json(_day(version: serverVersion, bricks: b['bricks'] as int?, status: 'present'));
    }
    if (path == '/api/calendar') return _json({'month': '2026-03', 'today': _date, 'restWeekdays': [0], 'teams': [], 'days': []});
    return _json({'error': 'inconnu'}, 404);
  }
}

Future<(AppStore, _Server)> _chief() async {
  SharedPreferences.setMockInitialValues({});
  final server = _Server();
  final local = await LocalStore.open();
  final store = AppStore(ApiClient(baseUrl: 'http://x', client: MockClient(server.handle)), local: local);
  await store.login('Moussa', '1234');
  return (store, server);
}

void main() {
  serverUrlTests();
  test('saisie hors ligne : gardée sur l\'appareil puis envoyée une seule fois au retour du réseau', () async {
    final (store, server) = await _chief();
    final current = await store.repo.day(_team, _date);
    final members = current.members..first.status = Presence.present;

    server.up = false;
    final out = await store.saveDay(current: current, teamName: 'Equipe A', bricks: 900, members: members);
    expect(out.queued, isTrue);
    expect(store.pendingCount, 1);
    expect(store.online, isFalse);

    // La journée relue hors ligne montre la saisie locale.
    final again = await store.repo.day(_team, _date);
    expect(again.bricks, 900);
    expect(again.members.first.status, Presence.present);

    server.up = true;
    await store.sync();
    expect(store.pendingCount, 0);
    expect(server.puts.length, 1);
    expect(server.puts.single['requestId'], isNotNull);
    expect(server.puts.single['baseVersion'], isNull);
    expect(server.puts.single.containsKey('baseVersion'), isTrue);

    // Rien à renvoyer ensuite.
    await store.sync();
    expect(server.puts.length, 1);
  });

  test('connexion sans réseau avec le code déjà utilisé ; mauvais code refusé', () async {
    final (store, server) = await _chief();
    store.logout(notifyServer: false);
    server.up = false;

    await expectLater(store.login('Moussa', '9999'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('incorrect'))));
    expect(store.user, isNull);

    await store.login('moussa', '1234');
    expect(store.user!.name, 'Moussa');
  });

  test('connexion sans réseau impossible pour un appareil inconnu', () async {
    SharedPreferences.setMockInitialValues({});
    final server = _Server()..up = false;
    final store = AppStore(ApiClient(baseUrl: 'http://x', client: MockClient(server.handle)), local: await LocalStore.open());
    await expectLater(store.login('Moussa', '1234'), throwsA(isA<ApiException>().having((e) => e.offline, 'offline', isTrue)));
  });

  test('conflit : la saisie est mise de côté puis renvoyée avec « force » si on la garde', () async {
    final (store, server) = await _chief();
    server.serverVersion = 'v1';
    final current = await store.repo.day(_team, _date);
    final members = current.members..first.status = Presence.present;

    server.failWith = {'status': 409, 'code': 'stale', 'error': 'Cette journée a été modifiée par quelqu\'un d\'autre.'};
    final out = await store.saveDay(current: current, teamName: 'Equipe A', bricks: 500, members: members);
    expect(out.conflict, isTrue);
    expect(store.pendingCount, 0);
    expect(store.needsAttention.single.state, SaveState.conflict);

    server.failWith = null;
    await store.keepMine(store.needsAttention.single);
    expect(store.queue, isEmpty);
    expect(server.puts.last['force'], isTrue);
  });

  test('refus définitif (jour verrouillé) : saisie écartée avec le motif, jamais renvoyée en boucle', () async {
    final (store, server) = await _chief();
    final current = await store.repo.day(_team, _date);
    server.up = false;
    await store.saveDay(current: current, teamName: 'Equipe A', bricks: 100, members: current.members);
    server.up = true;
    server.failWith = {'status': 409, 'code': 'locked', 'error': 'La paie de 2026-03 est verrouillée.'};

    await store.sync();
    final p = store.needsAttention.single;
    expect(p.state, SaveState.rejected);
    expect(p.message, contains('verrouillée'));
    final sent = server.puts.length;
    await store.sync();
    expect(server.puts.length, sent);

    await store.keepServer(p);
    expect(store.queue, isEmpty);
  });

  test('la file survit à une déconnexion et part à la connexion suivante', () async {
    final (store, server) = await _chief();
    final current = await store.repo.day(_team, _date);
    server.up = false;
    await store.saveDay(current: current, teamName: 'Equipe A', bricks: 300, members: current.members);
    store.logout(notifyServer: false);
    expect(store.queue, isEmpty); // vidée en mémoire seulement

    server.up = true;
    await store.login('Moussa', '1234');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(server.puts.length, 1);
    expect(store.pendingCount, 0);
  });
}

void serverUrlTests() {
  test('adresse du serveur : normalisation et mémorisation sur l\'appareil', () async {
    expect(AppStore.normalizeServerUrl('192.168.1.132:3000'), 'http://192.168.1.132:3000');
    expect(AppStore.normalizeServerUrl(' https://api.exemple.com/ '), 'https://api.exemple.com');
    expect(AppStore.normalizeServerUrl(''), isNull);
    expect(AppStore.normalizeServerUrl('ftp://x'), isNull);

    SharedPreferences.setMockInitialValues({});
    final local = await LocalStore.open();
    final a = AppStore(ApiClient(baseUrl: 'http://ancienne:3000'), local: local);
    await a.setServerUrl('http://192.168.1.132:3000');
    expect(a.serverUrl, 'http://192.168.1.132:3000');

    // Au prochain lancement, l'adresse enregistrée remplace celle de l'application.
    final b = AppStore(ApiClient(baseUrl: 'http://ancienne:3000'), local: local)..loadSavedServerUrl();
    expect(b.serverUrl, 'http://192.168.1.132:3000');
  });
}
