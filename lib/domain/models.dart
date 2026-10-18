// Modèles typés des réponses de l'API. L'application n'effectue aucun calcul de paie :
// les montants sont calculés par le serveur (fractions exactes) et seulement affichés ici.

typedef Json = Map<String, dynamic>;

Json _j(Object? o) => o as Json;
List<Json> _list(Object? o) => (o as List).cast<Json>();

enum Role { admin, chief }

extension RoleX on Role {
  String get label => this == Role.admin ? 'Admin' : 'Superviseur';
  static Role parse(String s) => s == 'admin' ? Role.admin : Role.chief;
}

class AppUser {
  final String id;
  final String name;
  final Role role;
  final String? workerId;
  const AppUser({required this.id, required this.name, required this.role, this.workerId});

  factory AppUser.fromJson(Json j) => AppUser(
        id: j['id'] as String,
        name: j['name'] as String,
        role: RoleX.parse(j['role'] as String),
        workerId: j['workerId'] as String?,
      );
}

/// Montant renvoyé par le serveur : valeur exacte « n/d », affichage décimal, indicateur d'approximation.
class Money {
  final String exact;
  final String value;
  final bool approx;
  const Money(this.exact, this.value, this.approx);
  static const zero = Money('0/1', '0.00', false);

  factory Money.fromJson(Object? o) {
    if (o == null) return zero;
    final j = _j(o);
    return Money(j['exact'] as String, j['value'] as String, j['approx'] as bool);
  }

  bool get isNegative => value.startsWith('-');
}

enum Presence { present, absent, unset }

Presence parsePresence(String s) => Presence.values.firstWhere((p) => p.name == s);

class MyTeam {
  final String id;
  final String name;
  final String relation; // titulaire | remplaçant
  const MyTeam(this.id, this.name, this.relation);
  factory MyTeam.fromJson(Json j) => MyTeam(j['id'] as String, j['name'] as String, j['role'] as String);
}

class PersonRef {
  final String id;
  final String name;
  const PersonRef(this.id, this.name);
  static PersonRef? from(Object? o) => o == null ? null : PersonRef(_j(o)['id'] as String, _j(o)['name'] as String);
}

class TeamInfo {
  final String id;
  final String name;
  final PersonRef? chief;
  final PersonRef? interim;
  final int members;
  const TeamInfo({required this.id, required this.name, this.chief, this.interim, required this.members});

  factory TeamInfo.fromJson(Json j) => TeamInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        chief: PersonRef.from(j['chief']),
        interim: PersonRef.from(j['interim']),
        members: j['members'] as int,
      );
}

class WorkerInfo {
  final String id;
  final String fullName;
  final String? phone;
  final String? village;
  final String? mobileOperator;
  final String? mobileNumber;
  final String? teamId;
  final String? teamName;
  final bool active;
  final bool faceEnrolled;
  final bool isSupervisor;
  const WorkerInfo({
    required this.id,
    required this.fullName,
    this.phone,
    this.village,
    this.mobileOperator,
    this.mobileNumber,
    this.teamId,
    this.teamName,
    required this.active,
    required this.faceEnrolled,
    required this.isSupervisor,
  });

  factory WorkerInfo.fromJson(Json j) => WorkerInfo(
        id: j['id'] as String,
        fullName: j['fullName'] as String,
        phone: j['phone'] as String?,
        village: j['village'] as String?,
        mobileOperator: j['mobileOperator'] as String?,
        mobileNumber: j['mobileNumber'] as String?,
        teamId: j['teamId'] as String?,
        teamName: j['teamName'] as String?,
        active: j['active'] as bool,
        faceEnrolled: j['faceEnrolled'] as bool,
        isSupervisor: j['isSupervisor'] as bool,
      );
}

class SupervisorInfo {
  final String id;
  final String name;
  final bool active;
  final String workerId;
  final String? teamName;
  final List<String> chiefOf;
  final List<String> interimOf;
  const SupervisorInfo({
    required this.id,
    required this.name,
    required this.active,
    required this.workerId,
    this.teamName,
    required this.chiefOf,
    required this.interimOf,
  });

  factory SupervisorInfo.fromJson(Json j) => SupervisorInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        active: j['active'] as bool,
        workerId: j['workerId'] as String,
        teamName: j['teamName'] as String?,
        chiefOf: (j['chiefOf'] as List).cast<String>(),
        interimOf: (j['interimOf'] as List).cast<String>(),
      );
}

/// Membre d'une équipe pour une journée. `status` et `faceVerified` sont modifiables avant enregistrement.
class Member {
  final String workerId;
  final String fullName;
  Presence status;
  bool faceVerified;
  String? absenceReason; // sick | permission | unjustified | other (seulement si absent)
  final bool isSubstitute;
  final bool faceEnrolled;
  final bool isSelf;
  Member({
    required this.workerId,
    required this.fullName,
    required this.status,
    required this.faceVerified,
    required this.isSubstitute,
    required this.faceEnrolled,
    required this.isSelf,
    this.absenceReason,
  });

