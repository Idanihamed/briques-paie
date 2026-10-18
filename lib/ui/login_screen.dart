import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/app_store.dart';
import '../data/api_client.dart';
import 'glass.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  String _pin = '';
  String? _error;

  bool _busy = false;

  Future<void> _submit(AppStore store) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await store.login(_name.text, _pin);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _pin = '';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Changer l'adresse du serveur (ex. quand l'ordinateur change de réseau Wi-Fi).
  Future<void> _editServer(AppStore store) async {
    final c = TextEditingController(text: store.serverUrl);
    String? err;
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Adresse du serveur'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
                "Tapez l'adresse de l'ordinateur qui fait tourner le serveur, puis :3000. "
                'Exemple : 192.168.1.132:3000. Le téléphone doit être sur le même Wi-Fi.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: 'Adresse', errorText: err),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
              onPressed: () {
                final n = AppStore.normalizeServerUrl(c.text);
                if (n == null) return setS(() => err = 'Adresse invalide (ex. 192.168.1.132:3000).');
                Navigator.pop(ctx, n);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (url != null) {
      await store.setServerUrl(url);
      if (mounted) setState(() => _error = null);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(children: [
                // Logo lumineux
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.40), blurRadius: 34, spreadRadius: 1)],
                  ),
                  child: Image.asset('assets/logo.png', semanticLabel: 'Association Bayiir Mêtba'),
                ),
                const SizedBox(height: 18),
                const GradientText('Briques & Paie',
                    gradient: LinearGradient(colors: [Colors.white, accentSoft]),
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                const Text('Production · Présences · Paie',
                    style: TextStyle(color: Colors.white60, letterSpacing: 1.2, fontSize: 12)),
                const SizedBox(height: 26),
                GlassCard(
                  radius: 30,
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                  child: Column(children: [
                    TextField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(
                          labelText: 'Votre nom', prefixIcon: Icon(Icons.person_outline)),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                    const SizedBox(height: 22),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (var i = 0; i < 6; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: i < _pin.length ? 18 : 14,
                          height: i < _pin.length ? 18 : 14,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: i < _pin.length ? brandGradient : null,
                            border: i < _pin.length ? null : Border.all(color: Colors.white38),
                            boxShadow: i < _pin.length
                                ? [BoxShadow(color: accent.withValues(alpha: 0.55), blurRadius: 8)]
                                : null,
                          ),
                        ),
                    ]),
                    SizedBox(
                      height: 40,
                      child: Center(
                          child: Text(_error ?? '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: errColor, fontWeight: FontWeight.w600))),
                    ),
                    _Keypad(
                      onDigit: (d) => setState(() {
                        if (_pin.length < 6) _pin += d;
                        _error = null;
                      }),
                      onBack: () => setState(() {
                        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
                      }),
                    ),
                    const SizedBox(height: 18),
                    GradientButton(
                      icon: Icons.lock_open_rounded,
                      label: _busy ? 'Connexion…' : 'Se connecter',
                      onPressed: !_busy && _name.text.trim().isNotEmpty && _pin.length >= 4
                          ? () => _submit(store)
                          : null,
                    ),
                  ]),
                ),
                if (!kIsWeb) ...[
                  const SizedBox(height: 14),
                  TextButton.icon(
                    onPressed: () => _editServer(store),
                    icon: const Icon(Icons.dns_outlined, size: 16),
                    label: Text('Serveur : ${Uri.tryParse(store.serverUrl)?.authority ?? store.serverUrl}',
                        style: const TextStyle(fontSize: 12, color: Colors.white60)),
                  ),
                ],
                if (store.notice != null) ...[
                  const SizedBox(height: 18),
                  Text(store.notice!,
                      style: const TextStyle(color: warnColor, fontSize: 13), textAlign: TextAlign.center),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  final void Function(String) onDigit;
  final VoidCallback onBack;
  const _Keypad({required this.onDigit, required this.onBack});

  @override
  Widget build(BuildContext context) {
    Widget key({String? label, IconData? icon, VoidCallback? onTap}) => Padding(
          padding: const EdgeInsets.all(5),
          child: SizedBox(
            width: 66,
            height: 58,
            child: onTap == null
                ? null
                : Material(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: onTap,
                      child: Center(
                        child: icon != null
                            ? Icon(icon, color: Colors.white70)
                            : Text(label!,
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ),
          ),
        );

    return Column(children: [
      for (final row in const [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
      ])
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final d in row) key(label: d, onTap: () => onDigit(d)),
        ]),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        key(),
        key(label: '0', onTap: () => onDigit('0')),
        key(icon: Icons.backspace_outlined, onTap: onBack),
      ]),
    ]);
  }
}
