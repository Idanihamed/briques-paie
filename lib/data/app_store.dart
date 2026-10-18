import 'dart:async';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../domain/models.dart';
import 'api_client.dart';
import 'offline.dart';
import 'repository.dart';

/// Résultat d'un enregistrement de journée.
class SaveOutcome {
  final DayView day;

  /// Vrai si la saisie est gardée sur l'appareil en attendant le réseau (ou un arbitrage).
  final bool queued;
  final PendingSave? pending;
  const SaveOutcome(this.day, {this.queued = false, this.pending});

  bool get conflict => pending?.state == SaveState.conflict;
}

/// Session de l'utilisateur connecté + synchronisation hors ligne du superviseur.
///
/// Les données métier du serveur restent la source de vérité. Pour un superviseur uniquement
/// (jamais d'argent côté appareil), les dernières données lues sont gardées localement et les
/// saisies faites sans réseau attendent dans une file, envoyées dès que le serveur répond.
class AppStore extends ChangeNotifier {
  AppStore(this.api, {this.local}) : repo = Repository(api) {
    api.onSessionExpired = () => logout(message: 'Session expirée. Reconnectez-vous.', notifyServer: false);
    api.onReachability = _reachability;
    repo.pendingDay = (team, date) => queue.where((p) => p.sameDay(team, date)).firstOrNull?.day;
  }

  final ApiClient api;
  final Repository repo;
  final LocalStore? local;

  AppUser? user;

  /// Message affiché sur l'écran de connexion après une déconnexion forcée.
  String? notice;

  bool get isAdmin => user?.role == Role.admin;

  // ───── Adresse du serveur (réglable sur l'appareil) ─────
  static const _serverKey = 'server_url';

  String get serverUrl => api.baseUrl;

  /// Reprend l'adresse enregistrée sur l'appareil, s'il y en a une.
  void loadSavedServerUrl() {
    final saved = local?.read(_serverKey);
    if (saved is String && saved.isNotEmpty) api.baseUrl = saved;
  }