  factory Member.fromJson(Json j) => Member(
        workerId: j['workerId'] as String,
        fullName: j['fullName'] as String,
        status: parsePresence(j['status'] as String),
        faceVerified: j['faceVerified'] as bool,
        isSubstitute: j['isSubstitute'] as bool,
        faceEnrolled: j['faceEnrolled'] as bool,
        isSelf: j['isSelf'] as bool,
        absenceReason: j['absenceReason'] as String?,
      );

  /// Copie locale (affichage hors ligne d'une saisie en attente).
  Json toJson() => {
        'workerId': workerId,
        'fullName': fullName,
        'status': status.name,
        'faceVerified': faceVerified && status == Presence.present,
        'isSubstitute': isSubstitute,
        'faceEnrolled': faceEnrolled,
        'isSelf': isSelf,
        'absenceReason': status == Presence.absent ? absenceReason : null,
      };

  Json toPayload() => {
        'workerId': workerId,
        'status': status.name,
        'isSubstitute': isSubstitute,
        'faceVerified': faceVerified && status == Presence.present,
        'absenceReason': status == Presence.absent ? absenceReason : null,
      };
}

class DayCalc {
  final String status;
  final int? bricks;
  final int? costRate;
  final int? saleRate;
  final Money cost;
  final Money sale;
  final Money margin;
  final Money? share;
  const DayCalc({
    required this.status,
    this.bricks,
    this.costRate,
    this.saleRate,
    required this.cost,
    required this.sale,
    required this.margin,
    this.share,
  });

  factory DayCalc.fromJson(Json j) => DayCalc(
        status: j['status'] as String,
        bricks: j['bricks'] as int?,
        costRate: j['costRate'] as int?,
        saleRate: j['saleRate'] as int?,
        cost: Money.fromJson(j['cost']),
        sale: Money.fromJson(j['sale']),
        margin: Money.fromJson(j['margin']),
        share: j['share'] == null ? null : Money.fromJson(j['share']),
      );
}

/// Une journée d'équipe. `calc` n'existe que pour l'admin : le serveur ne l'envoie jamais à un superviseur.
class DayView {
  final String teamId;
  final String date;
  final bool saved;
  final bool locked;
  final String? version; // sert à détecter une modification faite ailleurs (synchronisation)
  final WorkingDay workingDay;
  final int? bricks;
  final List<Member> members;
  final String? enteredBy;
  final DayCalc? calc;
  const DayView({
    required this.teamId,
    required this.date,
    required this.saved,
    required this.locked,
    this.version,
    this.workingDay = WorkingDay.work,
    required this.bricks,
    required this.members,
    this.enteredBy,
    this.calc,
  });

  factory DayView.fromJson(Json j) => DayView(
        teamId: j['teamId'] as String,
        date: j['date'] as String,
        saved: j['saved'] as bool,
        locked: j['locked'] as bool,
        version: j['version'] as String?,
        workingDay: j['workingDay'] == null ? WorkingDay.work : WorkingDay.fromJson(_j(j['workingDay'])),
        bricks: j['bricks'] as int?,
        members: _list(j['members']).map(Member.fromJson).toList(),
        enteredBy: j['enteredBy'] as String?,
        calc: j['calc'] == null ? null : DayCalc.fromJson(_j(j['calc'])),
      );

  /// Copie locale sans calcul : un superviseur n'en reçoit jamais.
  Json toJson() => {
        'teamId': teamId,
        'date': date,
        'saved': saved,
        'locked': locked,
        'version': version,
        'workingDay': workingDay.toJson(),
        'bricks': bricks,
        'members': members.map((m) => m.toJson()).toList(),
        'enteredBy': enteredBy,
      };
}

class SubstituteCandidate {
  final String workerId;
  final String fullName;
  final String? teamName;
  final bool faceEnrolled;
  const SubstituteCandidate(this.workerId, this.fullName, this.teamName, this.faceEnrolled);
  factory SubstituteCandidate.fromJson(Json j) => SubstituteCandidate(
      j['workerId'] as String, j['fullName'] as String, j['teamName'] as String?, j['faceEnrolled'] as bool);
}

class FaceResult {
  final bool match;
  final double distance;
  const FaceResult(this.match, this.distance);
  factory FaceResult.fromJson(Json j) => FaceResult(j['match'] as bool, (j['distance'] as num).toDouble());
}

