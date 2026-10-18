import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Erreur renvoyée par l'API (ou réseau) avec un message directement affichable.
class ApiException implements Exception {
  final String message;
  final int? status;
  final String? code;

  /// Vrai quand le serveur n'a pas pu être joint (pas de réseau, délai dépassé) : la saisie peut être gardée sur l'appareil.
  final bool offline;
  const ApiException(this.message, {this.status, this.code, this.offline = false});

  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

/// Client JSON minimal : jeton Bearer, erreurs lisibles, expiration de session.
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client}) : _http = client ?? http.Client();

  /// Modifiable : l'utilisateur peut changer l'adresse du serveur depuis l'écran de connexion.
  String baseUrl;
  final http.Client _http;
  String? token;

  /// Appelé quand le serveur répond 401 alors qu'une session était ouverte (jeton expiré, compte désactivé).
  void Function()? onSessionExpired;

  /// Appelé à chaque changement d'état du réseau (true = le serveur répond).
  void Function(bool online)? onReachability;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: '${base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path}/api$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) => _send('GET', path, query: query);
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) => _send('POST', path, body: body, timeout: timeout);
  Future<dynamic> put(String path, {Object? body, Duration? timeout}) => _send('PUT', path, body: body, timeout: timeout);
  Future<dynamic> patch(String path, {Object? body}) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Réponse brute en texte (export CSV).
  Future<String> getText(String path) async {
    final res = await _request('GET', path, null, null, const Duration(seconds: 30));
    return utf8.decode(res.bodyBytes);
  }

  Future<dynamic> _send(String method, String path,
      {Map<String, String>? query, Object? body, Duration? timeout}) async {
    final res = await _request(method, path, query, body, timeout ?? const Duration(seconds: 30));
    if (res.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<http.Response> _request(
      String method, String path, Map<String, String>? query, Object? body, Duration timeout) async {
    final req = http.Request(method, _uri(path, query));
    req.headers['Accept'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }

    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } on TimeoutException {
      onReachability?.call(false);
      throw const ApiException('Le serveur met trop de temps à répondre. Réessayez.', offline: true);
    } catch (_) {
      onReachability?.call(false);
      throw const ApiException("Serveur injoignable. Vérifiez que l'API est démarrée, son adresse (API_URL) et la connexion Internet.",
          offline: true);
    }
    onReachability?.call(true);

    if (res.statusCode >= 400) {
      String message = 'Erreur ${res.statusCode}.';
      String? code;
      try {
        final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        message = (j['error'] as String?) ?? message;
        code = j['code'] as String?;
        final details = j['details'];
        if (details is List && details.isNotEmpty) {
          message = '$message ${details.map((d) => (d as Map)['message']).join(' ')}';
        }
      } catch (_) {/* corps non JSON : message générique */}
      if (res.statusCode == 401 && token != null && path != '/auth/login') onSessionExpired?.call();
      throw ApiException(message, status: res.statusCode, code: code);
    }
    return res;
  }

  void close() => _http.close();
}
