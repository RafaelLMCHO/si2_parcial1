import '../api/api_client.dart';

class BitacoraService {
  /// CU-07 · Registra en la bitácora (CU-23) la consulta del vestidor virtual.
  /// Una falla aquí jamás bloquea la experiencia del vestidor.
  static Future<void> registrarConsultaVestidor({
    required int productoId,
    required String nombre,
    String modo = 'AR',
  }) async {
    try {
      await ApiClient.post(
        '/bitacora',
        body: {
          'accion': 'CONSULTA_VESTIDOR',
          'entidad': 'Producto',
          'entidad_id': productoId,
          'detalle': 'Vestidor virtual ($modo): $nombre',
        },
      );
    } catch (_) {
      // No bloqueante: la bitácora es un registro transversal.
    }
  }
}