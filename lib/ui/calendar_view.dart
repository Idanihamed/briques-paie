import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/app_store.dart';
import '../domain/models.dart';
import 'glass.dart';
import 'widgets.dart';

/// Calendrier de travail d'un mois : pour chaque jour, l'état de la saisie des équipes
/// (complet, incomplet, manquant, à saisir) ou la raison pour laquelle le jour n'est pas travaillé.
///
/// Admin : peut déclarer des jours non travaillés (repos, férié, intempérie, panne…), des jours
/// travaillés à titre exceptionnel, et choisir les jours de repos hebdomadaires.
/// Superviseur : lecture seule, sur ses équipes ; un clic ouvre la saisie du jour.
class CalendarView extends StatefulWidget {
  final bool isAdmin;
  final void Function(DateTime date, String teamId, String teamName) onOpenDay;
  const CalendarView({super.key, required this.isAdmin, required this.onOpenDay});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  late int _y = DateTime.now().year;
  late int _m = DateTime.now().month;
  String? _teamId; // null = toutes les équipes (résumé)
  Future<CalendarMonth>? _future;

  void _reload() {
    final next = StoreScope.of(context).repo.calendar(_y, _m);
    setState(() {
      _future = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= StoreScope.of(context).repo.calendar(_y, _m);
  }

  // Couleur / icône selon l'état. Un jour non travaillé garde une teinte neutre.
  static Color _color(String state) => switch (state) {
        'complete' => okColor,
        'incomplete' => warnColor,
        'missing' => errColor,
        'pending' => accent,
        _ => Colors.white38,
      };

  static IconData _kindIcon(String kind) => switch (kind) {
        'holiday' => Icons.celebration_outlined,
        'weather' => Icons.thunderstorm_outlined,
        'breakdown' => Icons.build_outlined,
        'other' => Icons.block,
        _ => Icons.bedtime_outlined,
      };

  static String _stateLabel(String state) => switch (state) {
        'complete' => 'Saisie complète',
        'incomplete' => 'Saisie incomplète',
        'missing' => 'Aucune saisie',
        'pending' => 'À saisir aujourd\'hui',
        'future' => 'À venir',
        _ => 'Non travaillé',
      };

  /// Plus la valeur est grande, plus l'état demande d'attention (pour le résumé « toutes équipes »).
  static const _severity = {'missing': 5, 'incomplete': 4, 'pending': 3, 'complete': 2, 'future': 1, 'off': 0};

  CalendarCell _summary(CalendarDay d, List<CalendarCell> cells) =>
      cells.reduce((a, b) => (_severity[b.state] ?? 0) > (_severity[a.state] ?? 0) ? b : a);

  @override
  Widget build(BuildContext context) {
    return AsyncBody<CalendarMonth>(
      future: _future!,
      onRetry: _reload,
      builder: (context, cal) {
        if (cal.teams.isEmpty) {
          return const Center(
              child: Padding(padding: EdgeInsets.all(24), child: Text('Aucune équipe pour le moment.')));
        }
        // Si l'équipe choisie n'existe plus dans ce mois, on revient au résumé.
        final selected = cal.teams.any((t) => t.id == _teamId) ? _teamId : null;
        final effective = selected ?? (widget.isAdmin ? null : cal.teams.first.id);

        return ListView(padding: const EdgeInsets.all(16), children: [
          MonthBar(
              year: _y,
              month: _m,
              onChanged: (y, m) {
                _y = y;
                _m = m;
                _reload();
              }),
          Row(children: [
            if (cal.teams.length > 1 || widget.isAdmin)
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: effective,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Équipe'),
                  items: [
                    if (widget.isAdmin) const DropdownMenuItem<String?>(value: null, child: Text('Toutes les équipes')),
                    for (final t in cal.teams) DropdownMenuItem<String?>(value: t.id, child: Text(t.name)),
                  ],
                  onChanged: (v) => setState(() => _teamId = v),
                ),
              ),
            if (widget.isAdmin) ...[
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
                onPressed: () => _editRestDays(cal),
                icon: const Icon(Icons.event_repeat),
                label: const Text('Jours de repos'),
              ),
            ],
          ]),
          const SizedBox(height: 4),
          Text('Repos hebdomadaire : ${_restText(cal.restWeekdays)}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          _grid(cal, effective),
          const SizedBox(height: 12),
          const Wrap(spacing: 14, runSpacing: 6, children: [
            _Legend('Complet', okColor),
            _Legend('Incomplet', warnColor),
            _Legend('Manquant', errColor),
            _Legend('À saisir', accent),
            _Legend('Non travaillé', Colors.white38),
          ]),
          if (widget.isAdmin)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: GradientButton(
                icon: Icons.event_busy,
                label: 'Déclarer des jours non travaillés',
                onPressed: () => _markDialog(cal, DateTime(_y, _m, 1), effective),
              ),
            ),
        ]);
      },
    );
  }

  static const _dayNames = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];

  String _restText(List<int> rest) {
    if (rest.isEmpty) return 'aucun';
    final sorted = [...rest]..sort((a, b) => (a == 0 ? 7 : a).compareTo(b == 0 ? 7 : b));
    return sorted.map((d) => _dayNames[d]).join(', ');
  }

  Widget _grid(CalendarMonth cal, String? teamId) {
    final first = DateTime(_y, _m, 1);
    final offset = (first.weekday - 1) % 7; // lundi = 0
    final cells = <Widget>[
      for (final n in ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'])
        Center(child: Text(n, style: const TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w700))),
      for (var i = 0; i < offset; i++) const SizedBox.shrink(),
      for (final d in cal.days) _dayCell(cal, d, teamId),
    ];
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.clamp(0, 760).toDouble();
      return Center(
        child: SizedBox(
          width: w,
          child: GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 0.82,
            children: cells,
          ),
        ),
      );
    });
  }

  Widget _dayCell(CalendarMonth cal, CalendarDay d, String? teamId) {
    final all = d.cells;
    final shown = teamId == null ? all : all.where((c) => c.teamId == teamId).toList();
    final c = teamId == null ? _summary(d, shown) : shown.first;
    final color = _color(c.state);
    final isToday = d.date == cal.today;
    final off = c.state == 'off';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _dayDetails(cal, d, teamId),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: color.withValues(alpha: off ? 0.07 : 0.16),
          border: Border.all(color: isToday ? accent : color.withValues(alpha: off ? 0.2 : 0.55), width: isToday ? 2 : 1),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${int.parse(d.date.substring(8))}',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: off ? Colors.white54 : Colors.white)),
          Align(
            alignment: Alignment.bottomRight,
            child: switch (c.state) {
              'off' => Icon(_kindIcon(c.day.kind), size: 16, color: Colors.white38),
              'complete' => const Icon(Icons.check_circle, size: 16, color: okColor),
              'incomplete' => const Icon(Icons.timelapse, size: 16, color: warnColor),
              'missing' => const Icon(Icons.error_outline, size: 16, color: errColor),
              'pending' => const Icon(Icons.edit_calendar, size: 16, color: accent),
              _ => const SizedBox.shrink(),
            },
          ),
        ]),
      ),
    );
  }

  // ───────── Détail d'un jour ─────────

  Future<void> _dayDetails(CalendarMonth cal, CalendarDay d, String? teamId) async {
    final date = parseDate(d.date);
    final names = {for (final t in cal.teams) t.id: t.name};
    final cells = teamId == null ? d.cells : d.cells.where((c) => c.teamId == teamId).toList();
    final canOpen = d.date.compareTo(cal.today) <= 0;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fmtLongDate(date), style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final c in cells) ...[
                GlassCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(names[c.teamId] ?? '', style: const TextStyle(fontWeight: FontWeight.w700))),
                      Pill(_stateLabel(c.state), _color(c.state)),
                    ]),
                    if (!c.day.working)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                            '${c.day.describe}${c.day.source == 'weekly' ? ' (repos hebdomadaire)' : c.day.source == 'team' ? ' (cette équipe)' : c.day.source == 'global' ? ' (toutes les équipes)' : ''}',
                            style: const TextStyle(color: Colors.white70)),
                      )
                    else if (c.bricks != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('${fmtInt(c.bricks!)} briques confectionnées', style: const TextStyle(color: Colors.white70)),
                      ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      if (c.day.working && canOpen)
                        TextButton.icon(
                          icon: const Icon(Icons.edit_calendar, size: 18),
                          label: Text(c.state == 'complete' ? 'Voir / corriger' : 'Ouvrir la saisie'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            widget.onOpenDay(date, c.teamId, names[c.teamId] ?? '');
                          },
                        ),
                      if (widget.isAdmin && (c.day.source == 'team' || c.day.source == 'global'))
                        TextButton.icon(
                          icon: const Icon(Icons.restore, size: 18),
                          label: const Text('Rétablir le calendrier habituel'),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final store = StoreScope.of(context);
                            if (await run(
                                context,
                                () => store.repo.clearDays(
                                    from: date, teamId: c.day.source == 'team' ? c.teamId : null),
                                success: 'Calendrier rétabli.')) {
                              _reload();
                            }
                          },
                        ),
                    ]),
                  ]),
                ),
                const SizedBox(height: 8),
              ],
              if (widget.isAdmin)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  icon: const Icon(Icons.event_busy),
                  label: const Text('Déclarer ce jour non travaillé…'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _markDialog(cal, date, teamId);
                  },
                ),
            ]),
          ),
        ),
      ),
    );
  }

  // ───────── Déclarer des jours (admin) ─────────

  Future<void> _markDialog(CalendarMonth cal, DateTime start, String? teamId) async {
    final store = StoreScope.of(context);
    var kind = 'holiday';
    var from = dateOnly(start);
    var to = dateOnly(start);
    String? scope = teamId;
    final reason = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Future<void> pick(bool isFrom) async {
            final d = await showDatePicker(
                context: ctx, initialDate: isFrom ? from : to, firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (d == null) return;
            setS(() {
              if (isFrom) {
                from = dateOnly(d);
                if (to.isBefore(from)) to = from;
              } else {
                to = dateOnly(d);
                if (to.isBefore(from)) from = to;
              }
            });
          }

          return AlertDialog(
            title: const Text('Déclarer des jours'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Statut'),
                    items: [
                      for (final e in dayKindLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setS(() => kind = v!),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => pick(true),
                        child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Du'), child: Text(fmtDate(dateKey(from)))),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () => pick(false),
                        child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Au'), child: Text(fmtDate(dateKey(to)))),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: scope,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Équipes concernées'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Toutes les équipes')),
                      for (final t in cal.teams) DropdownMenuItem<String?>(value: t.id, child: Text(t.name)),
                    ],
                    onChanged: (v) => setS(() => scope = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    decoration: const InputDecoration(labelText: 'Motif (ex. Tabaski, pluie, panne du malaxeur)'),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                      'Un jour déjà saisi ne peut pas être déclaré non travaillé. '
                      'Les jours non travaillés ne comptent pas comme « sans saisie » dans la paie.',
                      style: TextStyle(fontSize: 12, color: Colors.white60)),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true && mounted) {
      if (await run(
          context,
          () => store.repo.markDays(
              from: from,
              to: to,
              teamId: scope,
              kind: kind,
              reason: reason.text.trim().isEmpty ? null : reason.text.trim()),
          success: 'Calendrier mis à jour.')) {
        _reload();
      }
    }
  }

  Future<void> _editRestDays(CalendarMonth cal) async {
    final store = StoreScope.of(context);
    final selected = {...cal.restWeekdays};
    const order = [1, 2, 3, 4, 5, 6, 0];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Jours de repos hebdomadaires'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ces jours ne sont pas travaillés, sauf exception déclarée dans le calendrier.'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in order)
                FilterChip(
                  label: Text(_dayNames[d]),
                  selected: selected.contains(d),
                  onSelected: (v) => setS(() => v ? selected.add(d) : selected.remove(d)),
                ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      if (await run(context, () => store.repo.setRestWeekdays(selected.toList()..sort()),
          success: 'Jours de repos enregistrés.')) {
        _reload();
      }
    }
  }
}

class _Legend extends StatelessWidget {
  final String label;
  final Color color;
  const _Legend(this.label, this.color);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: color.withValues(alpha: 0.3),
            border: Border.all(color: color),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ]);
}
