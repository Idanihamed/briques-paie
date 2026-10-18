import '../core/format.dart';
import '../domain/models.dart';
import 'api_client.dart';
import 'offline.dart';

/// Une méthode par route de l'API, avec des types. Aucune règle métier ici :
/// droits, verrouillage et calculs sont appliqués par le serveur et la base.
class Repository {
  Repository(this.api);
  final ApiClient api;

  // ───── Copie locale (superviseur uniquement : jamais de montants hors du serveur) ─────
  LocalStore? local;
  String? cacheScope; // identifiant de l'utilisateur dont on garde les données
  bool get cacheEnabled => local != null && cacheScope != null;

  /// Saisie en attente de synchronisation pour (équipe, date) : prioritaire sur ce que dit le serveur.
  Json? Function(String teamId, String date)? pendingDay;

  String _ck(String kind) => 'cache:$cacheScope:$kind';

  /// Lecture « réseau d'abord » : si le serveur est injoignable, la dernière copie connue est utilisée.
  Future<T> _cached<T>(String kind, Future<dynamic> Function() fetch, T Function(Json) parse) async {
    try {
      final raw = await fetch();
      if (cacheEnabled) await local!.write(_ck(kind), raw);
      return parse(raw as Json);
    } on ApiException catch (e) {
      if (e.offline && cacheEnabled) {
        final raw = local!.read(_ck(kind));
        if (raw is Map) return parse(raw.cast<String, dynamic>());
      }
      rethrow;
    }
  }

  /// Mémorise une journée (réponse du serveur ou copie locale) pour la relire hors ligne.
  Future<void> cacheDay(Json day) async {
    if (cacheEnabled) await local!.write(_ck('day:${day['teamId']}:${day['date']}'), day);
  }

  List<Json> _list(dynamic o) => (o as List).cast<Json>();

  // ───── Session ─────
  Future<({String token, AppUser user})> login(String name, String pin) async {
    final j = await api.post('/auth/login', body: {'name': name, 'pin': pin}) as Json;
    return (token: j['token'] as String, user: AppUser.fromJson(j['user'] as Json));
  }

  /// Signale la déconnexion : l'admin ne voit plus la personne comme « connectée ».
  Future<void> logout() => api.post('/auth/logout');

  Future<List<MyTeam>> myTeams() => _cached('me', () => api.get('/auth/me'), (j) => _list(j['teams']).map(MyTeam.fromJson).toList());

  // ───── Équipes, ouvriers, superviseurs ─────
  Future<List<TeamInfo>> teams() async => _list(await api.get('/teams')).map(TeamInfo.fromJson).toList();
  Future<void> createTeam(String name) => api.post('/teams', body: {'name': name});
  Future<void> setChief(String teamId, String? userId) => api.put('/teams/$teamId/chief', body: {'userId': userId});
  Future<void> setInterim(String teamId, String? userId) => api.put('/teams/$teamId/interim', body: {'userId': userId});

  Future<List<WorkerInfo>> workers() async => _list(await api.get('/workers')).map(WorkerInfo.fromJson).toList();
  /// Enregistre un ouvrier avec ses coordonnées (toutes facultatives sauf le nom).
  Future<void> addWorker({
    required String fullName,
    required String teamId,
    String? phone,
    String? village,
    String? mobileOperator,
    String? mobileNumber,
  }) =>
      api.post('/workers', body: {
        'fullName': fullName,
        'teamId': teamId,
        'phone': ?phone,
        'village': ?village,
        'mobileOperator': ?mobileOperator,
        'mobileNumber': ?mobileNumber,
      });

  /// Met à jour nom et coordonnées. Une valeur `null` EFFACE le champ côté serveur.
  Future<void> updateContact(
    String id, {
    required String fullName,
    String? phone,
    String? village,
    String? mobileOperator,
    String? mobileNumber,
  }) =>
      api.patch('/workers/$id', body: {
        'fullName': fullName,
        'phone': phone,
        'village': village,
        'mobileOperator': mobileOperator,
        'mobileNumber': mobileNumber,
      });

  Future<void> updateWorker(String id, {String? teamId, bool? active}) =>
      api.patch('/workers/$id', body: {'teamId': ?teamId, 'active': ?active});

  Future<List<SupervisorInfo>> supervisors() async =>
      _list(await api.get('/supervisors')).map(SupervisorInfo.fromJson).toList();
  Future<void> createSupervisor(String workerId, String pin) =>
      api.post('/supervisors', body: {'workerId': workerId, 'pin': pin});
  Future<void> resetSupervisorPin(String id, String pin) => api.put('/supervisors/$id/pin', body: {'pin': pin});