class ImportRow {
  final int line;
  final String name;
  final String status; // ok | duplicate | error
  final String message;
  const ImportRow(this.line, this.name, this.status, this.message);
  factory ImportRow.fromJson(Json j) => ImportRow(j['line'] as int, j['name'] as String, j['status'] as String, j['message'] as String);
}

class ImportResult {
  final bool dryRun;
  final int imported;
  final int ok;
  final int duplicate;
  final int error;
  final List<ImportRow> rows;
  const ImportResult(this.dryRun, this.imported, this.ok, this.duplicate, this.error, this.rows);
  factory ImportResult.fromJson(Json j) {
    final c = _j(j['counts']);
    return ImportResult(j['dryRun'] as bool, j['imported'] as int, c['ok'] as int, c['duplicate'] as int, c['error'] as int,
        _list(j['rows']).map(ImportRow.fromJson).toList());
  }
}

// ───────────────────────── Factures ─────────────────────────

class Letterhead {
  final String name;
  final String footer;
  final String place;
  final String signer;
  const Letterhead({required this.name, required this.footer, required this.place, required this.signer});
  factory Letterhead.fromJson(Json j) => Letterhead(
      name: j['name'] as String, footer: (j['footer'] as String?) ?? '', place: j['place'] as String, signer: j['signer'] as String);
  Json toJson() => {'name': name, 'footer': footer, 'place': place, 'signer': signer};
}

class ClientInfo {
  final String id;
  final String code;
  final String name;
  final String? status;
  final String? rccm;
  final String? ifu;
  final String? capital;
  final String? address;
  final bool active;
  const ClientInfo({
    required this.id,
    required this.code,
    required this.name,
    this.status,
    this.rccm,
    this.ifu,
    this.capital,
    this.address,
    this.active = true,
  });
  factory ClientInfo.fromJson(Json j) => ClientInfo(
        id: (j['id'] as String?) ?? '',
        code: (j['code'] as String?) ?? '',
        name: j['name'] as String,
        status: j['status'] as String?,
        rccm: j['rccm'] as String?,
        ifu: j['ifu'] as String?,
        capital: j['capital'] as String?,
        address: j['address'] as String?,
        active: (j['active'] as bool?) ?? true,
      );
}

class InvoiceLine {
  String? date; // AAAA-MM-JJ, ou null (ex. ligne « Echantillons »)
  String label;
  int qty;
  InvoiceLine({this.date, required this.label, required this.qty});
  factory InvoiceLine.fromJson(Json j) => InvoiceLine(date: j['date'] as String?, label: j['label'] as String, qty: j['qty'] as int);
  Json toJson() => {'date': date, 'label': label, 'qty': qty};
}

class InvoiceDraft {
  final int? suggestedUnitPrice;
  final List<InvoiceLine> lines;
  const InvoiceDraft(this.suggestedUnitPrice, this.lines);
  factory InvoiceDraft.fromJson(Json j) =>
      InvoiceDraft(j['suggestedUnitPrice'] as int?, _list(j['lines']).map(InvoiceLine.fromJson).toList());
}

class InvoiceSummary {
  final String id;
  final String number;
  final String clientName;
  final String issuedOn;
  final int totalQty;
  final int totalAmount;
  final String status; // issued | cancelled
  const InvoiceSummary(this.id, this.number, this.clientName, this.issuedOn, this.totalQty, this.totalAmount, this.status);
  factory InvoiceSummary.fromJson(Json j) => InvoiceSummary(j['id'] as String, j['number'] as String, (j['clientName'] as String?) ?? '',
      (j['issuedOn'] as String).substring(0, 10), j['totalQty'] as int, j['totalAmount'] as int, j['status'] as String);
}

class Invoice {
  final String id;
  final String number;
  final String issuedOn;
  final String place;
  final String subject;
  final int unitPrice;
  final List<InvoiceLine> lines;
  final int totalQty;
  final int totalAmount;
  final String amountWords;
  final String signer;
  final ClientInfo client;
  final Letterhead letterhead;
  final String status;
  final String? cancelReason;
  const Invoice({
    required this.id,
    required this.number,
    required this.issuedOn,
    required this.place,
    required this.subject,
    required this.unitPrice,
    required this.lines,
    required this.totalQty,
    required this.totalAmount,
    required this.amountWords,
    required this.signer,
    required this.client,
    required this.letterhead,
    required this.status,
    this.cancelReason,
  });
  factory Invoice.fromJson(Json j) => Invoice(
        id: j['id'] as String,
        number: j['number'] as String,
        issuedOn: (j['issuedOn'] as String).substring(0, 10),
        place: j['place'] as String,
        subject: j['subject'] as String,
        unitPrice: j['unitPrice'] as int,
        lines: _list(j['lines']).map(InvoiceLine.fromJson).toList(),
        totalQty: j['totalQty'] as int,
        totalAmount: j['totalAmount'] as int,
        amountWords: j['amountWords'] as String,
        signer: j['signer'] as String,
        client: ClientInfo.fromJson(_j(j['client'])),
        letterhead: Letterhead.fromJson(_j(j['letterhead'])),
        status: j['status'] as String,
        cancelReason: j['cancelReason'] as String?,
      );
}

