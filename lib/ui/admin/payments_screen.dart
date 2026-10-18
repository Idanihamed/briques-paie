import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_store.dart';
import '../../domain/models.dart';
import '../glass.dart';
import '../widgets.dart';

/// Enregistrement manuel des paiements réellement effectués et suivi des soldes exacts.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  late int _y = DateTime.now().year;
  late int _m = DateTime.now().month;
  Future<PaymentsView>? _future;

  void _reload() {
    // Bloc (et non « => ») : setState refuse un callback qui renvoie un Future.
    final next = StoreScope.of(context).repo.payments(_y, _m);
    setState(() {
      _future = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= StoreScope.of(context).repo.payments(_y, _m);
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<PaymentsView>(
      future: _future!,
      onRetry: _reload,
      builder: (context, v) => ListView(padding: const EdgeInsets.all(16), children: [
        MonthBar(
            year: _y,
            month: _m,
            onChanged: (y, m) {
              _y = y;
              _m = m;
              _reload();
            }),
        if (!v.locked)
          const InfoBanner(
              icon: Icons.lock_open,
              color: warnColor,
              text: 'La paie de ce mois n\'est pas validée : les paiements sont désactivés.'),
        const SizedBox(height: 10),
        GlassCard(
          child: v.workers.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('Aucun montant dû ce mois-ci.'))
              : Column(children: [for (final w in v.workers) _row(context, w, v.locked)]),
        ),
      ]),
    );
  }

  Widget _row(BuildContext context, PaymentRow w, bool locked) {
    return ListTile(
      title: Text(w.fullName),
      subtitle: Text('Dû ${fmtMoney(w.due)}${w.advances > 0 ? ' · Avances ${fmtFcfa(w.advances)}' : ''} · Payé ${fmtFcfa(w.paid)}'),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(fmtMoney(w.balance),
            style: TextStyle(fontWeight: FontWeight.w700, color: w.balance.isNegative ? errColor : null)),
        Text(w.balance.isNegative ? 'trop-perçu' : 'solde', style: Theme.of(context).textTheme.bodySmall),
      ]),
      onTap: locked ? () => _pay(context, w) : null,
    );
  }

  Future<void> _pay(BuildContext context, PaymentRow w) async {
    final store = StoreScope.of(context);
    final amount = TextEditingController(text: w.proposed > 0 ? '${w.proposed}' : '');
    var cash = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(w.fullName),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              KeyValue('Solde exact', fmtMoney(w.balance)),
              KeyValue('Montant proposé (arrondi)', fmtFcfa(w.proposed)),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Montant réellement payé (FCFA)'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Espèces')),
                  ButtonSegment(value: false, label: Text('Mobile money')),
                ],
                selected: {cash},
                onSelectionChanged: (s) => setS(() => cash = s.first),
              ),
              const SizedBox(height: 8),
              const Text('Enregistrement manuel : aucun transfert n\'est envoyé.', style: TextStyle(fontSize: 12)),
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
          () => store.repo.pay(
              workerId: w.workerId, year: _y, month: _m, paid: int.tryParse(amount.text) ?? 0, cash: cash),
          success: 'Paiement enregistré.')) {
        _reload();
      }
    }
  }
}
