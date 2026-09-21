import '../api/api_client.dart';
import '../models/producto.dart';

class IaService {
  static Future<List<Producto>> recomendar({int limit = 6}) async {
    final data = await ApiClient.get(
      '/ia/recomendaciones',
      query: {'limit': '$limit'},
    );
    return (data as List)
        .map((e) => Producto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<Producto>> disponibles(
    int sucursalId, {
    int limit = 6,
  }) async {
    final data = await ApiClient.get(
      '/ia/recomendaciones/disponibles',
      query: {'sucursal_id': '$sucursalId', 'limit': '$limit'},
      auth: false,
    );
    return (data as List)
        .map((e) => Producto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}