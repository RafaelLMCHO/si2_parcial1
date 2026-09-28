import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

class AuthService {
  static Future<void> login(String email, String contrasena) async {
    final data = await ApiClient.post(
      '/auth/login',
      body: {'email': email, 'contrasena': contrasena},
      auth: false,
    );
    final token = data['access_token'] as String;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fashionstore_token', token);
    final usuario = data['usuario'];
    if (usuario != null) {
      await prefs.setString('fashionstore_usuario', jsonEncode(usuario));
    }
  }

  static Future<void> logout() async {
    await ApiClient.clearSession();
  }

  /// Devuelve el id del usuario autenticado, si hay sesion activa.
  static Future<int?> currentUsuarioId() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('fashionstore_usuario');
    if (raw == null) return null;
    try {
      return (jsonDecode(raw)['id_usuario'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// Devuelve el rol del usuario autenticado (CU-16: acceso a reportes
  /// para administradores y encargados).
  static Future<String?> currentRol() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('fashionstore_usuario');
    if (raw == null) return null;
    try {
      return jsonDecode(raw)['rol'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Devuelve el id de sucursal del usuario autenticado, si tiene.
  static Future<int?> currentSucursalId() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('fashionstore_usuario');
    if (raw == null) return null;
    try {
      return (jsonDecode(raw)['sucursal_id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }
}