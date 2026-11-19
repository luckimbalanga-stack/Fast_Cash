import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({this.base = const String.fromEnvironment('API_BASE', defaultValue: 'http://127.0.0.1:8000')});

  final String base;
  final http.Client _client = http.Client();

  /// Render (free) peut mettre 40–70 s à se réveiller après inactivité.
  static const Duration _timeout = Duration(seconds: 90);

  Future<dynamic> send(String method, String path, {Object? body, String? token}) async {
    final uri = Uri.parse('$base$path');
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final encoded = body == null ? null : jsonEncode(body);

    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final call = switch (method) {
          'POST' => _client.post(uri, headers: headers, body: encoded),
          'PATCH' => _client.patch(uri, headers: headers, body: encoded),
          'PUT' => _client.put(uri, headers: headers, body: encoded),
          'DELETE' => _client.delete(uri, headers: headers),
          _ => _client.get(uri, headers: headers),
        };
        final response = await call.timeout(_timeout);
        dynamic decoded;
        try {
          decoded = response.body.isEmpty ? null : jsonDecode(response.body);
        } catch (_) {
          decoded = null;
        }
        if (response.statusCode >= 400) {
          throw ApiException(_detail(decoded, response.statusCode));
        }
        return decoded;
      } on ApiException {
        rethrow;
      } on TimeoutException catch (error) {
        lastError = error;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
      } on SocketException catch (error) {
        lastError = error;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
      } on http.ClientException catch (error) {
        lastError = error;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
      } catch (error) {
        lastError = error;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
      }
    }
    final hint = lastError is TimeoutException
        ? 'Le serveur met trop de temps à répondre (réveil Render). Réessayez dans une minute.'
        : 'Impossible de joindre le serveur Fast-Cash. Vérifiez votre connexion puis réessayez.';
    throw ApiException(hint);
  }

  String _detail(dynamic decoded, int code) {
    if (decoded is Map && decoded['detail'] is String) return decoded['detail'] as String;
    if (decoded is Map && decoded['detail'] is List) {
      return (decoded['detail'] as List).map((item) => item is Map ? (item['msg'] ?? item.toString()) : item.toString()).join(' ');
    }
    return 'Erreur $code';
  }

  void close() => _client.close();
}
