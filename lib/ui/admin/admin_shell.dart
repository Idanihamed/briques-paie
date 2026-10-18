import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/app_store.dart';
import '../../domain/models.dart';
import '../glass.dart';
import '../supervisor/day_entry_view.dart';
import '../calendar_view.dart';
import 'alerts_screen.dart';
import 'audit_screen.dart';
import 'data_screen.dart';
import 'invoices_screen.dart';
import 'period_screen.dart';
import 'overview_screen.dart';
import 'payments_screen.dart';
import 'payroll_screen.dart';
import 'stats_screen.dart';
import 'tariffs_screen.dart';
import 'teams_screen.dart';

class _Page {
  final String title;
  final IconData icon;
  final IconData selectedIcon;
  final Widget body;
  const _Page(this.title, this.icon, this.selectedIcon, this.body);
}

/// Dashboard admin, partagé par les responsables (droits vérifiés par le serveur).
/// - Téléphone : barre de navigation du bas (3 entrées) + menu « Plus ».
/// - Web / tablette (≥ 900 px) : barre latérale en verre, toutes les pages accessibles directement.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _tab = 0;

  static const wideBreakpoint = 900.0;

  late final List<_Page> _pages = const [
    _Page('Tableau de bord', Icons.dashboard_outlined, Icons.dashboard, OverviewScreen()),
    _Page('Calendrier', Icons.calendar_month_outlined, Icons.calendar_month, _AdminCalendar()),
    _Page('Équipes & superviseurs', Icons.groups_outlined, Icons.groups, TeamsScreen()),
    _Page('Statistiques', Icons.insights_outlined, Icons.insights, StatsScreen()),
    _Page('Paie mensuelle', Icons.calculate_outlined, Icons.calculate, PayrollScreen()),
    _Page('Alertes', Icons.notifications_outlined, Icons.notifications, AlertsScreen()),
    _Page('Factures', Icons.receipt_long_outlined, Icons.receipt_long, InvoicesScreen()),
    _Page('Paie sur période', Icons.date_range_outlined, Icons.date_range, PeriodScreen()),
    _Page('Paiements', Icons.payments_outlined, Icons.payments, PaymentsScreen()),
    _Page('Prix & tarifs', Icons.sell_outlined, Icons.sell, TariffsScreen()),
    _Page('Import & sauvegarde', Icons.cloud_sync_outlined, Icons.cloud_sync, DataScreen()),
    _Page('Journal d\'audit', Icons.fact_check_outlined, Icons.fact_check, AuditScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final tab = _tab.clamp(0, _pages.length - 1);
    return LayoutBuilder(
        builder: (context, box) => box.maxWidth >= wideBreakpoint ? _wide(store, tab) : _compact(store, tab));
  }

  // ───────── Web / grand écran ─────────
  Widget _wide(AppStore store, int tab) {
    final u = store.user!;
    return Scaffold(
      body: Row(children: [
        SizedBox(
          width: 270,
          child: GlassBar(
            child: SafeArea(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Row(children: [
                    Image.asset('assets/logo.png', width: 46, height: 46, semanticLabel: 'Association Bayiir Mêtba'),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: GradientText('Briques & Paie',
                          gradient: LinearGradient(colors: [Colors.white, accentSoft]),
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
                Expanded(
                  child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                    for (var i = 0; i < _pages.length; i++)
                      _SideItem(page: _pages[i], selected: i == tab, onTap: () => setState(() => _tab = i)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: GlassCard(
                    radius: 18,
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      const CircleAvatar(radius: 18, backgroundColor: accentDeep, child: Icon(Icons.person, size: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(u.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(u.role.label, style: const TextStyle(fontSize: 12, color: Colors.white60)),
                        ]),
                      ),
                      IconButton(
                        tooltip: 'Se déconnecter',
                        icon: const Icon(Icons.logout, size: 20),
                        onPressed: store.logout,
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
        Expanded(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 28, 32, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_pages[tab].title,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    // Une page à la fois : chaque onglet recharge ses données du serveur à l'ouverture.
                    child: KeyedSubtree(key: ValueKey(tab), child: _pages[tab].body),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ───────── Téléphone ─────────
  Widget _compact(AppStore store, int tab) {
    final main = _pages.take(3).toList();
    final more = _pages.skip(3).toList();
    final isMore = tab >= 3;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const GlassBar(child: SizedBox.expand()),
        title: Text(isMore ? 'Plus' : _pages[tab].title),
        actions: [IconButton(tooltip: 'Se déconnecter', icon: const Icon(Icons.logout), onPressed: store.logout)],
      ),
      body: isMore ? _MoreList(store: store, pages: more) : KeyedSubtree(key: ValueKey(tab), child: _pages[tab].body),
      bottomNavigationBar: GlassBar(
        child: NavigationBar(
          selectedIndex: isMore ? 3 : tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            for (final p in main)
              NavigationDestination(icon: Icon(p.icon), selectedIcon: Icon(p.selectedIcon), label: p.title.split(' ').first),
            const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Plus'),
          ],
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  final _Page page;
  final bool selected;
  final VoidCallback onTap;
  const _SideItem({required this.page, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: selected
                    ? LinearGradient(colors: [accent.withValues(alpha: 0.55), accentDeep.withValues(alpha: 0.35)])
                    : null,
                border: selected ? Border.all(color: accent.withValues(alpha: 0.5)) : null,
              ),
              child: Row(children: [
                Icon(selected ? page.selectedIcon : page.icon,
                    color: selected ? Colors.white : Colors.white70, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(page.title,
                      style: TextStyle(
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                          color: selected ? Colors.white : Colors.white70)),
                ),
              ]),
            ),
          ),
        ),
      );
}

class _MoreList extends StatelessWidget {
  final AppStore store;
  final List<_Page> pages;
  const _MoreList({required this.store, required this.pages});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final p in pages) ...[
        GlassCard(
          child: ListTile(
            leading: Icon(p.selectedIcon),
            title: Text(p.title),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => StoreScope(
                    store: store,
                    child: Scaffold(
                        appBar: AppBar(flexibleSpace: const GlassBar(child: SizedBox.expand()), title: Text(p.title)),
                        body: p.body)))),
          ),
        ),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 8),
      Text('Connecté : ${store.user!.name} · ${store.user!.role.label}', style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

/// Calendrier admin : un clic sur « Ouvrir la saisie » ouvre la journée de l'équipe pour correction.
class _AdminCalendar extends StatelessWidget {
  const _AdminCalendar();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return CalendarView(
      isAdmin: true,
      onOpenDay: (date, teamId, teamName) => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => StoreScope(
              store: store,
              child: Scaffold(
                appBar: AppBar(flexibleSpace: const GlassBar(child: SizedBox.expand()), title: Text(teamName)),
                body: DayEntryView(initialDate: date, initialTeamId: teamId, initialTeamName: teamName),
              )))),
    );
  }
}
