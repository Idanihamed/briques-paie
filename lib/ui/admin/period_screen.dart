import 'package:flutter/material.dart';

import '../../core/documents.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_store.dart';
import '../../domain/models.dart';
import '../glass.dart';
import '../widgets.dart';

/// Paie sur une période libre (semaine, quinzaine…), à titre d'information.
/// Le règlement officiel reste la paie mensuelle validée.
class PeriodScreen extends StatefulWidget {
  const PeriodScreen({super.key});

  @override
  State<PeriodScreen> createState() => _PeriodScreenState();
}

class _PeriodScreenState extends State<PeriodScreen> {
  late DateTime _to = dateOnly(DateTime.now());
  late DateTime _from = _to.subtract(const Duration(days: 6));
  Future<PeriodReport>? _future;

  void _reload() {
    final next = StoreScope.of(context).repo.period(_from, _to);
    setState(() {
      _future = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= StoreScope.of(context).repo.period(_from, _to);
  }

  Future<void> _pick(bool isFrom) async {
    final d = await showDatePicker(
        context: context, initialDate: isFrom ? _from : _to, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d == null) return;
    if (isFrom) {
      _from = dateOnly(d);
      if (_to.isBefore(_from)) _to = _from;
    } else {
      _to = dateOnly(d);
      if (_to.isBefore(_from)) _from = _to;
    }
    _reload();
  }

  void _preset(int days) {
    _to = dateOnly(DateTime.now());
    _from = _to.subtract(Duration(days: days - 1));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<PeriodReport>(
      future: _future!,
      onRetry: _reload,
      builder: (context, r) => ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(
            child: InkWell(
              onTap: () => _pick(true),
              child: InputDecorator(decoration: const InputDecoration(labelText: 'Du'), child: Text(fmtDate(dateKey(_from)))),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => _pick(false),
              child: InputDecorator(decoration: const InputDecoration(labelText: 'Au'), child: Text(fmtDate(dateKey(_to)))),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          ActionChip(label: const Text('7 derniers jours'), onPressed: () => _preset(7)),
          ActionChip(label: const Text('15 derniers jours'), onPressed: () => _preset(15)),
          ActionChip(label: const Text('30 derniers jours'), onPressed: () => _preset(30)),
        ]),
        const SizedBox(height: 12),
        const InfoBanner(
            icon: Icons.info_outline,
            color: accent,
            text: 'Calcul à titre d\'information : mêmes règles que la paie mensuelle. '
                'Le règlement officiel (validation, verrouillage, paiements) se fait par mois.'),
        const SizedBox(height: 12),
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              KeyValue('Briques confectionnées', fmtInt(r.bricks)),
              KeyValue('Payé aux équipes (confection)', fmtMoney(r.cost), bold: true),
              KeyValue('Valeur de vente', fmtMoney(r.sale)),
              KeyValue('Marge', fmtMoney(r.margin), color: okColor),
              if (r.incompleteDays > 0)
                KeyValue('Journées incomplètes (non comptées)', '${r.incompleteDays}', color: warnColor),
            ]),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async => sharePdf(await periodPdf(r), 'paie-${dateKey(_from)}-${dateKey(_to)}.pdf'),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Exporter en PDF'),
          ),
        ),
        const SectionTitle('Par équipe'),
        GlassCard(
          child: Column(children: [
            if (r.teams.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucune production sur la période.')),
            for (final t in r.teams) ListTile(dense: true, title: Text(t.name), trailing: Text(fmtMoney(t.total))),
          ]),
        ),
        const SectionTitle('Par ouvrier'),
        GlassCard(
          child: Column(children: [
            if (r.workers.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucun ouvrier payé sur la période.')),
            for (final w in r.workers)
              ListTile(
                dense: true,
                title: Text(w.fullName),
                subtitle: Text('${w.days} jour${w.days > 1 ? 's' : ''}'),
                trailing: Text(fmtMoney(w.total), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
      ]),
    );
  }
}
