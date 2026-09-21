import '../api/api_client.dart';
import '../models/reporte.dart';

class ReportesService {
  static Future<ResumenReporte> resumen({
    String? fechaDesde,
    String? fechaHasta,
    int? sucursalId,
    int? categoriaId,
    int? temporadaId,
  }) async {
    final data = await ApiClient.get(
      '/reportes/resumen',
      query: _query(fechaDesde, fechaHasta, sucursalId, categoriaId, temporadaId),
    );
    return ResumenReporte.fromJson(data as Map<String, dynamic>);
  }

  static Future<List<VentaSucursalRow>> ventasPorSucursal({
    String? fechaDesde,
    String? fechaHasta,
    int? sucursalId,
    int? categoriaId,
    int? temporadaId,
  }) async {
    final data = await ApiClient.get(
      '/reportes/ventas-por-sucursal',
      query: _query(fechaDesde, fechaHasta, sucursalId, categoriaId, temporadaId),
    );
    return (data as List)
        .map((e) => VentaSucursalRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<MasVendidoRow>> masVendidos({
    String? fechaDesde,
    String? fechaHasta,
    int? sucursalId,
    int? categoriaId,
    int? temporadaId,
    int limit = 10,
  }) async {
    final data = await ApiClient.get(
      '/reportes/mas-vendidos',
      query: {
        'limit': '$limit',
        ..._query(fechaDesde, fechaHasta, sucursalId, categoriaId, temporadaId),
      },
    );
    return (data as List)
        .map((e) => MasVendidoRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<RotacionRow>> rotacionInventario({
    String? fechaDesde,
    String? fechaHasta,
    int? sucursalId,
    int? categoriaId,
    int? temporadaId,
    int limit = 10,
  }) async {
    final data = await ApiClient.get(
      '/reportes/rotacion-inventario',
      query: {
        'limit': '$limit',
        ..._query(fechaDesde, fechaHasta, sucursalId, categoriaId, temporadaId),
      },
    );
    return (data as List)
        .map((e) => RotacionRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<StockCriticoRow>> stockCritico({
    String? fechaDesde,
    String? fechaHasta,
    int? sucursalId,
    int? categoriaId,
    int? temporadaId,
  }) async {
    final data = await ApiClient.get(
      '/reportes/stock-critico',
      query: _query(fechaDesde, fechaHasta, sucursalId, categoriaId, temporadaId),
    );
    return (data as List)
        .map((e) => StockCriticoRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<ReservasReporte> reservas({
    String? fechaDesde,
    String? fechaHasta,
    int? sucursalId,
    int? categoriaId,
    int? temporadaId,
  }) async {
    final data = await ApiClient.get(
      '/reportes/reservas',
      query: _query(fechaDesde, fechaHasta, sucursalId, categoriaId, temporadaId),
    );
    return ReservasReporte.fromJson(data as Map<String, dynamic>);
  }

  static Future<List<TendenciaRow>> tendencias({
    String? fechaDesde,
    String? fechaHasta,
    int? sucursalId,
    int? categoriaId,
    int? temporadaId,
  }) async {
    final data = await ApiClient.get(
      '/reportes/tendencias-temporada',
      query: _query(fechaDesde, fechaHasta, sucursalId, categoriaId, temporadaId),
    );
    return (data as List)
        .map((e) => TendenciaRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Map<String, String> _query(
    String? fechaDesde,
    String? fechaHasta,
    int? sucursalId,
    int? categoriaId,
    int? temporadaId,
  ) {
    return {
      'fecha_desde': ?fechaDesde,
      'fecha_hasta': ?fechaHasta,
      'sucursal_id': ?sucursalId?.toString(),
      'categoria_id': ?categoriaId?.toString(),
      'temporada_id': ?temporadaId?.toString(),
    };
  }
}