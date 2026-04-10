import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl, this.onUnauthorized})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:4000');

  final http.Client _client;
  final String _baseUrl;
  final void Function()? onUnauthorized;

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<Map<String, dynamic>> getJson(String path, {String? token}) async {
    final res = await _client.get(
      _uri(path),
      headers: _headers(token: token),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body, {String? token}) async {
    final res = await _client.post(
      _uri(path),
      headers: _headers(token: token),
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> putJson(String path, Map<String, dynamic> body, {String? token}) async {
    final res = await _client.put(
      _uri(path),
      headers: _headers(token: token),
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Future<void> delete(String path, {String? token}) async {
    final res = await _client.delete(
      _uri(path),
      headers: _headers(token: token),
    );
    if (res.statusCode == 401) onUnauthorized?.call();
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body);
    }
  }

  Map<String, String> _headers({String? token}) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode == 401) {
      onUnauthorized?.call();
      throw ApiException(res.statusCode, res.body);
    }
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body);
    }
    if (res.body.isEmpty) return {};
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw ApiException(res.statusCode, 'Unexpected response');
  }
}

class ApiException implements Exception {
  final int status;
  final String message; // human-readable, parsed from the server JSON body

  ApiException(this.status, String rawBody) : message = _parse(rawBody);

  /// Parses the server error body into a clean human-readable string.
  ///
  /// Server returns either:
  ///   {"error": "some string"}           → plain message
  ///   {"error": {"field": ["msg", ...]}} → Zod validation errors (flattened)
  static String _parse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is String) return error;
        if (error is Map<String, dynamic>) {
          final messages = <String>[];
          for (final msgs in error.values) {
            if (msgs is List) {
              for (final m in msgs) {
                if (m is String) messages.add(m);
              }
            }
          }
          if (messages.isNotEmpty) return messages.join('\n');
        }
      }
    } catch (_) {}
    return body.length < 200 ? body : 'An unexpected error occurred';
  }

  @override
  String toString() => message;
}