// ───────────────────────── Avances, période, alertes ─────────────────────────

class AdvanceItem {
  final String id;
  final String workerId;
  final String fullName;
  final int amount;
  final String givenAt;
  final String mode;
  final String? note;
  const AdvanceItem(this.id, this.workerId, this.fullName, this.amount, this.givenAt, this.mode, this.note);
  factory AdvanceItem.fromJson(Json j) => AdvanceItem(j['id'] as String, j['workerId'] as String, j['fullName'] as String,
      j['amount'] as int, (j['givenAt'] as String).substring(0, 10), j['mode'] as String, j['note'] as String?);
}

class PeriodReport {
  final String from;
  final String to;
  final String label;
  final int days;
  final int bricks;
  final Money cost;
  final Money sale;
  final Money margin;
  final int incompleteDays;
  final List<({String name, Money total})> teams;
  final List<({String workerId, String fullName, int days, Money total})> workers;
  const PeriodReport({
    required this.from,
    required this.to,
    required this.label,
    required this.days,
    required this.bricks,
    required this.cost,
    required this.sale,
    required this.margin,
    required this.incompleteDays,
    required this.teams,
    required this.workers,
  });
  factory PeriodReport.fromJson(Json j) => PeriodReport(
        from: j['from'] as String,
        to: j['to'] as String,
        label: j['label'] as String,
        days: j['days'] as int,
        bricks: j['bricks'] as int,
        cost: Money.fromJson(j['cost']),
        sale: Money.fromJson(j['sale']),
        margin: Money.fromJson(j['margin']),
        incompleteDays: j['incompleteDays'] as int,
        teams: _list(j['teams']).map((t) => (name: t['name'] as String, total: Money.fromJson(t['total']))).toList(),
        workers: _list(j['workers'])
            .map((w) => (workerId: w['workerId'] as String, fullName: w['fullName'] as String, days: w['days'] as int, total: Money.fromJson(w['total'])))
            .toList(),
      );
}

class AlertItem {
  final String level; // high | medium | info
  final String kind;
  final String title;
  final String detail;
  const AlertItem(this.level, this.kind, this.title, this.detail);
  factory AlertItem.fromJson(Json j) =>
      AlertItem(j['level'] as String, j['kind'] as String, j['title'] as String, j['detail'] as String);
}

class AlertsView {
  final int count;
  final int high;
  final List<AlertItem> alerts;
  const AlertsView(this.count, this.high, this.alerts);
  factory AlertsView.fromJson(Json j) =>
      AlertsView(j['count'] as int, j['high'] as int, _list(j['alerts']).map(AlertItem.fromJson).toList());
}

// ───────────────────────── Statistiques ─────────────────────────

double? _rate(Object? o) => (o as num?)?.toDouble();

class TrendPoint {
  final String month;
  final String label;
  final int bricks;
  final int workedDays;
  final double? attendanceRate;
  final Money cost;
  final Money sale;
  final Money margin;
  const TrendPoint(this.month, this.label, this.bricks, this.workedDays, this.attendanceRate, this.cost, this.sale, this.margin);
  factory TrendPoint.fromJson(Json j) => TrendPoint(j['month'] as String, j['label'] as String, j['bricks'] as int,
      j['workedDays'] as int, _rate(j['attendanceRate']), Money.fromJson(j['cost']), Money.fromJson(j['sale']), Money.fromJson(j['margin']));
}

class TeamStat {
  final String name;
  final int bricks;
  final int workedDays;
  final int? avgBricksPerDay;
  final int? bricksPerPresent;
  final double? attendanceRate;
  const TeamStat(this.name, this.bricks, this.workedDays, this.avgBricksPerDay, this.bricksPerPresent, this.attendanceRate);
  factory TeamStat.fromJson(Json j) => TeamStat(j['name'] as String, j['bricks'] as int, j['workedDays'] as int,
      j['avgBricksPerDay'] as int?, j['bricksPerPresent'] as int?, _rate(j['attendanceRate']));
}

class WorkerStat {
  final String workerId;
  final String fullName;
  final int present;
  final int absent;
  final double? attendanceRate;
  final Money earned;
  const WorkerStat(this.workerId, this.fullName, this.present, this.absent, this.attendanceRate, this.earned);
  factory WorkerStat.fromJson(Json j) => WorkerStat(j['workerId'] as String, j['fullName'] as String, j['present'] as int,
      j['absent'] as int, _rate(j['attendanceRate']), Money.fromJson(j['earned']));
}

