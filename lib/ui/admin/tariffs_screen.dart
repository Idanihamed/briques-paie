import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../data/app_store.dart';
import '../../domain/models.dart';
import '../glass.dart';
import '../widgets.dart';

/// Les deux prix : prix de confection (base de paie) et prix de vente. Historique en ajout seul.
class TariffsScreen extends StatefulWidget {
  const TariffsScreen({super.key});

  @override
  State<TariffsScreen> createState() => _TariffsScreenState();
}

class _TariffsScreenState extends State<TariffsScreen> {
  Future<List<PriceGroup>>? _future;

  void _reload() {
    // Bloc (et non « => ») : setState refuse un callback qui renvoie un Future.
    final next = StoreScope.of(context).repo.tariffs();
    setState(() {
      _future = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= StoreScope.of(context).repo.tariffs();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: AsyncBody<List<PriceGroup>>(
        future: _future!,
        onRetry: _reload,
        builder: (context, groups) => ListView(padding: const EdgeInsets.all(16), children: [
          for (final g in groups) ...[
            SectionTitle(g.label, trailing: Pill('Actuel : ${g.current == null ? '—' : fmtFcfa(g.current!)}', scheme.primary)),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(g.hint, style: Theme.of(context).textTheme.bodySmall),
            ),
            GlassCard(
              child: g.history.isEmpty
                  ? const Padding(padding: EdgeInsets.all(16), child: Text('Aucun prix défini. Ajoutez-en un.'))
                  : Column(children: [
                      for (final t in g.history)
                        ListTile(
                          title: Text('${fmtFcfa(t.value)} / brique'),
                          subtitle: Text('Dès le ${fmtDate(t.effectiveDate)} · ${t.reason}\n'
                              'Par ${t.author} le ${fmtDateTime(t.recordedAt)}'),
                          isThreeLine: true,
                        ),
                    ]),
            ),
          ],
          const SizedBox(height: 80),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau prix'),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final store = StoreScope.of(context);
    var kind = PriceKind.cost;
    var date = dateOnly(DateTime.now());
    final value = TextEditingController();
    final reason = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Nouveau prix'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<PriceKind>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Prix à modifier'),
                items: [
                  const DropdownMenuItem(value: PriceKind.cost, child: Text('Prix de confection')),
                  const DropdownMenuItem(value: PriceKind.sale, child: Text('Prix de vente')),
                ],
                onChanged: (v) => kind = v!,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: value,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Nouveau prix (FCFA par brique)'),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                      context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (d != null) setS(() => date = dateOnly(d));
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date d\'effet'),
                  child: Text(fmtDate(dateKey(date))),
                ),
              ),
              const SizedBox(height: 12),
              TextField(controller: reason, maxLines: 2, decoration: const InputDecoration(labelText: 'Motif (obligatoire)')),
              const SizedBox(height: 12),
              const Text('Les productions antérieures à la date d\'effet gardent l\'ancien prix.', style: TextStyle(fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      if (await run(
          context,
          () => store.repo.addTariff(
              kind: kind, value: int.tryParse(value.text) ?? 0, effectiveDate: date, reason: reason.text),
          success: 'Prix enregistré.')) {
        _reload();
      }
    }
  }
}
