import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/app_store.dart';
import '../../domain/models.dart';
import '../face_capture.dart';
import '../glass.dart';
import '../widgets.dart';

/// Saisie d'une journée d'équipe : présences (avec identification par le visage) et nombre de briques.
///
/// Superviseur : voit son équipe (ou celle qu'il remplace) et ne reçoit AUCUN prix ni montant
/// (le serveur ne les envoie pas). Admin : peut corriger n'importe quelle équipe et voit les calculs.
class DayEntryView extends StatefulWidget {
  final String? initialTeamId;
  final DateTime? initialDate;
  final String? initialTeamName;
  const DayEntryView({super.key, this.initialTeamId, this.initialDate, this.initialTeamName});

  @override
  State<DayEntryView> createState() => _DayEntryViewState();
}

class _DayEntryViewState extends State<DayEntryView> {
  List<MyTeam>? _teams;
  String? _teamId;
  late DateTime _date;

  DayView? _day;
  List<Member> _members = [];
  final _qty = TextEditingController();
  int? _bricks;

  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;
  final Set<String> _scanning = {};
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    _date = widget.initialDate ?? dateOnly(DateTime.now());
    _teamId = widget.initialTeamId;
    _boot();
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final store = StoreScope.of(context);
    try {
      if (_teamId == null) {
        final teams = await store.repo.myTeams();
        _teams = teams;
        _teamId = teams.firstOrNull?.id;
      }
      if (_teamId == null) {
        setState(() => _loading = false);
        return;
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _load() async {
    final store = StoreScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final day = await store.repo.day(_teamId!, dateKey(_date));
      if (!mounted) return;
      _apply(day, store);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  void _apply(DayView day, AppStore store) {
    final members = day.members;
    // Le superviseur est connecté donc présent : il n'est pas à cocher.
    if (store.user?.role == Role.chief) {
      for (final m in members.where((m) => m.isSelf && m.status == Presence.unset)) {
        m.status = Presence.present;
      }
    }
    setState(() {
      _day = day;
      _members = members;
      _bricks = day.bricks;
      _qty.text = day.bricks?.toString() ?? '';
      _dirty = false;
      _loading = false;
    });
  }

  Future<void> _guardLeave(VoidCallback change) async {
    if (_dirty &&
        !await confirm(context, 'Modifications non enregistrées', 'Changer de page abandonnera la saisie en cours.',
            ok: 'Abandonner')) {
      return;
    }
    change();
    await _load();
  }

  Future<void> _save() async {
    final store = StoreScope.of(context);
    setState(() => _saving = true);
    final teamName = _teams?.where((t) => t.id == _teamId).firstOrNull?.name ?? widget.initialTeamName ?? 'Équipe';
    String? info;
    final ok = await run(context, () async {
      final r = await store.saveDay(current: _day!, teamName: teamName, bricks: _bricks, members: _members);
      if (mounted) _apply(r.day, store);
      if (r.conflict) {
        info = 'Cette journée a changé sur le serveur : choisissez quelle version garder (bandeau en haut).';
      } else if (r.queued) {
        info = "Enregistré sur l'appareil. Envoi automatique dès que le réseau revient.";
      }
    }, success: null);
    if (ok && mounted) toast(context, info ?? 'Journée enregistrée.');
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _scan(Member m) async {
    final store = StoreScope.of(context);
    if (!m.faceEnrolled) {
      toast(context, 'Visage de ${m.fullName} non enregistré. Demandez à l\'admin.', error: true);
      return;
    }
    final shots = await captureFaces(context, title: 'Identification : ${m.fullName}');
    if (shots == null || !mounted) return;
    setState(() => _scanning.add(m.workerId));
    try {
      final r = await store.repo.verifyFace(m.workerId, shots.first);
      if (!mounted) return;
      if (r.match) {
        setState(() {
          m.status = Presence.present;
          m.faceVerified = true;
          _dirty = true;
        });
        toast(context, '${m.fullName} identifié par le visage.');
      } else {
        toast(context, 'Visage non reconnu pour ${m.fullName}. Réessayez ou cochez manuellement.', error: true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        toast(
            context,
            e.offline
                ? 'Identification faciale indisponible hors ligne : cochez la présence à la main.'
                : e.message,
            error: true);
      }
    } finally {
      if (mounted) setState(() => _scanning.remove(m.workerId));
    }
  }

  Future<void> _addSubstitute() async {
    final store = StoreScope.of(context);
    List<SubstituteCandidate> list;
    try {
      list = await store.repo.substitutes(_teamId!, dateKey(_date));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
      return;
    }
    if (!mounted) return;
    final taken = _members.map((m) => m.workerId).toSet();
    list = list.where((c) => !taken.contains(c.workerId)).toList();
    final picked = await showModalBottomSheet<SubstituteCandidate>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, controller) => Column(children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Choisir un remplaçant', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('Aucun ouvrier disponible ce jour-là.'))
                : ListView(controller: controller, children: [
                    for (final c in list)
                      ListTile(title: Text(c.fullName), subtitle: Text(c.teamName ?? '—'), onTap: () => Navigator.pop(ctx, c)),
                  ]),
          ),
        ]),
      ),
    );
    if (picked == null) return;
    setState(() {
      _members.add(Member(
        workerId: picked.workerId,
        fullName: picked.fullName,
        status: Presence.present,
        faceVerified: false,
        isSubstitute: true,
        faceEnrolled: picked.faceEnrolled,
        isSelf: false,
      ));
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final isAdmin = store.isAdmin;

    if (_loading && _day == null) return const Center(child: CircularProgressIndicator());
    if (_error != null && _day == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _boot, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
          ]),
        ),
      );
    }
    if (_day == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucune équipe ne vous est affectée. Contactez l\'admin.', textAlign: TextAlign.center),
        ),
      );
    }

    final day = _day!;
    final editable = !day.locked && day.workingDay.working;
    final self = !isAdmin ? store.user?.workerId : null;
    final shown = _members.where((m) => m.workerId != self).toList();
    final present = _members.where((m) => m.status == Presence.present).length;
    final absent = _members.where((m) => m.status == Presence.absent).length;
    final unset = _members.where((m) => m.status == Presence.unset).length;
    final faceCount = _members.where((m) => m.faceVerified && m.status == Presence.present).length;
    final complete = unset == 0 && _bricks != null;
    final myTeam = _teams?.where((t) => t.id == _teamId).firstOrNull;
    final calc = day.calc;

    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            Expanded(
              child: (_teams != null && _teams!.length > 1)
                  ? DropdownButtonFormField<String>(
                      initialValue: _teamId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Équipe'),
                      items: [for (final t in _teams!) DropdownMenuItem(value: t.id, child: Text(t.name))],
                      onChanged: (v) => _guardLeave(() => _teamId = v),
                    )
                  : InputDecorator(
                      decoration: const InputDecoration(labelText: 'Équipe'),
                      child: Text(_teams?.firstOrNull?.name ?? widget.initialTeamName ?? 'Équipe', overflow: TextOverflow.ellipsis),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                      context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
                  if (d != null) _guardLeave(() => _date = dateOnly(d));
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'Date', suffixIcon: Icon(Icons.calendar_today, size: 18)),
                  child: Text(fmtDate(dateKey(_date))),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(fmtLongDate(_date), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          if (myTeam?.relation == 'remplaçant')
            const InfoBanner(
                icon: Icons.swap_horiz, color: accent, text: 'Vous remplacez le superviseur titulaire de cette équipe.'),
          if (!day.workingDay.working)
            InfoBanner(
                icon: Icons.event_busy,
                color: warnColor,
                text: 'Jour non travaillé (${day.workingDay.describe}). La saisie est désactivée.'),
          if (day.locked)
            const InfoBanner(
                icon: Icons.lock, color: warnColor, text: 'La paie de ce mois est verrouillée : lecture seule.'),
          if (!day.locked && day.saved)
            InfoBanner(
                icon: Icons.check_circle,
                color: okColor,
                text: 'Journée déjà enregistrée par ${day.enteredBy ?? '—'}. Toute correction est tracée.'),

          SectionTitle('Membres de l\'équipe (${shown.length})',
              trailing: editable
                  ? TextButton.icon(
                      onPressed: () => setState(() {
                        for (final m in _members) {
                          if (m.status == Presence.unset) m.status = Presence.present;
                        }
                        _dirty = true;
                      }),
                      icon: const Icon(Icons.done_all, size: 18),
                      label: const Text('Non saisis : présents'),
                    )
                  : null),
          GlassCard(
            child: Column(children: [
              if (shown.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text('Aucun ouvrier actif dans cette équipe.')),
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _memberRow(shown[i], editable),
              ],
            ]),
          ),
          if (editable)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addSubstitute,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Ajouter un ouvrier remplaçant'),
              ),
            ),

          const SectionTitle('Briques confectionnées'),
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                TextField(
                  controller: _qty,
                  enabled: editable,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  decoration: InputDecoration(
                    labelText: 'Nombre de briques confectionnées',
                    prefixIcon: const Icon(Icons.view_in_ar_rounded),
                    helperText: _bricks == null ? 'Non saisi' : null,
                  ),
                  onChanged: (v) => setState(() {
                    _bricks = v.isEmpty ? null : int.tryParse(v);
                    _dirty = true;
                  }),
                ),
                // Réservé à l'admin : le serveur n'envoie jamais ces valeurs à un superviseur.
                if (isAdmin && calc != null && day.saved) ...[
                  const Divider(height: 24),
                  KeyValue('Payé à l\'équipe (confection)', fmtMoney(calc.cost)),
                  KeyValue('Valeur de vente', fmtMoney(calc.sale)),
                  KeyValue('Marge', fmtMoney(calc.margin), bold: true, color: okColor),
                ],
              ]),
            ),
          ),

          const SectionTitle('Résumé du jour'),
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                KeyValue('Présents', '$present / ${_members.length}'),
                KeyValue('Absents', '$absent'),
                KeyValue('Non saisis', '$unset', color: unset > 0 ? warnColor : null),
                KeyValue('Identifiés par visage', '$faceCount'),
                if (isAdmin && calc?.share != null) ...[
                  const Divider(height: 20),
                  KeyValue('Part par présent', fmtMoney(calc!.share!), bold: true),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (!complete)
            const InfoBanner(
                icon: Icons.pending_actions,
                color: warnColor,
                text: 'Journée incomplète : présences ou briques non saisies. '
                    'Un non-saisi n\'est pas compté comme absent.')
          else
            const InfoBanner(icon: Icons.check_circle, color: okColor, text: 'Journée complète.'),
        ]),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: GradientButton(
            icon: Icons.save_rounded,
            label: _saving ? 'Enregistrement…' : 'Enregistrer la journée',
            onPressed: editable && _dirty && !_saving ? _save : null,
          ),
        ),
      ),
    ]);
  }

  Widget _memberRow(Member m, bool editable) {
    final bio = m.faceVerified && m.status == Presence.present;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
            Wrap(spacing: 6, children: [
              if (m.isSubstitute) const Pill('Remplaçant', accentSoft),
              if (bio) const Pill('Visage ✓', okColor),
              if (m.status == Presence.unset) const Pill('Non saisi', warnColor),
            ]),
            if (m.status == Presence.absent)
              PopupMenuButton<String?>(
                enabled: editable,
                tooltip: 'Motif d\'absence',
                onSelected: (v) => setState(() {
                  m.absenceReason = v;
                  _dirty = true;
                }),
                itemBuilder: (_) => [
                  for (final e in absenceReasonLabels.entries) PopupMenuItem<String?>(value: e.key, child: Text(e.value)),
                  const PopupMenuItem<String?>(value: null, child: Text('Aucun motif')),
                ],
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        m.absenceReason == null
                            ? 'Motif : à préciser'
                            : 'Motif : ${absenceReasonLabels[m.absenceReason] ?? m.absenceReason}',
                        style: const TextStyle(fontSize: 12, color: accentSoft)),
                    if (editable) const Icon(Icons.arrow_drop_down, size: 18, color: accentSoft),
                  ]),
                ),
              ),
          ]),
        ),
        if (editable)
          _scanning.contains(m.workerId)
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  tooltip: m.faceEnrolled ? 'Identifier par le visage' : 'Visage non enregistré',
                  icon: Icon(Icons.face_retouching_natural,
                      color: bio ? okColor : (m.faceEnrolled ? null : Colors.white24)),
                  onPressed: () => _scan(m),
                ),
        _PresenceToggle(
          value: m.status,
          enabled: editable,
          onChanged: (v) => setState(() {
            m.status = v;
            if (v != Presence.present) m.faceVerified = false;
            if (v != Presence.absent) m.absenceReason = null;
            _dirty = true;
          }),
        ),
        if (m.isSubstitute && editable)
          IconButton(
            tooltip: 'Retirer le remplaçant',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() {
              _members.remove(m);
              _dirty = true;
            }),
          ),
      ]),
    );
  }
}

/// Bascule Présent (vert) / Absent (rouge). Un second appui remet « non saisi ».
class _PresenceToggle extends StatelessWidget {
  final Presence value;
  final bool enabled;
  final ValueChanged<Presence> onChanged;
  const _PresenceToggle({required this.value, required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget btn(String label, Presence target, Color color) {
      final on = value == target;
      return GestureDetector(
        onTap: enabled ? () => onChanged(on ? Presence.unset : target) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 42,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: on ? color : Colors.white.withValues(alpha: 0.07),
            border: Border.all(color: on ? color : Colors.white24),
            boxShadow: on ? [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 14)] : null,
          ),
          child: Text(label,
              style: TextStyle(fontWeight: FontWeight.w900, color: on ? Colors.black87 : Colors.white70)),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      btn('P', Presence.present, okColor),
      const SizedBox(width: 6),
      btn('A', Presence.absent, errColor),
    ]);
  }
}
