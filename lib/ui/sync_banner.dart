import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/app_store.dart';
import '../data/offline.dart';
import '../domain/models.dart';
import 'glass.dart';
import 'widgets.dart';

/// État de la synchronisation pour le superviseur : hors ligne, saisies en attente,
/// conflits à arbitrer et saisies refusées par le serveur.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (store.user?.role != Role.chief) return const SizedBox.shrink();
    final pending = store.pendingCount;
    final attention = store.needsAttention;
    if (store.online && pending == 0 && attention.isEmpty && !store.syncing) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(children: [
        if (!store.online)
          const InfoBanner(
              icon: Icons.cloud_off,
              color: warnColor,
              text: 'Hors ligne. Vous pouvez continuer : vos saisies sont gardées sur l\'appareil '
                  'et envoyées dès que le réseau revient.'),
        if (pending > 0 || store.syncing) ...[
          if (!store.online) const SizedBox(height: 8),
          GlassCard(
            radius: 16,
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            child: Row(children: [
              Icon(store.syncing ? Icons.sync : Icons.schedule, color: accentSoft, size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(store.syncing
                      ? 'Synchronisation…'
                      : '$pending saisie${pending > 1 ? 's' : ''} en attente d\'envoi')),
              if (!store.syncing && store.online) TextButton(onPressed: store.sync, child: const Text('Envoyer')),
            ]),
          ),
        ],
        for (final p in attention) ...[
          const SizedBox(height: 8),
          _AttentionCard(p: p, store: store),
        ],
      ]),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  final PendingSave p;
  final AppStore store;
  const _AttentionCard({required this.p, required this.store});

  @override
  Widget build(BuildContext context) {
    final conflict = p.state == SaveState.conflict;
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(conflict ? Icons.sync_problem : Icons.error_outline, color: conflict ? warnColor : errColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${p.teamName} · ${fmtDate(p.date)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(p.message ?? (conflict ? 'Conflit de synchronisation.' : 'Saisie refusée par le serveur.')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          if (conflict)
            FilledButton(
              onPressed: () => store.keepMine(p),
              child: const Text('Garder ma saisie'),
            ),
          OutlinedButton(
            onPressed: () => store.keepServer(p),
            child: Text(conflict ? 'Garder celle du serveur' : 'Abandonner ma saisie'),
          ),
        ]),
      ]),
    );
  }
}
