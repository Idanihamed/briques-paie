import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_store.dart';
import '../../domain/models.dart';
import '../glass.dart';
import 'alerts_screen.dart';
import '../supervisor/day_entry_view.dart';
import '../widgets.dart';

/// Vue du jour pour l'admin : qui est là / absent, briques, coût de confection, vente et marge.
/// Tous les montants viennent du serveur.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  late DateTime _date = dateOnly(DateTime.now());
  Future<Overview>? _future;
  Timer? _refresh;

  void _reload() {
    // Bloc (et non « => ») : setState refuse un callback qui renvoie un Future.
    final next = StoreScope.of(context).repo.overview(_date);
    setState(() {
      _future = next;
    });
  }

  @override
  void initState() {
    super.initState();
    // Qui est connecté change en continu : actualisation silencieuse toutes les 30 secondes.
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= StoreScope.of(context).repo.overview(_date);
  }

  void _go(DateTime d) {
    _date = dateOnly(d);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final dateBar = Row(children: [
      IconButton(onPressed: () => _go(_date.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left)),
      Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final d = await showDatePicker(
                context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: today);
            if (d != null) _go(d);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(fmtLongDate(_date),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ),
      ),
      IconButton(
          onPressed: _date.isBefore(today) ? () => _go(_date.add(const Duration(days: 1))) : null,
          icon: const Icon(Icons.chevron_right)),
      IconButton(tooltip: 'Actualiser', onPressed: _reload, icon: const Icon(Icons.refresh)),
    ]);

    return AsyncBody<Overview>(
      future: _future!,
      onRetry: _reload,
      builder: (context, o) {
        final tiles = [
          StatTile(label: 'Présents', value: '${o.present}', icon: Icons.how_to_reg, color: okColor),
          StatTile(label: 'Absents', value: '${o.absent}', icon: Icons.person_off, color: errColor),
          StatTile(label: 'Non saisis', value: '${o.unset}', icon: Icons.help_outline, color: warnColor),
          StatTile(
              label: 'Équipes sans saisie',
              value: '${o.teamsWithoutEntry}',
              icon: Icons.pending_actions,
              color: o.teamsWithoutEntry > 0 ? errColor : okColor),
          StatTile(
              label: 'Ouvriers enregistrés · ${o.workersWithFace} avec visage',
              value: '${o.workersActive}',
              icon: Icons.groups_2,
              color: accent),
          StatTile(
              label: 'Connectés maintenant',
              value: '${o.online.length}',
              icon: Icons.wifi_tethering,
              color: okColor),
        ];

        final missingPrice = o.costRate == null || o.saleRate == null;
        final priceAlert = missingPrice
            ? const Padding(
                padding: EdgeInsets.only(top: 8),
                child: InfoBanner(
                    icon: Icons.sell,
                    color: warnColor,
                    text: 'Prix non défini : ouvrez « Prix & tarifs » pour fixer le prix de confection et le prix de vente.'),
              )
            : const SizedBox.shrink();

        final onlineCard = GlassCard(
          child: o.online.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('Personne n\'est connecté.'))
              : Column(children: [
                  for (final u in o.online)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.circle, size: 12, color: okColor),
                      title: Text(u.isMe ? '${u.name} (vous)' : u.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(u.role == Role.admin
                          ? u.role.label
                          : '${u.role.label}${u.teams != null ? ' · ${u.teams}' : ''}'),
                      trailing: Text(_ago(u.lastSeen), style: const TextStyle(fontSize: 12, color: Colors.white60)),
                    ),
                ]),
        );

        final production = GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              KeyValue('Briques confectionnées', fmtInt(o.bricks), bold: true),
              const Divider(height: 20),
              KeyValue(
                  o.costRate == null
                      ? 'Confection : prix non défini'
                      : 'Confection : ${fmtInt(o.bricks)} × ${fmtInt(o.costRate!)} FCFA',
                  fmtMoney(o.cost)),
              KeyValue(
                  o.saleRate == null
                      ? 'Vente : prix non défini'
                      : 'Vente : ${fmtInt(o.bricks)} × ${fmtInt(o.saleRate!)} FCFA',
                  fmtMoney(o.sale)),
              const Divider(height: 20),
              KeyValue('MARGE (vente − confection)', fmtMoney(o.margin), bold: true, color: okColor),
            ]),
          ),
        );

        final teamCards = [
          if (o.teams.isEmpty)
            const InfoBanner(
                icon: Icons.groups, color: accent, text: 'Aucune équipe. Créez-en une dans l\'onglet « Équipes ».'),
          for (final t in o.teams) ...[_TeamCard(team: t, date: _date, onChanged: _reload), const SizedBox(height: 10)],
        ];

        return LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 900) {
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                dateBar,
                priceAlert,
                const AlertsBanner(),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.75,
                  children: tiles,
                ),
                const SectionTitle('Production du jour'),
                production,
                SectionTitle('Connectés maintenant (${o.online.length})'),
                onlineCard,
                const SectionTitle('Équipes'),
                ...teamCards,
              ]),
            );
          }
          return ListView(padding: const EdgeInsets.fromLTRB(8, 4, 8, 24), children: [
            dateBar,
            priceAlert,
            const AlertsBanner(),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: Row(children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(child: tiles[i]),
                ],
              ]),
            ),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 2,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionTitle('Production du jour'),
                  production,
                  SectionTitle('Connectés maintenant (${o.online.length})'),
                  onlineCard,
                ]),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionTitle('Équipes'),
                  ...teamCards,
                ]),
              ),
            ]),
          ]);
        });
      },
    );
  }
}

