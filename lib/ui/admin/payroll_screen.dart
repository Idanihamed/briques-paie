import 'package:flutter/material.dart';

import '../../core/documents.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_store.dart';
import '../../domain/models.dart';
import '../glass.dart';
import '../widgets.dart';

/// Calcul (fait par le serveur), validation, verrouillage et déverrouillage de la paie mensuelle.
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  late int _y = DateTime.now().year;
  late int _m = DateTime.now().month;
  Future<PayrollView>? _future;

  void _reload() {
    // Bloc (et non « => ») : setState refuse un callback qui renvoie un Future.
    final next = StoreScope.of(context).repo.payroll(_y, _m);
    setState(() {
      _future = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= StoreScope.of(context).repo.payroll(_y, _m);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return AsyncBody<PayrollView>(
      future: _future!,
      onRetry: _reload,
      builder: (context, p) {
        final blocking = p.anomalies.where((a) => a.blocking).toList();
        final warnings = p.anomalies.where((a) => !a.blocking).toList();
        final current = p.versions.firstOrNull;

        return ListView(padding: const EdgeInsets.all(16), children: [
          MonthBar(
              year: _y,
              month: _m,
              onChanged: (y, m) {
                _y = y;
                _m = m;
                _reload();
              }),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async =>
                  sharePdf(await payrollPdf(p), 'etat-de-paie-${p.month}.pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('État de paie (PDF)'),
            ),
          ),
          Row(children: [
            p.locked ? Pill('Verrouillée · v${p.currentVersion}', okColor) : const Pill('Paie provisoire', warnColor),
            const Spacer(),
            Text(fmtMoney(p.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ]),
          if (p.anomalies.isNotEmpty) ...[
            SectionTitle('Anomalies (${p.anomalies.length})'),
            GlassCard(
              child: Column(children: [
                for (final a in [...blocking, ...warnings])
                  ListTile(
                    dense: true,
                    leading: Icon(a.blocking ? Icons.block : Icons.warning_amber, color: a.blocking ? errColor : warnColor),
                    title: Text(a.message),
                  ),
              ]),
            ),
          ],
          const SectionTitle('Par équipe'),
          GlassCard(
            child: p.teams.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('Aucune équipe.'))
                : Column(children: [
                    for (final t in p.teams)
                      ListTile(
                        title: Text(t.name),
                        trailing: Text(fmtMoney(t.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  ]),
          ),
          const SectionTitle('Par ouvrier (montants exacts)'),
          GlassCard(
            child: p.workers.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('Aucune part attribuée ce mois-ci.'))
                : Column(children: [
                    for (final w in p.workers)
                      ListTile(
                        title: Text(w.fullName),
                        subtitle: Text('${w.days} jour(s) travaillé(s)'),
                        trailing: Text(fmtMoney(w.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                        onTap: () => _detail(context, w),
                      ),
                  ]),
          ),
          const SectionTitle('Validation'),
          if (blocking.isNotEmpty)
            const InfoBanner(
                icon: Icons.block, color: errColor, text: 'Corrigez les anomalies bloquantes avant de valider.'),
          const SizedBox(height: 10),
          if (!p.locked)
            GradientButton(
              icon: Icons.lock,
              label: 'Valider et verrouiller la paie',
              onPressed: blocking.isEmpty
                  ? () async {
                      if (await confirm(context, 'Valider et verrouiller ?',
                              'Total : ${fmtMoney(p.total)}.\nAucune modification ordinaire ne sera possible ensuite.',
                              ok: 'Valider') &&
                          context.mounted &&
                          await run(context, () => store.repo.validatePayroll(_y, _m), success: 'Paie validée et verrouillée.')) {
                        _reload();
                      }
                    }
                  : null,
            )
          else
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () async {
                final r = await askText(context, title: 'Déverrouiller la paie', label: 'Motif (obligatoire)');
                if (r != null && context.mounted &&
                    await run(context, () => store.repo.unlockPayroll(_y, _m, r), success: 'Paie déverrouillée.')) {
                  _reload();
                }
              },
              icon: const Icon(Icons.lock_open),
              label: const Text('Déverrouiller (motif obligatoire)'),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () async {
              try {
                final csv = await store.repo.payrollCsv(_y, _m);
                await Clipboard.setData(ClipboardData(text: csv));
                if (context.mounted) toast(context, 'CSV copié dans le presse-papiers.');
              } catch (e) {
                if (context.mounted) toast(context, e.toString(), error: true);
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copier le CSV de la paie'),
          ),
          if (p.versions.isNotEmpty) ...[
            const SectionTitle('Historique des versions'),
            GlassCard(
              child: Column(children: [
                for (final v in p.versions)
                  ListTile(
                    leading: Icon(v.locked ? Icons.lock : Icons.history, color: v.locked ? okColor : null),
                    title: Text('Version ${v.version} · ${fmtMoney(v.total)}'),
                    subtitle: Text('Validée par ${v.validatedBy} le ${fmtDateTime(v.validatedAt)}'
                        '${v.unlockedAt != null ? '\nDéverrouillée par ${v.unlockedBy} le ${fmtDateTime(v.unlockedAt!)} : ${v.unlockReason}' : ''}'),
                  ),
              ]),
            ),
            if (current == null) const SizedBox.shrink(),
          ],
          const SizedBox(height: 24),
        ]);
      },
    );
  }

  void _detail(BuildContext context, PayrollWorker w) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, controller) => ListView(controller: controller, padding: const EdgeInsets.all(16), children: [
          Text(w.fullName, style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('${w.days} jour(s) · Total exact ${fmtMoney(w.total)}'),
          const Divider(height: 24),
          for (final l in w.lines)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(fmtLongDate(parseDate(l.date))),
              trailing: Text(fmtMoney(l.share)),
            ),
        ]),
      ),
    );
  }
}
