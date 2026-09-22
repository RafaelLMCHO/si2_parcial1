import '../api/api_client.dart';
import '../models/venta.dart';

class VentasService {
  static Future<IntencionPago> crearIntencionPago(CompraDigitalCreate data) async {
    final resp = await ApiClient.post('/ventas/digital/payment-intent', body: data.toJson());
    return IntencionPago.fromJson(resp as Map<String, dynamic>);
  }

  static Future<SesionCheckout> crearCheckout(
    CompraDigitalCreate data, {
    String? returnUrl,
  }) async {
    final body = data.toJson();
    if (returnUrl != null) body['return_url'] = returnUrl;
    final resp = await ApiClient.post('/ventas/digital/checkout', body: body);
    return SesionCheckout.fromJson(resp as Map<String, dynamic>);
  }

  static Future<CompraConfirmada> confirmarSesion(String sessionId) async {
    final resp = await ApiClient.post(
      '/ventas/digital/confirmar',
      body: {'session_id': sessionId},
    );
    return CompraConfirmada.fromJson(resp as Map<String, dynamic>);
  }

  static Future<CompraConfirmada> confirmarCompra(CompraDigitalCreate data) async {
    final resp = await ApiClient.post('/ventas/digital/confirmar', body: data.toJson());
    return CompraConfirmada.fromJson(resp as Map<String, dynamic>);
  }

  static Future<ConfigPublica> configPublica() async {
    final resp = await ApiClient.get('/config/public', auth: false);
    return ConfigPublica.fromJson(resp as Map<String, dynamic>);
  }
}