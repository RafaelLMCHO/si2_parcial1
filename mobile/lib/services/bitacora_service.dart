import '../api/api_client.dart';
import '../models/bitacora.dart';

class BitacoraResult {
  final List<RegistroBitacora> registros;
  final int total;

  BitacoraResult(this.registros, this.total);
}

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

  /// CU-23 · Consulta la bitácora. Solo el administrador puede leerla:
  /// el backend responde 403 para otros roles.
  static Future<BitacoraResult> listar({
    int? usuarioId,
    String? accion,
    String? entidad,
    String? fechaDesde,
    String? fechaHasta,
    int pagina = 1,
    int limite = 200,
  }) async {
    final query = <String, String>{
      'pagina': '$pagina',
      'limite': '$limite',
      if (usuarioId != null) 'usuario_id': '$usuarioId',
      if (accion != null && accion.isNotEmpty) 'accion': accion,
      if (entidad != null && entidad.isNotEmpty) 'entidad': entidad,
      if (fechaDesde != null && fechaDesde.isNotEmpty) 'fecha_desde': fechaDesde,
      if (fechaHasta != null && fechaHasta.isNotEmpty) 'fecha_hasta': fechaHasta,
    };
    final res = await ApiClient.getResult('/bitacora', query: query);
    final registros = (res.body as List)
        .map((e) => RegistroBitacora.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = int.tryParse(res.headers['x-total-count'] ?? '') ??
        registros.length;
    return BitacoraResult(registros, total);
  }
}