class Stats {
  final String month;
  final String label;
  final int bricks;
  final int workedDays;
  final double? attendanceRate;
  final int? avgBricksPerDay;
  final ({String date, int bricks})? bestDay;
  final Money cost;
  final Money sale;
  final Money margin;
  final List<TrendPoint> trend;
  final List<TeamStat> teams;
  final List<WorkerStat> workers;
  final List<({String date, int bricks})> daily;
  const Stats({
    required this.month,
    required this.label,
    required this.bricks,
    required this.workedDays,
    this.attendanceRate,
    this.avgBricksPerDay,
    this.bestDay,
    required this.cost,
    required this.sale,
    required this.margin,
    required this.trend,
    required this.teams,
    required this.workers,
    required this.daily,
  });

  factory Stats.fromJson(Json j) {
    final t = _j(j['totals']);
    ({String date, int bricks}) day(Json d) => (date: d['date'] as String, bricks: d['bricks'] as int);
    return Stats(
      month: j['month'] as String,
      label: j['label'] as String,
      bricks: t['bricks'] as int,
      workedDays: t['workedDays'] as int,
      attendanceRate: _rate(t['attendanceRate']),
      avgBricksPerDay: t['avgBricksPerDay'] as int?,
      bestDay: t['bestDay'] == null ? null : day(_j(t['bestDay'])),
      cost: Money.fromJson(t['cost']),
      sale: Money.fromJson(t['sale']),
      margin: Money.fromJson(t['margin']),
      trend: _list(j['trend']).map(TrendPoint.fromJson).toList(),
      teams: _list(j['teams']).map(TeamStat.fromJson).toList(),
      workers: _list(j['workers']).map(WorkerStat.fromJson).toList(),
      daily: _list(j['daily']).map(day).toList(),
    );
  }
}

// ───────────────────────── Calendrier de travail ─────────────────────────

const dayKindLabels = {
  'work': 'Travaillé (exceptionnel)',
  'rest': 'Repos',
  'holiday': 'Férié',
  'weather': 'Intempérie',
  'breakdown': 'Panne',
  'other': 'Autre',
};

const absenceReasonLabels = {
  'sick': 'Maladie',
  'permission': 'Permission',
  'unjustified': 'Non justifiée',
  'other': 'Autre',
};

/// Statut d'un jour pour une équipe, selon le calendrier (équipe > global > repos hebdomadaire).
class WorkingDay {
  final bool working;
  final String kind;
  final String? reason;
  final String source; // team | global | weekly | default
  const WorkingDay({required this.working, required this.kind, this.reason, required this.source});

  static const work = WorkingDay(working: true, kind: 'work', source: 'default');

  factory WorkingDay.fromJson(Json j) => WorkingDay(
        working: j['working'] as bool,
        kind: j['kind'] as String,
        reason: j['reason'] as String?,
        source: j['source'] as String,
      );

  Json toJson() => {'working': working, 'kind': kind, 'reason': reason, 'source': source};

  String get label => dayKindLabels[kind] ?? kind;
  String get describe => reason == null || reason!.isEmpty ? label : '$label : $reason';
}

class CalendarCell {
  final String teamId;
  final WorkingDay day;
  final String state; // off | future | pending | missing | incomplete | complete
  final int? bricks;
  const CalendarCell({required this.teamId, required this.day, required this.state, this.bricks});

  factory CalendarCell.fromJson(Json j) => CalendarCell(
        teamId: j['teamId'] as String,
        day: WorkingDay.fromJson(j),
        state: j['state'] as String,
        bricks: j['bricks'] as int?,
      );
}

class CalendarDay {
  final String date;
  final int weekday; // 0 = dimanche … 6 = samedi
  final List<CalendarCell> cells;
  const CalendarDay(this.date, this.weekday, this.cells);

  factory CalendarDay.fromJson(Json j) => CalendarDay(
        j['date'] as String,
        j['weekday'] as int,
        _list(j['teams']).map(CalendarCell.fromJson).toList(),
      );
}

class CalendarMonth {
  final String month;
  final String today;
  final List<int> restWeekdays;
  final List<({String id, String name})> teams;
  final List<CalendarDay> days;
  const CalendarMonth({
    required this.month,
    required this.today,
    required this.restWeekdays,
    required this.teams,
    required this.days,
  });

  factory CalendarMonth.fromJson(Json j) => CalendarMonth(
        month: j['month'] as String,
        today: j['today'] as String,
        restWeekdays: (j['restWeekdays'] as List).cast<int>(),
        teams: _list(j['teams']).map((t) => (id: t['id'] as String, name: t['name'] as String)).toList(),
        days: _list(j['days']).map(CalendarDay.fromJson).toList(),
      );
}

// ───────────────────────── Fiche d'un ouvrier ─────────────────────────

