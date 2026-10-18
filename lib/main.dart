import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'data/api_client.dart';
import 'data/app_store.dart';
import 'data/offline.dart';
import 'domain/models.dart';
import 'ui/admin/admin_shell.dart';
import 'ui/glass.dart';
import 'ui/login_screen.dart';
import 'ui/supervisor/supervisor_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LocalStore? local;
  try {
    local = await LocalStore.open();
  } catch (_) {/* stockage indisponible : l'application reste utilisable en ligne */}
  final store = AppStore(ApiClient(baseUrl: apiBaseUrl), local: local);
  if (!kIsWeb) store.loadSavedServerUrl(); // sur le web, l'API est à la même adresse que la page
  runApp(BriquesApp(store: store));
}

class BriquesApp extends StatelessWidget {
  final AppStore store;
  const BriquesApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: store,
      child: MaterialApp(
        title: 'Briques & Paie',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        themeMode: ThemeMode.dark,
        builder: (context, child) => AuroraBackground(child: child!),
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _Gate(),
      ),
    );
  }
}

/// Aiguille vers l'espace Superviseur ou Admin selon le rôle, et verrouille
/// la session après 5 minutes d'inactivité.
class _Gate extends StatefulWidget {
  const _Gate();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  Timer? _timer;

  void _touch(AppStore store) {
    _timer?.cancel();
    if (store.user == null) return;
    _timer = Timer(idleLockAfter, () => store.logout(message: 'Session verrouillée après inactivité.'));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final u = store.user;
    if (u == null) _timer?.cancel();
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touch(store),
      child: u == null
          ? const LoginScreen()
          : u.role == Role.chief
              ? const SupervisorScreen()
              : const AdminShell(),
    );
  }
}
