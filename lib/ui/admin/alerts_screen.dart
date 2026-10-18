import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/app_store.dart';
import '../../domain/models.dart';
import '../glass.dart';
import '../widgets.dart';

Color _levelColor(String level) => switch (level) {
      'high' => errColor,
      'medium' => warnColor,
      _ => accentSoft,
    };

IconData _levelIcon(String level) => switch (level) {
      'high' => Icons.error_outline,
      'medium' => Icons.warning_amber_rounded,
      _ => Icons.info_outline,
    };

/// Alertes de l'admin : jours sans saisie, journées incomplètes, baisse de production,
/// absences répétées, paie à valider, avances excessives, prix manquants…
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  Future<AlertsView>? _future;

  void _reload() {
    final next = StoreScope.of(context).repo.alerts();
    setState(() {
      _future = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= StoreScope.of(context).repo.alerts();
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<AlertsView>(
      future: _future!,
      onRetry: _reload,
      builder: (context, v) => RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (v.alerts.isEmpty)
            const InfoBanner(icon: Icons.check_circle, color: okColor, text: 'Rien à signaler pour le moment.'),
          for (final a in v.alerts) ...[
            GlassCard(
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(_levelIcon(a.level), color: _levelColor(a.level)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(a.detail, style: const TextStyle(color: Colors.white70)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh, size: 18), label: const Text('Actualiser')),
          ),
        ]),
      ),
    );
  }
}

/// Bandeau du tableau de bord : nombre d'alertes (dont urgentes), ouvre la liste. Silencieux en cas d'erreur.
class AlertsBanner extends StatefulWidget {
  const AlertsBanner({super.key});

  @override
  State<AlertsBanner> createState() => _AlertsBannerState();
}

class _AlertsBannerState extends State<AlertsBanner> {
  Future<AlertsView>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= StoreScope.of(context).repo.alerts();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AlertsView>(
      future: _future,
      builder: (context, snap) {
        final v = snap.data;
        if (v == null || v.count == 0) return const SizedBox.shrink();
        final color = v.high > 0 ? errColor : warnColor;
        final store = StoreScope.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => StoreScope(
                    store: store,
                    child: Scaffold(
                      appBar: AppBar(flexibleSpace: const GlassBar(child: SizedBox.expand()), title: const Text('Alertes')),
                      body: const AlertsScreen(),
                    )))),
            child: InfoBanner(
              icon: v.high > 0 ? Icons.error_outline : Icons.warning_amber_rounded,
              color: color,
              text: '${v.count} alerte${v.count > 1 ? 's' : ''}'
                  '${v.high > 0 ? ' dont ${v.high} urgente${v.high > 1 ? 's' : ''}' : ''} · toucher pour voir',
            ),
          ),
        );
      },
    );
  }
}