class SheetLine {
  final String date;
  final String? teamName;
  final Presence status;
  final bool isSubstitute;
  final bool faceVerified;
  final String? absenceReason;
  final String dayStatus;
  final Money? share;
  const SheetLine({
    required this.date,
    this.teamName,
    required this.status,
    required this.isSubstitute,
    required this.faceVerified,
    this.absenceReason,
    required this.dayStatus,
    this.share,
  });

  factory SheetLine.fromJson(Json j) => SheetLine(
        date: j['date'] as String,
        teamName: j['teamName'] as String?,
        status: parsePresence(j['status'] as String),
        isSubstitute: j['isSubstitute'] as bool,
        faceVerified: j['faceVerified'] as bool,
        absenceReason: j['absenceReason'] as String?,
        dayStatus: j['dayStatus'] as String,
        share: j['share'] == null ? null : Money.fromJson(j['share']),
      );
}

class WorkerSheet {
  final WorkerInfo worker;
  final String month;
  final bool locked;
  final int present;
  final int absent;
  final int unset;
  final double? attendanceRate;
  final Map<String, int> absences; // sick | permission | unjustified | other | unspecified
  final Money earned;
  final int paid;
  final int advanced;
  final List<({String id, String givenAt, int amount, String mode, String? note})> advances;
  final Money balance;
  final List<SheetLine> lines;
  final List<({String paidAt, int paid, String mode})> payments;
  const WorkerSheet({
    required this.worker,
    required this.month,
    required this.locked,
    required this.present,
    required this.absent,
    required this.unset,
    this.attendanceRate,
    required this.absences,
    required this.earned,
    required this.paid,
    this.advanced = 0,
    this.advances = const [],
    required this.balance,
    required this.lines,
    required this.payments,
  });

  factory WorkerSheet.fromJson(Json j) {
    final s = _j(j['stats']);
    return WorkerSheet(
      worker: WorkerInfo.fromJson(_j(j['worker'])),
      month: j['month'] as String,
      locked: j['locked'] as bool,
      present: s['present'] as int,
      absent: s['absent'] as int,
      unset: s['unset'] as int,
      attendanceRate: (s['attendanceRate'] as num?)?.toDouble(),
      absences: _j(s['absences']).map((k, v) => MapEntry(k, v as int)),
      earned: Money.fromJson(j['earned']),
      paid: j['paid'] as int,
      advanced: (j['advanced'] as int?) ?? 0,
      advances: _list(j['advances'] ?? [])
          .map((a) => (id: a['id'] as String, givenAt: a['givenAt'] as String, amount: a['amount'] as int, mode: a['mode'] as String, note: a['note'] as String?))
          .toList(),
      balance: Money.fromJson(j['balance']),
      lines: _list(j['lines']).map(SheetLine.fromJson).toList(),
      payments: _list(j['payments'])
          .map((p) => (paidAt: p['paidAt'] as String, paid: p['paid'] as int, mode: p['mode'] as String))
          .toList(),
    );
  }
}

// ───────────────────────── Vue admin du jour ─────────────────────────

class OverviewMember {
  final String workerId;
  final String fullName;
  final Presence status;
  final bool faceVerified;
  const OverviewMember(this.workerId, this.fullName, this.status, this.faceVerified);
  factory OverviewMember.fromJson(Json j) => OverviewMember(
      j['workerId'] as String, j['fullName'] as String, parsePresence(j['status'] as String), j['faceVerified'] as bool);
}

class OverviewTeam {
  final String teamId;
  final String name;
  final String? chief;
  final String? interim;
  final bool saved;
  final bool locked;
  final int present;
  final int absent;
  final int unset;
  final String? enteredBy;
  final String status;
  final int? bricks;
  final Money cost;
  final Money sale;
  final Money? share;
  final List<OverviewMember> members;
  const OverviewTeam({
    required this.teamId,
    required this.name,
    this.chief,
    this.interim,
    required this.saved,
    required this.locked,
    required this.present,
    required this.absent,
    required this.unset,
    this.enteredBy,
    required this.status,
    this.bricks,
    required this.cost,
    required this.sale,
    this.share,
    required this.members,
  });

  factory OverviewTeam.fromJson(Json j) {
    final c = _j(j['counts']);
    return OverviewTeam(
      teamId: j['teamId'] as String,
      name: j['name'] as String,
      chief: j['chief'] as String?,
      interim: j['interim'] as String?,
      saved: j['saved'] as bool,
      locked: j['locked'] as bool,
      present: c['present'] as int,
      absent: c['absent'] as int,
      unset: c['unset'] as int,
      enteredBy: j['enteredBy'] as String?,
      status: j['status'] as String,
      bricks: j['bricks'] as int?,
      cost: Money.fromJson(j['cost']),
      sale: Money.fromJson(j['sale']),
      share: j['share'] == null ? null : Money.fromJson(j['share']),
      members: _list(j['members']).map(OverviewMember.fromJson).toList(),
    );
  }
}

