import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';

/// Stockage local clé → JSON (SharedPreferences). Toute lecture est tolérante : une donnée
/// illisible est ignorée plutôt que de faire planter l'application.
class LocalStore {
  LocalStore(this._p);
  final SharedPreferences _p;

  static Future<LocalStore> open() async => LocalStore(await SharedPreferences.getInstance());

  Object? read(String key) {
    try {
      final s = _p.getString(key);
      return s == null ? null : jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, Object? value) async {
    try {
      await _p.setString(key, jsonEncode(value));
    } catch (_) {/* stockage plein ou indisponible : l'appli continue en ligne */}
  }

  Future<void> remove(String key) => _p.remove(key);
}

String newRequestId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Identifiants conservés après une connexion réussie pour pouvoir se reconnecter sans réseau.
/// Seule une empreinte salée du code PIN est gardée, jamais le code lui-même.
class OfflineCredentials {
  static String _key(String name) => 'cred:${name.trim().toLowerCase()}';

  static String _hash(String salt, String name, String pin) {
    List<int> d = utf8.encode('$salt|${name.trim().toLowerCase()}|$pin');
    for (var i = 0; i < 20000; i++) {
      d = sha256.convert(d).bytes;
    }
    return base64.encode(d);
  }

  static Future<void> save(LocalStore s, String name, String pin, AppUser user, String token) {
    final salt = newRequestId();
    return s.write(_key(name), {
      'salt': salt,
      'hash': _hash(salt, name, pin),
      'user': {'id': user.id, 'name': user.name, 'role': user.role.name, 'workerId': user.workerId},
      'token': token,
    });
  }

  /// null = aucun identifiant connu sur cet appareil ; sinon `ok` indique si le PIN correspond.
  static ({bool ok, AppUser user, String token})? check(LocalStore s, String name, String pin) {
    final j = s.read(_key(name));
    if (j is! Map) return null;
    try {
      final user = AppUser.fromJson((j['user'] as Map).cast<String, dynamic>());
      final ok = _hash(j['salt'] as String, name, pin) == j['hash'];
      return (ok: ok, user: user, token: j['token'] as String);
    } catch (_) {
      return null;
    }
  }
}

enum SaveState { pending, conflict, rejected }

/// Saisie de journée enregistrée sur l'appareil, en attente d'envoi au serveur.
class PendingSave {
  final String requestId;
  final String teamId;
  final String teamName;
  final String date;
  final Json body; // teamId, date, bricks, presences
  final String? baseVersion;
  final Json day; // copie locale de la journée, affichée tant que la saisie n'est pas synchronisée
  SaveState state;
  String? message;

  PendingSave({
    required this.requestId,
    required this.teamId,
    required this.teamName,
    required this.date,
    required this.body,
    required this.baseVersion,
    required this.day,
    this.state = SaveState.pending,
    this.message,
  });

  bool sameDay(String team, String d) => teamId == team && date == d;

  Json toJson() => {
        'requestId': requestId,
        'teamId': teamId,
        'teamName': teamName,
        'date': date,
        'body': body,
        'baseVersion': baseVersion,
        'day': day,
        'state': state.name,
        'message': message,
      };

  factory PendingSave.fromJson(Json j) => PendingSave(
        requestId: j['requestId'] as String,
        teamId: j['teamId'] as String,
        teamName: j['teamName'] as String? ?? '',
        date: j['date'] as String,
        body: (j['body'] as Map).cast<String, dynamic>(),
        baseVersion: j['baseVersion'] as String?,
        day: (j['day'] as Map).cast<String, dynamic>(),
        state: SaveState.values.firstWhere((s) => s.name == j['state'], orElse: () => SaveState.pending),
        message: j['message'] as String?,
      );
}