  // ───── Visage ─────
  /// `images` : 1 à 5 photos JPEG (base64) du même visage. Le serveur calcule et chiffre la signature.
  Future<void> enrollFace(String workerId, List<String> images) =>
      api.put('/workers/$workerId/face', body: {'images': images}, timeout: const Duration(seconds: 90));
  Future<void> deleteFace(String workerId) => api.delete('/workers/$workerId/face');
  Future<FaceResult> verifyFace(String workerId, String image) async => FaceResult.fromJson(
      await api.post('/faces/verify', body: {'workerId': workerId, 'image': image}, timeout: const Duration(seconds: 60)) as Json);

  // ───── Journées ─────
  Future<DayView> day(String teamId, String date) async {
    final pending = pendingDay?.call(teamId, date);
    if (pending != null) return DayView.fromJson(pending);
    return _cached('day:$teamId:$date', () => api.get('/days', query: {'teamId': teamId, 'date': date}), DayView.fromJson);
  }

  /// Corps d'une saisie de journée. Les clés de synchronisation ne sont envoyées que si elles sont fournies.
  static Json dayBody({
    required String teamId,
    required String date,
    required int? bricks,
    required List<Member> members,
  }) =>
      {
        'teamId': teamId,
        'date': date,
        'bricks': bricks,
        'presences': members.map((m) => m.toPayload()).toList(),
      };

  Future<DayView> saveDay(Json body) async {
    final day = await api.put('/days', body: body) as Json;
    await cacheDay(day);
    return DayView.fromJson(day);
  }

  Future<List<SubstituteCandidate>> substitutes(String teamId, String date) async {
    final key = _ck('subs:$teamId:$date');
    try {
      final raw = await api.get('/days/substitutes', query: {'teamId': teamId, 'date': date});
      if (cacheEnabled) await local!.write(key, raw);
      return _list(raw).map(SubstituteCandidate.fromJson).toList();
    } on ApiException catch (e) {
      final raw = cacheEnabled && e.offline ? local!.read(key) : null;
      if (raw is List) return _list(raw).map(SubstituteCandidate.fromJson).toList();
      rethrow;
    }
  }

  Future<Stats> stats(int year, int month) async =>
      Stats.fromJson(await api.get('/stats', query: {'month': monthKey(year, month)}) as Json);

  // ───── Calendrier de travail ─────
  Future<CalendarMonth> calendar(int year, int month, {String? teamId}) => _cached(
      'cal:${monthKey(year, month)}:${teamId ?? ''}',
      () => api.get('/calendar', query: {'month': monthKey(year, month), 'teamId': ?teamId}),
      CalendarMonth.fromJson);

  Future<void> setRestWeekdays(List<int> days) => api.put('/calendar/settings', body: {'restWeekdays': days});

  /// Déclare une période (non travaillée, ou travaillée à titre exceptionnel si `kind` = 'work').
  Future<void> markDays({
    required DateTime from,
    DateTime? to,
    String? teamId,
    required String kind,
    String? reason,
  }) =>
      api.post('/calendar/days', body: {
        'from': dateKey(from),
        'to': dateKey(to ?? from),
        'teamId': teamId,
        'kind': kind,
        'reason': reason,
      });

  Future<void> clearDays({required DateTime from, DateTime? to, String? teamId}) =>
      api.post('/calendar/days/clear', body: {'from': dateKey(from), 'to': dateKey(to ?? from), 'teamId': teamId});

  Future<WorkerSheet> workerSheet(String workerId, int year, int month) async =>
      WorkerSheet.fromJson(await api.get('/workers/$workerId/sheet', query: {'month': monthKey(year, month)}) as Json);

  // ───── Admin ─────
  Future<Overview> overview(DateTime date) async =>
      Overview.fromJson(await api.get('/overview', query: {'date': dateKey(date)}) as Json);

  Future<List<PriceGroup>> tariffs() async => _list(await api.get('/tariffs')).map(PriceGroup.fromJson).toList();
  Future<void> addTariff({required PriceKind kind, required int value, required DateTime effectiveDate, required String reason}) =>
      api.post('/tariffs', body: {'kind': kind.name, 'value': value, 'effectiveDate': dateKey(effectiveDate), 'reason': reason});

