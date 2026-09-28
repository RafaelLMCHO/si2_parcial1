import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final int status;
  final String message;

  ApiException(this.status, this.message);

  @override
  String toString() => message;
}

class HttpResult {
  final dynamic body;
  final Map<String, String> headers;

  HttpResult(this.body, this.headers);
}

class ApiClient {
  static const _envUrl = String.fromEnvironment('API_URL');
  static const _timeout = Duration(seconds: 8);
  static String? _customUrl;

  static void setCustomUrl(String url) {
    _customUrl = url.trim().replaceAll(RegExp(r'/$'), '');
  }

  static String baseUrl() {
    if (_customUrl != null && _customUrl!.isNotEmpty) return _customUrl!;
    if (_envUrl.isNotEmpty) return _envUrl;
    if (kIsWeb) return 'http://localhost:8000/api/v1';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'https://backend-production-1d343.up.railway.app/api/v1';
    }
    return 'https://backend-production-1d343.up.railway.app/api/v1';
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
    final res = await _getRaw(path, query, auth);
    return _decode(res);
  }

  /// Igual que [get] pero además expone los headers de la respuesta
  /// (p. ej. `X-Total-Count` para la paginación de la bitácora).
  static Future<HttpResult> getResult(
    String path, {
    Map<String, String>? query,
    bool auth = true,
  }) async {
    final res = await _getRaw(path, query, auth);
    final body = _decode(res);
    return HttpResult(body, res.headers);
  }

  static Future<http.Response> _getRaw(
    String path,
    Map<String, String>? query,
    bool auth,
  ) async {
    var uri = Uri.parse('${baseUrl()}$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final token = await _token();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    try {
      return await http.get(uri, headers: headers).timeout(_timeout);
    } on TimeoutException {
      throw ApiException(408, 'Tiempo de espera agotado al conectar a ${uri.host}:${uri.port}.\nVerifica que el Firewall de Windows permita el puerto 8000.');
    } on SocketException catch (e) {
      throw ApiException(503, 'No se pudo conectar al servidor (${uri.host}:${uri.port}): ${e.message}');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(500, 'Error de red: $e');
    }
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
    try {
      final res = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(_timeout);
      return _decode(res);
    } on TimeoutException {
      throw ApiException(408, 'Tiempo de espera agotado al conectar a ${uri.host}:${uri.port}.\nVerifica que el Firewall de Windows permita el puerto 8000.');
    } on SocketException catch (e) {
      throw ApiException(503, 'No se pudo conectar al servidor (${uri.host}:${uri.port}): ${e.message}');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(500, 'Error de red: $e');
    }
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
    try {
      final res = await http.patch(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      ).timeout(_timeout);
      return _decode(res);
    } on TimeoutException {
      throw ApiException(408, 'Tiempo de espera agotado al conectar a ${uri.host}:${uri.port}.');
    } on SocketException catch (e) {
      throw ApiException(503, 'No se pudo conectar al servidor: ${e.message}');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(500, 'Error de red: $e');
    }
  }

  /// Sube una imagen (multipart) y devuelve los BYTES de la respuesta.
  ///
  /// El probador virtual por foto (`/virtual/prueba`) responde la imagen
  /// editada en binario cuando funciona, y JSON de error cuando falla, así que
  /// este método existe para ese caso concreto.
  static Future<Uint8List> postImage(
    String path, {
    required Uint8List fileBytes,
    required String filename,
    String mimeType = 'image/jpeg',
    Map<String, String>? fields,
    bool auth = true,
  }) async {
    final uri = Uri.parse('${baseUrl()}$path');
    final req = http.MultipartRequest('POST', uri);
    if (auth) {
      final token = await _token();
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
    }
    fields?.forEach((key, value) => req.fields[key] = value);
    req.files.add(http.MultipartFile.fromBytes(
      'persona',
      fileBytes,
      filename: filename,
      contentType: MediaType.parse(mimeType),
    ));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }
    throw ApiException(res.statusCode, _mensajeDeError(res));
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
    throw ApiException(res.statusCode, _mensajeDeError(res));
  }

  /// Extrae el mensaje legible de una respuesta de error. Prefiere el `detail`
  /// JSON de FastAPI, después `error`/`message`, y como último recurso el
  /// estado HTTP (misma regla en todos los verbos).
  static String _mensajeDeError(http.Response res) {
    final isJson =
        res.headers['content-type']?.contains('application/json') ?? false;
    if (!isJson || res.body.isEmpty) {
      return 'Error de comunicación (${res.statusCode})';
    }
    try {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is Map) {
        final detalle = data['detail'];
        if (detalle is String && detalle.isNotEmpty) return detalle;
        if (detalle is List) {
          final partes = detalle
              .map((e) =>
                  e is Map ? e['msg']?.toString() ?? '' : '')
              .where((s) => s.isNotEmpty)
              .toList();
          if (partes.isNotEmpty) return partes.join('; ');
        }
        for (final clave in ['error', 'message']) {
          final valor = data[clave];
          if (valor != null && valor.toString().isNotEmpty) {
            return valor.toString();
          }
        }
        return jsonEncode(data);
      }
    } catch (_) {
      // el cuerpo decía JSON pero no lo era: se cae al mensaje genérico
    }
    return 'Error de comunicación (${res.statusCode})';
  }
}