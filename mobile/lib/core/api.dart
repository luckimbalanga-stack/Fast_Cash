import 'dart:convert';

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

  Future<dynamic> send(String method, String path, {Object? body, String? token}) async {
    final uri = Uri.parse('$base$path');
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    http.Response response;
    try {
      final encoded = body == null ? null : jsonEncode(body);
      switch (method) {
        case 'POST':
          response = await http.post(uri, headers: headers, body: encoded);
        case 'PATCH':
          response = await http.patch(uri, headers: headers, body: encoded);
        case 'PUT':
          response = await http.put(uri, headers: headers, body: encoded);
        case 'DELETE':
          response = await http.delete(uri, headers: headers);
        default:
          response = await http.get(uri, headers: headers);
      }
    } catch (_) {
      throw ApiException('Impossible de joindre le serveur Fast-Cash. Vérifiez que l’API est démarrée.');
    }
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
  }

  String _detail(dynamic decoded, int code) {
    if (decoded is Map && decoded['detail'] is String) return decoded['detail'] as String;
    if (decoded is Map && decoded['detail'] is List) {
      return (decoded['detail'] as List).map((item) => item is Map ? (item['msg'] ?? item.toString()) : item.toString()).join(' ');
    }
    return 'Erreur $code';
  }
}
