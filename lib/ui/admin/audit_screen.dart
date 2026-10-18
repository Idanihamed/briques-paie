import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_store.dart';
import '../../domain/models.dart';
import '../glass.dart';

/// Journal d'audit en lecture seule (la base interdit toute modification ou suppression).
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final List<AuditItem> _items = [];
  int? _next;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_items.isEmpty && _loading && _error == null) _load();
  }

  Future<void> _load({bool more = false}) async {
    final repo = StoreScope.of(context).repo;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _items.clear();
        _error = null;
      }
    });
    try {
      final page = await repo.audit(before: more ? _next : null);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _next = page.next;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length + (_next != null ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          if (i == _items.length) {
            return Center(
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : TextButton(onPressed: () => _load(more: true), child: const Text('Charger plus')),
            );
          }
          final a = _items[i];
          return GlassCard(
            child: ListTile(
              title: Text(a.action,
                  style: TextStyle(fontWeight: FontWeight.w700, color: a.security ? errColor : null)),
              subtitle: Text('${a.object}\n'
                  '${a.oldValue != null ? 'Avant : ${a.oldValue}\n' : ''}'
                  '${a.newValue != null ? 'Après : ${a.newValue}\n' : ''}'
                  '${a.reason != null ? 'Motif : ${a.reason}\n' : ''}'
                  '${a.user} (${a.role}) · ${fmtDateTime(a.at)}'),
              isThreeLine: true,
            ),
          );
        },
      ),
    );
  }
}
