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

  static Future<QrDigitalResponse> generarQrDigital(CompraDigitalCreate data) async {
    final resp = await ApiClient.post('/ventas/digital/qr-generar', body: data.toJson());
    return QrDigitalResponse.fromJson(resp as Map<String, dynamic>);
  }

  static Future<ConfigPublica> configPublica() async {
    final resp = await ApiClient.get('/config/public', auth: false);
    return ConfigPublica.fromJson(resp as Map<String, dynamic>);
  }

  /// Pide la pagina de pago de un cobro QR emitido por el punto de venta.
  /// El codigo es el `Transaccion:` que aparece impreso junto al QR.
  static Future<CobroQrPago> pagarCobroQr(String referencia) async {
    final resp = await ApiClient.post(
      '/ventas/qr/${Uri.encodeComponent(referencia.trim())}/pagar',
    );
    return CobroQrPago.fromJson(resp as Map<String, dynamic>);
  }

  /// Cierra el cobro. El backend le pregunta a la pasarela si el dinero llego:
  /// este metodo no declara que se pago, solo entrega el session_id.
  ///
  /// `numeroTarjeta` solo se usa en modo simulado, para poder demostrar tambien
  /// el rechazo. Con Stripe real la tarjeta la evalua Stripe.
  static Future<CobroQrResultado> confirmarCobroQr(
    String referencia,
    String sessionId, {
    String? numeroTarjeta,
  }) async {
    final resp = await ApiClient.post(
      '/ventas/qr/${Uri.encodeComponent(referencia.trim())}/confirmar',
      body: {
        'session_id': sessionId,
        'numero_tarjeta': ?numeroTarjeta,
      },
    );
    return CobroQrResultado.fromJson(resp as Map<String, dynamic>);
  }
}