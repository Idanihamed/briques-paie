import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_store.dart';
import '../../domain/models.dart';
import '../glass.dart';
import '../widgets.dart';
import 'worker_sheet_screen.dart';

/// Classements et tendances (admin) : évolution sur 6 mois, équipes, assiduité des ouvriers, production par jour.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late int _y = DateTime.now().year;
  late int _m = DateTime.now().month;
  Future<Stats>? _future;

  void _reload() {
    final next = StoreScope.of(context).repo.stats(_y, _m);
    setState(() {
      _future = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= StoreScope.of(context).repo.stats(_y, _m);
  }

  static String _pct(double? r) => r == null ? '—' : '${(r * 100).round()} %';

  @override
  Widget build(BuildContext context) {
    return AsyncBody<Stats>(
      future: _future!,
      onRetry: _reload,
      builder: (context, s) => ListView(padding: const EdgeInsets.all(16), children: [
        MonthBar(
            year: _y,
            month: _m,
            onChanged: (y, m) {
              _y = y;
              _m = m;
              _reload();
            }),
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              KeyValue('Briques confectionnées', fmtInt(s.bricks), bold: true),
              KeyValue('Jours de production (équipes)', '${s.workedDays}'),
              KeyValue('Moyenne par jour de saisie', s.avgBricksPerDay == null ? '—' : fmtInt(s.avgBricksPerDay!)),
              if (s.bestDay != null) KeyValue('Meilleur jour', '${fmtDate(s.bestDay!.date)} · ${fmtInt(s.bestDay!.bricks)}'),
              KeyValue('Taux de présence', _pct(s.attendanceRate)),
              const Divider(height: 20),
              KeyValue('Payé aux équipes (confection)', fmtMoney(s.cost)),
              KeyValue('Valeur de vente', fmtMoney(s.sale)),
              KeyValue('Marge', fmtMoney(s.margin), bold: true, color: okColor),
            ]),
          ),
        ),
        const SectionTitle('Évolution sur 6 mois (briques)'),
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: _Bars(
              values: [for (final t in s.trend) t.bricks.toDouble()],
              labels: [for (final t in s.trend) t.label.split(' ').first.substring(0, 3)],
              highlight: s.trend.length - 1,
            ),
          ),
        ),
        const SectionTitle('Production jour par jour'),
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: s.daily.isEmpty
                ? const Text('Aucune saisie ce mois-ci.')
                : _Bars(
                    values: [for (final d in s.daily) d.bricks.toDouble()],
                    labels: [for (final d in s.daily) d.date.substring(8)],
                    compact: true),
          ),
        ),
        const SectionTitle('Classement des équipes'),
        GlassCard(
          child: Column(children: [
            if (s.teams.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucune équipe.')),
            for (var i = 0; i < s.teams.length; i++)
              ListTile(
                leading: _Rank(i + 1),
                title: Text(s.teams[i].name),
                subtitle: Text('${s.teams[i].workedDays} jours · moy. ${s.teams[i].avgBricksPerDay == null ? '—' : fmtInt(s.teams[i].avgBricksPerDay!)}/jour'
                    ' · ${s.teams[i].bricksPerPresent == null ? '—' : fmtInt(s.teams[i].bricksPerPresent!)} par présent'
                    ' · présence ${_pct(s.teams[i].attendanceRate)}'),
                trailing: Text(fmtInt(s.teams[i].bricks), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
          ]),
        ),
        const SectionTitle('Assiduité des ouvriers'),
        GlassCard(
          child: Column(children: [
            if (s.workers.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucune présence saisie.')),
            for (var i = 0; i < s.workers.length; i++)
              ListTile(
                dense: true,
                leading: _Rank(i + 1),
                title: Text(s.workers[i].fullName),
                subtitle: Text('${s.workers[i].present} présent · ${s.workers[i].absent} absent · gagné ${fmtMoney(s.workers[i].earned)}'),
                trailing: Text(_pct(s.workers[i].attendanceRate), style: const TextStyle(fontWeight: FontWeight.w800)),
                onTap: () {
                  final store = StoreScope.of(context);
                  Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => StoreScope(
                          store: store,
                          child: WorkerSheetScreen(workerId: s.workers[i].workerId, name: s.workers[i].fullName))));
                },
              ),
          ]),
        ),
      ]),
    );
  }
}

class _Rank extends StatelessWidget {
  final int n;
  const _Rank(this.n);

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 14,
        backgroundColor: n <= 3 ? accent.withValues(alpha: 0.6) : Colors.white12,
        child: Text('$n', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      );
}

/// Histogramme simple, sans dépendance.
class _Bars extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final int? highlight;
  final bool compact;
  const _Bars({required this.values, required this.labels, this.highlight, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final max = values.fold<double>(0, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 1 : 4),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (!compact && values[i] > 0)
                  Text(fmtInt(values[i].round()), style: const TextStyle(fontSize: 10, color: Colors.white70)),
                Container(
                  height: max == 0 ? 2 : (96 * values[i] / max).clamp(2, 96).toDouble(),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: i == highlight ? accent : accent.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 4),
                Text(labels[i], style: TextStyle(fontSize: compact ? 8 : 11, color: Colors.white60)),
              ]),
            ),
          ),
      ]),
    );
  }
}
