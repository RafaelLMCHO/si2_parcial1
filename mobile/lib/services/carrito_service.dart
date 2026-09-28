import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/carrito.dart';
import 'auth_service.dart';

class CarritoService {
  CarritoService._();

  static final CarritoService instance = CarritoService._();

  static const _claveBase = 'fashionstore_carrito_reservas';

  final List<CarritoItem> _items = [];
  bool _cargado = false;
  int? _usuarioCargado;
  String? _claveActiva;

  /// Cada cliente tiene su propio carrito, guardado bajo una clave distinta.
  static String _claveDe(int? idUsuario) =>
      idUsuario == null ? _claveBase : '${_claveBase}_$idUsuario';

  List<CarritoItem> get items => List.unmodifiable(_items);
  int get totalPrendas => _items.fold(0, (acc, item) => acc + item.cantidad);
  bool get vacio => _items.isEmpty;

  /// Prendas que todavia no tienen reserva confirmada.
  List<CarritoItem> get disponibles =>
      _items.where((i) => !i.reservado).toList(growable: false);

  int get totalDisponibles =>
      disponibles.fold(0, (acc, item) => acc + item.cantidad);

  static DateTime get _hoy {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Saca del carrito las prendas cuya fecha de prueba ya paso.
  /// Durante el dia de la reserva siguen visibles.
  void _descartarVencidas() {
    final corte = _hoy;
    _items.removeWhere(
      (i) => i.reservadoHasta != null && i.reservadoHasta!.isBefore(corte),
    );
  }

  /// Carga el carrito del usuario autenticado. Si la cuenta cambio desde la
  /// ultima carga, descarta lo que habia en memoria y vuelve a leer.
  Future<void> init() async {
    final id = await AuthService.currentUsuarioId();
    if (_cargado && _usuarioCargado == id) return;
    _cargado = true;
    _usuarioCargado = id;
    _claveActiva = _claveDe(id);
    _items.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_claveActiva!);
      if (raw == null || raw.isEmpty) return;
      final lista = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _items.addAll(lista.map(CarritoItem.fromJson));
      final antes = _items.length;
      _descartarVencidas();
      if (_items.length != antes) await _guardar();
    } catch (_) {
      _items.clear();
    }
  }

  Future<void> agregar(CarritoItem item) async {
    await init();
    final idx = _items.indexWhere((i) => i.varianteId == item.varianteId);
    if (idx >= 0) {
      _items[idx].cantidad += item.cantidad;
    } else {
      _items.add(item);
    }
    await _guardar();
  }

  Future<void> cambiarCantidad(int varianteId, int cantidad) async {
    await init();
    final idx = _items.indexWhere((i) => i.varianteId == varianteId);
    if (idx >= 0) {
      _items[idx].cantidad = cantidad < 1 ? 1 : cantidad;
      await _guardar();
    }
  }

  Future<void> quitar(int varianteId) async {
    await init();
    _items.removeWhere((i) => i.varianteId == varianteId);
    await _guardar();
  }

  Future<void> limpiar() async {
    _items.clear();
    await _guardar();
  }

  /// Marca como reservadas las prendas aun disponibles, con la fecha en la
  /// que el cliente ira a probarlas. Se quedan en el carrito hasta esa fecha.
  Future<void> marcarReservados(DateTime fecha, int idReserva) async {
    await init();
    final corte = DateTime(fecha.year, fecha.month, fecha.day);
    for (final i in _items) {
      if (i.reservado) continue;
      i.reservadoHasta = corte;
      i.idReserva = idReserva;
    }
    await _guardar();
  }

  Future<void> _guardar() async {
    final prefs = await SharedPreferences.getInstance();
    _claveActiva ??= _claveDe(await AuthService.currentUsuarioId());
    await prefs.setString(
      _claveActiva!,
      jsonEncode(_items.map((i) => i.toJson()).toList()),
    );
  }
}