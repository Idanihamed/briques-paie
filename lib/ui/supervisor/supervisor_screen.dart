import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/app_store.dart';
import '../calendar_view.dart';
import '../glass.dart';
import '../sync_banner.dart';
import 'day_entry_view.dart';

/// Dashboard superviseur : saisie du jour (membres, présent/absent, briques) et calendrier de son équipe.
class SupervisorScreen extends StatefulWidget {
  const SupervisorScreen({super.key});

  @override
  State<SupervisorScreen> createState() => _SupervisorScreenState();
}

class _SupervisorScreenState extends State<SupervisorScreen> {
  int _tab = 0;
  DateTime? _date;
  String? _teamId;
  String? _teamName;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const GlassBar(child: SizedBox.expand()),
        title: Text(store.user!.name),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: store.logout,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              const SyncBanner(),
              Expanded(
                child: _tab == 0
                    ? DayEntryView(
                        key: ValueKey(
                          '${_teamId}_${_date == null ? '' : dateKey(_date!)}',
                        ),
                        initialDate: _date,
                        initialTeamId: _teamId,
                        initialTeamName: _teamName,
                      )
                    : CalendarView(
                        isAdmin: false,
                        onOpenDay: (date, teamId, teamName) => setState(() {
                          _date = date;
                          _teamId = teamId;
                          _teamName = teamName;
                          _tab = 0;
                        }),
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: GlassBar(
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.edit_note), label: 'Saisie'),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Calendrier',
            ),
          ],
        ),
      ),
    );
  }
}