/// Une personne connectée en ce moment (vue de l'admin).
class OnlineUser {
  final String id;
  final String name;
  final Role role;
  final String? teams;
  final DateTime lastSeen;
  final bool isMe;
  const OnlineUser({
    required this.id,
    required this.name,
    required this.role,
    this.teams,
    required this.lastSeen,
    required this.isMe,
  });

  factory OnlineUser.fromJson(Json j) => OnlineUser(
        id: j['id'] as String,
        name: j['name'] as String,
        role: RoleX.parse(j['role'] as String),
        teams: j['teams'] as String?,
        lastSeen: DateTime.parse(j['lastSeenAt'] as String).toLocal(),
        isMe: j['isMe'] as bool,
      );
}

class Overview {
  final String date;
  final int present;
  final int absent;
  final int unset;
  final int teamsWithoutEntry;
  final int bricks;
  final int? costRate;
  final int? saleRate;
  final Money cost;
  final Money sale;
  final Money margin;
  final int workersActive;
  final int workersTotal;
  final int workersWithFace;
  final int supervisors;
  final List<OnlineUser> online;
  final int onlineWindowMinutes;
  final List<OverviewTeam> teams;
  const Overview({
    required this.date,
    required this.present,
    required this.absent,
    required this.unset,
    required this.teamsWithoutEntry,
    required this.bricks,
    this.costRate,
    this.saleRate,
    required this.cost,
    required this.sale,
    required this.margin,
    required this.workersActive,
    required this.workersTotal,
    required this.workersWithFace,
    required this.supervisors,
    required this.online,
    required this.onlineWindowMinutes,
    required this.teams,
  });

  factory Overview.fromJson(Json j) {
    final t = _j(j['totals']);
    final p = _j(j['production']);
    final w = _j(j['workers']);
    return Overview(
      date: j['date'] as String,
      present: t['present'] as int,
      absent: t['absent'] as int,
      unset: t['unset'] as int,
      teamsWithoutEntry: t['teamsWithoutEntry'] as int,
      bricks: p['bricks'] as int,
      costRate: p['costRate'] as int?,
      saleRate: p['saleRate'] as int?,
      cost: Money.fromJson(p['cost']),
      sale: Money.fromJson(p['sale']),
      margin: Money.fromJson(p['margin']),
      workersActive: w['active'] as int,
      workersTotal: w['total'] as int,
      workersWithFace: w['withFace'] as int,
      supervisors: w['supervisors'] as int,
      online: _list(j['online']).map(OnlineUser.fromJson).toList(),
      onlineWindowMinutes: j['onlineWindowMinutes'] as int,
      teams: _list(j['teams']).map(OverviewTeam.fromJson).toList(),
    );
  }
}

// ───────────────────────── Paie, paiements ─────────────────────────

class PayrollLine {
  final String date;
  final String teamId;
  final Money share;
  const PayrollLine(this.date, this.teamId, this.share);
  factory PayrollLine.fromJson(Json j) => PayrollLine(j['date'] as String, j['teamId'] as String, Money.fromJson(j['share']));
}

class PayrollWorker {
  final String workerId;
  final String fullName;
  final int days;
  final Money total;
  final int advances;
  final int paid;
  final Money balance;
  final List<PayrollLine> lines;
  const PayrollWorker({
    required this.workerId,
    required this.fullName,
    required this.days,
    required this.total,
    this.advances = 0,
    required this.paid,
    required this.balance,
    required this.lines,
  });

  factory PayrollWorker.fromJson(Json j) => PayrollWorker(
        workerId: j['workerId'] as String,
        fullName: j['fullName'] as String,
        days: j['days'] as int,
        total: Money.fromJson(j['total']),
        advances: (j['advances'] as int?) ?? 0,
        paid: j['paid'] as int,
        balance: Money.fromJson(j['balance']),
        lines: _list(j['lines']).map(PayrollLine.fromJson).toList(),
      );
}

class Anomaly {
  final String kind;
  final String date;
  final String message;
  final bool blocking;
  const Anomaly(this.kind, this.date, this.message, this.blocking);
  factory Anomaly.fromJson(Json j) =>
      Anomaly(j['kind'] as String, j['date'] as String, j['message'] as String, j['blocking'] as bool);
}

class PayrollVersion {
  final int version;
  final Money total;
  final String validatedBy;
  final String validatedAt;
  final String? unlockedBy;
  final String? unlockedAt;
  final String? unlockReason;
  const PayrollVersion({
    required this.version,
    required this.total,
    required this.validatedBy,
    required this.validatedAt,
    this.unlockedBy,
    this.unlockedAt,
    this.unlockReason,
  });

