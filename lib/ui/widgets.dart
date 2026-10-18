import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/api_client.dart';
import 'glass.dart';

void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? errColor : null,
    behavior: SnackBarBehavior.floating,
  ));
}

/// Exécute une action serveur et affiche son message d'erreur (droits, verrouillage, validation…).
/// Retourne true si elle a réussi. À utiliser pour toute écriture : le serveur reste l'arbitre.
Future<bool> run(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) toast(context, success);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
    return false;
  }
}

/// Charge des données du serveur : indicateur, erreur lisible avec « Réessayer », puis contenu.
class AsyncBody<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback onRetry;
  const AsyncBody({super.key, required this.future, required this.builder, required this.onRetry});

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            // Actualisation : on garde l'affichage précédent au lieu de faire clignoter un indicateur.
            if (snap.hasData) return builder(context, snap.data as T);
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final msg = snap.error is ApiException ? (snap.error as ApiException).message : 'Erreur inattendue.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_rounded, size: 44, color: Colors.white54),
                  const SizedBox(height: 12),
                  Text(msg, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                      onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
                ]),
              ),
            );
          }
          return builder(context, snap.data as T);
        },
      );
}

class InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const InfoBanner({super.key, required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Row(children: [
          Container(
            width: 5,
            height: 20,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [accentSoft, accentDeep]),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.2))),
          ?trailing,
        ]),
      );
}

/// Tuile de statistique : verre teinté de la couleur du KPI + icône lumineuse.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  const StatTile(
      {super.key, required this.label, required this.value, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? accent;
    return GlassCard(
      tint: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [c.withValues(alpha: 0.16), c.withValues(alpha: 0.04)],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.withValues(alpha: 0.18),
            border: Border.all(color: c.withValues(alpha: 0.45)),
          ),
          child: Icon(icon, color: c, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
            Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
        ),
      ]),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class KeyValue extends StatelessWidget {
  final String k;
  final String v;
  final bool bold;
  final Color? color;
  const KeyValue(this.k, this.v, {super.key, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k)),
          Text(v,
              style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color)),
        ]),
      );
}

class MonthBar extends StatelessWidget {
  final int year;
  final int month;
  final void Function(int year, int month) onChanged;
  const MonthBar({super.key, required this.year, required this.month, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    void go(int delta) {
      final d = DateTime(year, month + delta);
      onChanged(d.year, d.month);
    }

    return Row(children: [
      IconButton(onPressed: () => go(-1), icon: const Icon(Icons.chevron_left)),
      Expanded(
        child: Text(fmtMonth(year, month),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ),
      IconButton(onPressed: () => go(1), icon: const Icon(Icons.chevron_right)),
    ]);
  }
}

Future<String?> askText(BuildContext context,
    {required String title, required String label}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
          controller: c, autofocus: true, maxLines: 2, decoration: InputDecoration(labelText: label)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
          onPressed: () => Navigator.pop(ctx, c.text),
          child: const Text('Confirmer'),
        ),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String ok = 'Confirmer'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}
