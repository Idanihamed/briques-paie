import 'package:flutter/foundation.dart' show kIsWeb;

/// Adresse de l'API. Aucune donnée n'est embarquée dans l'application : tout vient du serveur.
///
///   flutter run -d chrome --dart-define=API_URL=http://localhost:3000
///   flutter build apk     --dart-define=API_URL=https://api.votre-domaine.com
///   flutter build web     --dart-define=API_URL=same-origin     (web servi par l'API elle-même)
///
/// Émulateur Android : http://10.0.2.2:3000 (l'émulateur voit le PC par cette adresse).
/// En production, utilisez toujours https.
const _apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

/// « same-origin » (web uniquement) : l'application et l'API partagent la même adresse, sans CORS.
String get apiBaseUrl => (_apiUrl == 'same-origin' && kIsWeb) ? Uri.base.origin : _apiUrl;

/// Verrouillage automatique de la session après inactivité.
const idleLockAfter = Duration(minutes: 5);