  Future<PayrollView> payroll(int year, int month) async =>
      PayrollView.fromJson(await api.get('/payroll/${monthKey(year, month)}') as Json);
  Future<void> validatePayroll(int year, int month) => api.post('/payroll/${monthKey(year, month)}/validate');
  Future<void> unlockPayroll(int year, int month, String reason) =>
      api.post('/payroll/${monthKey(year, month)}/unlock', body: {'reason': reason});
  Future<String> payrollCsv(int year, int month) => api.getText('/payroll/${monthKey(year, month)}/csv');

  Future<PaymentsView> payments(int year, int month) async =>
      PaymentsView.fromJson(await api.get('/payments', query: {'month': monthKey(year, month)}) as Json);
  Future<List<AdvanceItem>> advances(int year, int month) async =>
      _list((await api.get('/payments/advances', query: {'month': monthKey(year, month)}) as Json)['advances']).map(AdvanceItem.fromJson).toList();
  Future<void> addAdvance({required String workerId, required int year, required int month, required int amount, required bool cash, String? note}) =>
      api.post('/payments/advances', body: {
        'workerId': workerId,
        'month': monthKey(year, month),
        'amount': amount,
        'mode': cash ? 'cash' : 'mobile_money',
        'note': ?note,
      });
  Future<void> deleteAdvance(String id) => api.delete('/payments/advances/$id');

  Future<PeriodReport> period(DateTime from, DateTime to) async =>
      PeriodReport.fromJson(await api.get('/reports/period', query: {'from': dateKey(from), 'to': dateKey(to)}) as Json);

  Future<ImportResult> importWorkers(String text, {required bool dryRun}) async =>
      ImportResult.fromJson(await api.post('/workers/import', body: {'text': text, 'dryRun': dryRun}, timeout: const Duration(seconds: 60)) as Json);

  Future<String> backupJson() => api.getText('/backup');

  // ───── Factures ─────
  Future<Letterhead> letterhead() async => Letterhead.fromJson(await api.get('/invoices/letterhead') as Json);
  Future<void> saveLetterhead(Letterhead l) => api.put('/invoices/letterhead', body: l.toJson());

  Future<List<ClientInfo>> clients() async => _list(await api.get('/invoices/clients')).map(ClientInfo.fromJson).toList();
  Future<void> addClient(Map<String, String?> f) => api.post('/invoices/clients', body: f);
  Future<void> updateClient(String id, Map<String, Object?> f) => api.patch('/invoices/clients/$id', body: f);

  Future<InvoiceDraft> invoiceDraft(DateTime from, DateTime to) async =>
      InvoiceDraft.fromJson(await api.get('/invoices/draft', query: {'from': dateKey(from), 'to': dateKey(to)}) as Json);
  Future<List<InvoiceSummary>> invoices() async => _list(await api.get('/invoices')).map(InvoiceSummary.fromJson).toList();
  Future<Invoice> invoice(String id) async => Invoice.fromJson(await api.get('/invoices/$id') as Json);

  Future<({String id, String number, int totalAmount})> createInvoice({
    required String clientId,
    required DateTime issuedOn,
    required String subject,
    DateTime? from,
    DateTime? to,
    required int unitPrice,
    required List<InvoiceLine> lines,
  }) async {
    final j = await api.post('/invoices', body: {
      'clientId': clientId,
      'issuedOn': dateKey(issuedOn),
      'subject': subject,
      'periodFrom': from == null ? null : dateKey(from),
      'periodTo': to == null ? null : dateKey(to),
      'unitPrice': unitPrice,
      'lines': lines.map((l) => l.toJson()).toList(),
    }) as Json;
    return (id: j['id'] as String, number: j['number'] as String, totalAmount: j['totalAmount'] as int);
  }

  Future<void> cancelInvoice(String id, String reason) => api.post('/invoices/$id/cancel', body: {'reason': reason});

  Future<AlertsView> alerts() async => AlertsView.fromJson(await api.get('/alerts') as Json);

  Future<void> pay({required String workerId, required int year, required int month, required int paid, required bool cash}) =>
      api.post('/payments', body: {
        'workerId': workerId,
        'month': monthKey(year, month),
        'paid': paid,
        'mode': cash ? 'cash' : 'mobile_money',
      });

  Future<({List<AuditItem> items, int? next})> audit({int? before}) async {
    final j = await api.get('/audit', query: {'limit': '50', if (before != null) 'before': '$before'}) as Json;
    return (items: _list(j['items']).map(AuditItem.fromJson).toList(), next: j['next'] as int?);
  }
}
