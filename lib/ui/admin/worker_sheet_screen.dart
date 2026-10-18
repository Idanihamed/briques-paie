import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/documents.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_store.dart';
import '../../domain/models.dart';
import '../glass.dart';
import '../widgets.dart';

/// Fiche d'un ouvrier pour un mois : assiduité, motifs d'absence, gains exacts, paiements, jour par jour.
class WorkerSheetScreen extends StatefulWidget {
  final String workerId;
  final String name;
  const WorkerSheetScreen({super.key, required this.workerId, required this.name});

  @override
  State<WorkerSheetScreen> createState() => _WorkerSheetScreenState();
}

class _WorkerSheetScreenState extends State<WorkerSheetScreen> {
  late int _y = DateTime.now().year;
  late int _m = DateTime.now().month;
  Future<WorkerSheet>? _future;

  void _reload() {
    final next = StoreScope.of(context).repo.workerSheet(widget.workerId, _y, _m);
    setState(() {
      _future = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= StoreScope.of(context).repo.workerSheet(widget.workerId, _y, _m);
  }

  Future<void> _addAdvance(WorkerSheet s) async {
    final store = StoreScope.of(context);
    final amount = TextEditingController();
    final note = TextEditingController();
    var cash = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Avance pour ${s.worker.fullName}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Montant (FCFA)'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Espèces')),
                  ButtonSegment(value: false, label: Text('Mobile money')),
                ],
                selected: {cash},
                onSelectionChanged: (v) => setS(() => cash = v.first),
              ),
              const SizedBox(height: 12),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (facultatif)')),
              const SizedBox(height: 8),
              Text('Elle sera déduite du solde de ${fmtMonth(_y, _m)}.', style: const TextStyle(fontSize: 12)),
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
    if (ok == true && mounted) {
      if (await run(
          context,
          () => store.repo.addAdvance(
              workerId: widget.workerId,
              year: _y,
              month: _m,
              amount: int.tryParse(amount.text) ?? 0,
              cash: cash,
              note: note.text.trim().isEmpty ? null : note.text.trim()),
          success: 'Avance enregistrée.')) {
        _reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const GlassBar(child: SizedBox.expand()),
        title: Text(widget.name),
        actions: [
          IconButton(
            tooltip: 'Fiche de paie (PDF)',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () async {
              final s = await _future!;
              await sharePdf(await payslipPdf(s), 'fiche-paie-${s.worker.fullName.replaceAll(' ', '-')}-${s.month}.pdf');
            },
          ),
        ],
      ),
      body: AsyncBody<WorkerSheet>(
        future: _future!,
        onRetry: _reload,
        builder: (context, s) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              MonthBar(
                  year: _y,
                  month: _m,
                  onChanged: (y, m) {
                    _y = y;
                    _m = m;
                    _reload();
                  }),
              if (s.locked)
                const InfoBanner(icon: Icons.lock, color: warnColor, text: 'Paie du mois verrouillée.'),
              GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    KeyValue('Jours présent', '${s.present}'),
                    KeyValue('Jours absent', '${s.absent}'),
                    KeyValue('Non saisis', '${s.unset}', color: s.unset > 0 ? warnColor : null),
                    KeyValue('Taux de présence',
                        s.attendanceRate == null ? '—' : '${(s.attendanceRate! * 100).round()} %'),
                    const Divider(height: 20),
                    KeyValue('Gagné', fmtMoney(s.earned)),
                    if (s.advanced > 0) KeyValue('Avances déduites', fmtFcfa(s.advanced)),
                    KeyValue('Déjà payé', '${fmtInt(s.paid)} FCFA'),
                    KeyValue('Solde à payer', fmtMoney(s.balance), bold: true),
                  ]),
                ),
              ),
              if (s.absent > 0) ...[
                const SectionTitle('Motifs d\'absence'),
                GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(children: [
                      for (final e in s.absences.entries.where((e) => e.value > 0))
                        KeyValue(absenceReasonLabels[e.key] ?? 'Non précisé', '${e.value}'),
                    ]),
                  ),
                ),
              ],
              SectionTitle('Avances',
                  trailing: s.locked
                      ? null
                      : TextButton.icon(
                          onPressed: () => _addAdvance(s),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Ajouter'),
                        )),
              GlassCard(
                child: Column(children: [
                  if (s.advances.isEmpty)
                    const Padding(padding: EdgeInsets.all(16), child: Text('Aucune avance ce mois-ci.')),
                  for (final a in s.advances)
                    ListTile(
                      dense: true,
                      title: Text(fmtFcfa(a.amount)),
                      subtitle: Text('${fmtDate(a.givenAt.substring(0, 10))} · ${a.mode == 'cash' ? 'Espèces' : 'Mobile money'}'
                          '${a.note == null ? '' : ' · ${a.note}'}'),
                      trailing: s.locked
                          ? null
                          : IconButton(
                              tooltip: 'Annuler cette avance',
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () async {
                                final store = StoreScope.of(context);
                                if (await confirm(context, 'Annuler l\'avance ?', '${fmtFcfa(a.amount)} ne sera plus déduit.', ok: 'Annuler l\'avance') &&
                                    context.mounted &&
                                    await run(context, () => store.repo.deleteAdvance(a.id), success: 'Avance annulée.')) {
                                  _reload();
                                }
                              },
                            ),
                    ),
                ]),
              ),
              const SectionTitle('Jour par jour'),
              GlassCard(
                child: Column(children: [
                  if (s.lines.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucune présence ce mois-ci.')),
                  for (final l in s.lines)
                    ListTile(
                      dense: true,
                      title: Text(fmtDate(l.date)),
                      subtitle: Text([
                        if (l.teamName != null) l.teamName!,
                        if (l.isSubstitute) 'remplaçant',
                        if (l.faceVerified) 'visage ✓',
                        if (l.status == Presence.absent && l.absenceReason != null) absenceReasonLabels[l.absenceReason] ?? '',
                      ].join(' · ')),
                      trailing: l.status == Presence.present
                          ? Text(l.share == null ? '—' : fmtMoney(l.share!), style: const TextStyle(fontWeight: FontWeight.w700))
                          : Pill(l.status == Presence.absent ? 'Absent' : 'Non saisi',
                              l.status == Presence.absent ? errColor : warnColor),
                    ),
                ]),
              ),
              if (s.payments.isNotEmpty) ...[
                const SectionTitle('Paiements'),
                GlassCard(
                  child: Column(children: [
                    for (final p in s.payments)
                      ListTile(
                        dense: true,
                        title: Text('${fmtInt(p.paid)} FCFA'),
                        subtitle: Text('${fmtDate(p.paidAt.substring(0, 10))} · ${p.mode}'),
                      ),
                  ]),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