  bool get locked => unlockedAt == null;

  factory PayrollVersion.fromJson(Json j) => PayrollVersion(
        version: j['version'] as int,
        total: Money.fromJson(j['total']),
        validatedBy: j['validatedBy'] as String,
        validatedAt: j['validatedAt'] as String,
        unlockedBy: j['unlockedBy'] as String?,
        unlockedAt: j['unlockedAt'] as String?,
        unlockReason: j['unlockReason'] as String?,
      );
}

class PayrollView {
  final String month;
  final bool locked;
  final int? currentVersion;
  final Money total;
  final bool hasBlocking;
  final List<({String teamId, String name, Money total})> teams;
  final List<PayrollWorker> workers;
  final List<Anomaly> anomalies;
  final List<PayrollVersion> versions;
  const PayrollView({
    required this.month,
    required this.locked,
    this.currentVersion,
    required this.total,
    required this.hasBlocking,
    required this.teams,
    required this.workers,
    required this.anomalies,
    required this.versions,
  });

  factory PayrollView.fromJson(Json j) => PayrollView(
        month: j['month'] as String,
        locked: j['locked'] as bool,
        currentVersion: j['currentVersion'] as int?,
        total: Money.fromJson(j['total']),
        hasBlocking: j['hasBlocking'] as bool,
        teams: _list(j['teams'])
            .map((t) => (teamId: t['teamId'] as String, name: t['name'] as String, total: Money.fromJson(t['total'])))
            .toList(),
        workers: _list(j['workers']).map(PayrollWorker.fromJson).toList(),
        anomalies: _list(j['anomalies']).map(Anomaly.fromJson).toList(),
        versions: _list(j['versions']).map(PayrollVersion.fromJson).toList(),
      );
}

class PaymentRow {
  final String workerId;
  final String fullName;
  final Money due;
  final int advances;
  final int paid;
  final Money balance;
  final int proposed;
  const PaymentRow({
    required this.workerId,
    required this.fullName,
    required this.due,
    this.advances = 0,
    required this.paid,
    required this.balance,
    required this.proposed,
  });

  factory PaymentRow.fromJson(Json j) => PaymentRow(
        workerId: j['workerId'] as String,
        fullName: j['fullName'] as String,
        due: Money.fromJson(j['due']),
        advances: (j['advances'] as int?) ?? 0,
        paid: j['paid'] as int,
        balance: Money.fromJson(j['balance']),
        proposed: j['proposed'] as int,
      );
}

class PaymentsView {
  final String month;
  final bool locked;
  final List<PaymentRow> workers;
  const PaymentsView(this.month, this.locked, this.workers);
  factory PaymentsView.fromJson(Json j) => PaymentsView(
      j['month'] as String, j['locked'] as bool, _list(j['workers']).map(PaymentRow.fromJson).toList());
}

// ───────────────────────── Tarifs, audit ─────────────────────────

enum PriceKind { cost, sale }

class TariffEntry {
  final int value;
  final String effectiveDate;
  final String reason;
  final String author;
  final String recordedAt;
  const TariffEntry(this.value, this.effectiveDate, this.reason, this.author, this.recordedAt);
  factory TariffEntry.fromJson(Json j) => TariffEntry(j['value'] as int, j['effectiveDate'] as String,
      j['reason'] as String, j['author'] as String, j['recordedAt'] as String);
}

class PriceGroup {
  final PriceKind kind;
  final String label;
  final String hint;
  final int? current;
  final List<TariffEntry> history;
  const PriceGroup(this.kind, this.label, this.hint, this.current, this.history);
  factory PriceGroup.fromJson(Json j) => PriceGroup(
        PriceKind.values.firstWhere((k) => k.name == j['kind']),
        j['label'] as String,
        j['hint'] as String,
        j['current'] as int?,
        _list(j['history']).map(TariffEntry.fromJson).toList(),
      );
}

class AuditItem {
  final int id;
  final String at;
  final String user;
  final String role;
  final String action;
  final String object;
  final String? oldValue;
  final String? newValue;
  final String? reason;
  final bool security;
  const AuditItem({
    required this.id,
    required this.at,
    required this.user,
    required this.role,
    required this.action,
    required this.object,
    this.oldValue,
    this.newValue,
    this.reason,
    required this.security,
  });

  factory AuditItem.fromJson(Json j) => AuditItem(
        id: j['id'] as int,
        at: j['at'] as String,
        user: j['user'] as String,
        role: j['role'] as String,
        action: j['action'] as String,
        object: j['object'] as String,
        oldValue: j['oldValue'] as String?,
        newValue: j['newValue'] as String?,
        reason: j['reason'] as String?,
        security: j['security'] as bool,
      );
}