  /// « 192.168.1.132:3000 » → « http://192.168.1.132:3000 ». Null si l'adresse est inutilisable.
  static String? normalizeServerUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'http://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    final u = Uri.tryParse(s);
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) return null;
    return s;
  }

  Future<void> setServerUrl(String url) async {
    api.baseUrl = url;
    await local?.write(_serverKey, url);
    notifyListeners();
  }
  bool get _offlineCapable => local != null && user?.role == Role.chief;

  // ───── Hors ligne ─────
  bool online = true;
  bool syncing = false;
  List<PendingSave> queue = [];
  Timer? _timer;

  int get pendingCount => queue.where((p) => p.state == SaveState.pending).length;
  List<PendingSave> get needsAttention => queue.where((p) => p.state != SaveState.pending).toList();

  void _reachability(bool v) {
    if (v == online) return;
    online = v;
    notifyListeners();
    if (v && pendingCount > 0) unawaited(sync());
  }

  String get _queueKey => 'queue:${user!.id}';

  void _loadQueue() {
    queue = [];
    final raw = local?.read(_queueKey);
    if (raw is List) {
      for (final e in raw) {
        try {
          queue.add(PendingSave.fromJson((e as Map).cast<String, dynamic>()));
        } catch (_) {/* entrée illisible : ignorée */}
      }
    }
  }

  Future<void> _persistQueue() async {
    if (local != null && user != null) await local!.write(_queueKey, queue.map((p) => p.toJson()).toList());
  }

  // ───── Connexion ─────
  Future<void> login(String name, String pin) async {
    try {
      final r = await repo.login(name.trim(), pin);
      api.token = r.token;
      user = r.user;
      if (_offlineCapable) await OfflineCredentials.save(local!, name, pin, r.user, r.token);
    } on ApiException catch (e) {
      final l = local;
      if (!e.offline || l == null) rethrow;
      // Pas de réseau : un superviseur déjà connecté une fois sur cet appareil peut rentrer avec son code.
      final c = OfflineCredentials.check(l, name, pin);
      if (c == null) rethrow;
      if (!c.ok) throw const ApiException('Nom ou code incorrect.');
      api.token = c.token;
      user = c.user;
    }
    notice = null;
    _startSession();
    notifyListeners();
  }

  void _startSession() {
    repo.local = local;
    repo.cacheScope = _offlineCapable ? user!.id : null;
    _timer?.cancel();
    if (!_offlineCapable) return;
    _loadQueue();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    unawaited(_syncThenPrefetch());
  }

  Future<void> _syncThenPrefetch() async {
    await sync();
    await prefetch();
  }

  Future<void> _tick() async {
    if (user == null) return;
    if (!online) {
      // Sonde légère : une réponse (même 401) rétablit l'état « en ligne ».
      try {
        await api.get('/auth/me');
      } catch (_) {}
    }
    if (pendingCount > 0) await sync();
  }

  /// Télécharge ce qu'il faut pour travailler sans réseau : équipes, journée du jour, calendrier du mois.
  Future<void> prefetch() async {
    if (!_offlineCapable) return;
    try {
      final teams = await repo.myTeams();
      final now = DateTime.now();
      for (final t in teams) {
        await repo.day(t.id, dateKey(now));
      }
      await repo.calendar(now.year, now.month);
    } catch (_) {/* au mieux : sans réseau, on garde la copie précédente */}
  }

  void logout({String? message, bool notifyServer = true}) {
    if (user == null) return;
    // Au mieux : la requête part avec le jeton actuel, avant qu'il soit effacé.
    if (notifyServer) repo.logout().catchError((Object _) {});
    _timer?.cancel();
    // La file d'attente reste sur l'appareil (clé par utilisateur) et sera envoyée à la prochaine connexion.
    api.token = null;
    user = null;
    queue = [];
    repo.cacheScope = null;
    notice = message;
    notifyListeners();
  }

  // ───── Saisie de journée ─────

  /// Enregistre une journée. Superviseur : si le serveur est injoignable, la saisie est gardée
  /// sur l'appareil et synchronisée plus tard (sans doublon grâce à `requestId`).
  Future<SaveOutcome> saveDay({
    required DayView current,
    required String teamName,
    required int? bricks,
    required List<Member> members,
  }) async {
    final body = Repository.dayBody(teamId: current.teamId, date: current.date, bricks: bricks, members: members);
    if (!_offlineCapable) return SaveOutcome(await repo.saveDay(body));

    final existing = queue.where((p) => p.sameDay(current.teamId, current.date)).firstOrNull;
    // Plusieurs modifications hors ligne d'un même jour : la version de départ reste la première.
    final base = existing != null && existing.state == SaveState.pending ? existing.baseVersion : current.version;
    final requestId = newRequestId();
    body['baseVersion'] = base;
    body['requestId'] = requestId;

    PendingSave item(SaveState state, String? message) => PendingSave(
          requestId: requestId,
          teamId: current.teamId,
          teamName: teamName,
          date: current.date,
          body: body,
          baseVersion: base,
          state: state,
          message: message,
          day: DayView(
            teamId: current.teamId,
            date: current.date,
            saved: true,
            locked: false,
            version: base,
            workingDay: current.workingDay,
            bricks: bricks,
            members: members,
            enteredBy: user?.name,
          ).toJson(),
        );

    Future<SaveOutcome> keep(SaveState state, String? message) async {
      final p = item(state, message);
      queue
        ..removeWhere((x) => x.sameDay(current.teamId, current.date))
        ..add(p);
      await _persistQueue();
      await repo.cacheDay(p.day);
      notifyListeners();
      return SaveOutcome(DayView.fromJson(p.day), queued: true, pending: p);
    }

    try {
      final day = await repo.saveDay(body);
      if (existing != null) {
        queue.remove(existing);
        await _persistQueue();
        notifyListeners();
      }
      return SaveOutcome(day);
    } on ApiException catch (e) {
      if (e.offline || (e.status ?? 0) >= 500) return keep(SaveState.pending, null);
      if (e.code == 'stale') return keep(SaveState.conflict, e.message);
      rethrow;
    }
  }

  /// Envoie les saisies en attente. Réseau coupé ou erreur serveur : on garde et on réessaiera.
  /// Refus définitif (jour verrouillé, jour non travaillé…) : la saisie est mise de côté avec le motif.
  Future<void> sync() async {
    if (syncing || !_offlineCapable) return;
    syncing = true;
    notifyListeners();
    try {
      for (final p in queue.where((p) => p.state == SaveState.pending).toList()) {
        try {
          final body = {...p.body, 'baseVersion': p.baseVersion, 'requestId': p.requestId};
          await repo.saveDay(body);
          queue.remove(p);
        } on ApiException catch (e) {
          if (e.offline || e.isUnauthorized || (e.status ?? 0) >= 500) break;
          p.state = e.code == 'stale' ? SaveState.conflict : SaveState.rejected;
          p.message = e.message;
        }
        await _persistQueue();
      }
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// Conflit : l'utilisateur garde sa saisie, qui remplace la version du serveur.
  Future<void> keepMine(PendingSave p) async {
    p.body['force'] = true;
    p.state = SaveState.pending;
    p.message = null;
    await _persistQueue();
    notifyListeners();
    await sync();
  }

  /// Conflit ou refus : on abandonne la saisie locale et on reprend la version du serveur.
  Future<void> keepServer(PendingSave p) async {
    queue.remove(p);
    await _persistQueue();
    notifyListeners();
    try {
      await repo.day(p.teamId, p.date); // rafraîchit la copie locale
    } catch (_) {}
    notifyListeners();
  }
}

class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child}) : super(notifier: store);

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