/// « à l'instant », « il y a 3 min »…
String _ago(DateTime t) {
  final s = DateTime.now().difference(t).inSeconds;
  if (s < 60) return 'à l\'instant';
  return 'il y a ${s ~/ 60} min';
}

class _TeamCard extends StatelessWidget {
  final OverviewTeam team;
  final DateTime date;
  final VoidCallback onChanged;
  const _TeamCard({required this.team, required this.date, required this.onChanged});

  static String _label(String s) => switch (s) {
        'ok' => 'Complète',
        'zero_production' => 'Production nulle',
        'no_present' => 'Aucun présent',
        'incomplete' => 'Incomplète',
        'no_tariff' => 'Prix manquant',
        _ => 'Non saisi',
      };

  @override
  Widget build(BuildContext context) {
    final t = team;
    final color = switch (t.status) {
      'ok' => okColor,
      'zero_production' || 'incomplete' => warnColor,
      _ => errColor,
    };

    return GlassCard(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('Superviseur : ${t.chief ?? 'non affecté'}${t.interim != null ? ' (remplacé par ${t.interim})' : ''}'
            '${t.saved ? '\n${t.present} présent(s) · ${t.absent} absent(s)' : ''}'),
        trailing: Pill(_label(t.status), color),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!t.saved)
            const Text('Aucune saisie pour cette date.')
          else ...[
            for (final m in t.members)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Icon(
                    switch (m.status) {
                      Presence.present => Icons.check_circle,
                      Presence.absent => Icons.cancel,
                      Presence.unset => Icons.help,
                    },
                    size: 18,
                    color: switch (m.status) {
                      Presence.present => okColor,
                      Presence.absent => errColor,
                      Presence.unset => warnColor,
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(m.fullName)),
                  if (m.faceVerified && m.status == Presence.present)
                    const Icon(Icons.face_retouching_natural, size: 18, color: okColor),
                ]),
              ),
            const Divider(),
            KeyValue('Briques confectionnées', '${t.bricks ?? '—'}'),
            KeyValue('Payé à l\'équipe (confection)', fmtMoney(t.cost)),
            KeyValue('Valeur de vente', fmtMoney(t.sale)),
            KeyValue('Part par présent', t.share == null ? '—' : fmtMoney(t.share!), bold: true),
            if (t.enteredBy != null) Text('Saisi par ${t.enteredBy}', style: Theme.of(context).textTheme.bodySmall),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.edit),
              label: Text(t.saved ? 'Corriger' : 'Saisir'),
              onPressed: () async {
                final store = StoreScope.of(context);
                await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => StoreScope(
                        store: store,
                        child: Scaffold(
                            appBar: AppBar(
                                flexibleSpace: const GlassBar(child: SizedBox.expand()), title: Text(t.name)),
                            body: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 640),
                                child: DayEntryView(initialTeamId: t.teamId, initialDate: date, initialTeamName: t.name),
                              ),
                            )))));
                onChanged();
              },
            ),
          ),
        ],
      ),
    );
  }
}
