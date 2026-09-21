import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final int status;
  final String message;

  ApiException(this.status, this.message);

  @override
  String toString() => message;
}

class ApiClient {
  static const _envUrl = String.fromEnvironment('API_URL');

  static String baseUrl() {
    if (_envUrl.isNotEmpty) return _envUrl;
    if (kIsWeb) return 'http://localhost:8000/api/v1';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000/api/v1';
    }
    return 'http://localhost:8000/api/v1';
  }

  static Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('fashionstore_token');
  }

  static Future<dynamic> get(
    String path, {
    Map<String, String>? query,
    bool auth = true,
  }) async {
    var uri = Uri.parse('${baseUrl()}$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final token = await _token();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    final res = await http.get(uri, headers: headers);
    return _decode(res);
  }

  static Future<dynamic> post(
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    final uri = Uri.parse('${baseUrl()}$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final token = await _token();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    final res = await http.post(uri, headers: headers, body: jsonEncode(body));
    return _decode(res);
  }

  static Future<dynamic> patch(
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    final uri = Uri.parse('${baseUrl()}$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final token = await _token();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    final res = await http.patch(
      uri,
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    );
    return _decode(res);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('fashionstore_token');
    await prefs.remove('fashionstore_usuario');
  }

  /// Resuelve la URL de un medio (modelo 3D, imagen) que puede venir relativa,
  /// p. ej. `/static/models/prenda.glb`, contra el origen del API.
  static String resolveMediaUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    if (path.startsWith('/')) {
      final base = Uri.parse(baseUrl());
      return Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.port,
        pathSegments: path.split('/').where((s) => s.isNotEmpty).toList(),
      ).toString();
    }
    return path;
  }

  static dynamic _decode(http.Response res) {
    final isJson =
        res.headers['content-type']?.contains('application/json') ?? false;
    final dynamic data =
        isJson && res.body.isNotEmpty ? jsonDecode(utf8.decode(res.bodyBytes)) : res.body;
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    String message;
    if (data is Map && data['detail'] != null) {
      final detail = data['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail is List) {
        message = detail
            .map((e) => (e as Map)['msg']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .join('; ');
      } else {
        message = 'Error del servidor';
      }
    } else {
      message = 'Error de comunicación (${res.statusCode})';
    }
    throw ApiException(res.statusCode, message);
  }
}