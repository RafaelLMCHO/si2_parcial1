class CompraItemCreate {
  final int varianteId;
  final int cantidad;

  CompraItemCreate({required this.varianteId, required this.cantidad});

  Map<String, dynamic> toJson() =>
      {'variante_id': varianteId, 'cantidad': cantidad};
}

class CompraDigitalCreate {
  final int sucursalId;
  final String pasarela;
  final String? tipoPago;
  final String? paymentIntentId;
  final List<CompraItemCreate> items;

  CompraDigitalCreate({
    this.sucursalId = 1,
    this.pasarela = 'stripe',
    this.tipoPago = 'tarjeta_credito',
    this.paymentIntentId,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'sucursal_id': sucursalId,
        'pasarela': pasarela,
        if (tipoPago != null) 'tipo_pago': tipoPago,
        if (paymentIntentId != null) 'payment_intent_id': paymentIntentId,
        'items': items.map((e) => e.toJson()).toList(),
      };
}

class QrDigitalResponse {
  final double monto;
  final String qrUrl;
  final String referencia;
  final String moneda;

  QrDigitalResponse({
    required this.monto,
    required this.qrUrl,
    required this.referencia,
    required this.moneda,
  });

  factory QrDigitalResponse.fromJson(Map<String, dynamic> json) =>
      QrDigitalResponse(
        monto: (json['monto'] as num).toDouble(),
        qrUrl: json['qr_url'] as String? ?? '',
        referencia: json['referencia'] as String? ?? '',
        moneda: json['moneda'] as String? ?? 'BOB',
      );
}

class IntencionPago {
  final double monto;
  final String id;
  final String clientSecret;
  final bool simulado;

  IntencionPago({
    required this.monto,
    required this.id,
    required this.clientSecret,
    required this.simulado,
  });

  factory IntencionPago.fromJson(Map<String, dynamic> json) => IntencionPago(
        monto: (json['monto'] as num).toDouble(),
        id: json['id'] as String,
        clientSecret: json['client_secret'] as String,
        simulado: json['simulado'] as bool? ?? true,
      );
}

class CompraConfirmada {
  final int idPedido;
  final double total;
  final String estado;
  final String? tipoPago;

  CompraConfirmada({
    required this.idPedido,
    required this.total,
    required this.estado,
    this.tipoPago,
  });

  factory CompraConfirmada.fromJson(Map<String, dynamic> json) =>
      CompraConfirmada(
        idPedido: json['id_pedido'] as int,
        total: (json['total'] as num).toDouble(),
        estado: json['estado'] as String,
        tipoPago: json['tipo_pago'] as String?,
      );
}

class ConfigPublica {
  final String? stripePublishableKey;
  final bool pasarelaSimulada;
  final String moneda;

  ConfigPublica({
    required this.stripePublishableKey,
    required this.pasarelaSimulada,
    required this.moneda,
  });

  factory ConfigPublica.fromJson(Map<String, dynamic> json) =>
      ConfigPublica(
        stripePublishableKey: json['stripe_publishable_key'] as String?,
        pasarelaSimulada: json['pasarela_simulada'] as bool? ?? true,
        moneda: json['moneda'] as String? ?? 'usd',
      );
}

class SesionCheckout {
  final String sessionId;
  final String? checkoutUrl;
  final bool simulado;

  SesionCheckout({required this.sessionId, this.checkoutUrl, required this.simulado});

  factory SesionCheckout.fromJson(Map<String, dynamic> json) => SesionCheckout(
        sessionId: json['session_id'] as String,
        checkoutUrl: json['url'] as String?,
        simulado: json['simulado'] as bool? ?? false,
      );
}

/// Lo que devuelve el backend al pedir la pagina de pago de un cobro QR.
class CobroQrPago {
  final String sessionId;

  /// Nulo cuando la pasarela no esta configurada: en ese caso el backend marca
  /// `simulado` y no hay pagina que abrir.
  final String? checkoutUrl;
  final bool simulado;
  final double total;
  final int idPago;

  CobroQrPago({
    required this.sessionId,
    this.checkoutUrl,
    required this.simulado,
    required this.total,
    required this.idPago,
  });

  factory CobroQrPago.fromJson(Map<String, dynamic> json) => CobroQrPago(
        sessionId: json['session_id'] as String,
        checkoutUrl: json['checkout_url'] as String,
        simulado: json['simulado'] as bool? ?? false,
        total: (json['total'] as num).toDouble(),
        idPago: json['id_pago'] as int,
      );
}

/// El veredicto del cobro QR. `estado` es la palabra que decide la pantalla:
/// 'aprobado' o 'rechazado'. Un rechazo llega como resultado, no como error.
class CobroQrResultado {
  final int idPago;
  final int idPedido;
  final String estado;
  final bool aplicado;
  final String? motivo;
  final String? estadoPedido;
  final double total;

  CobroQrResultado({
    required this.idPago,
    required this.idPedido,
    required this.estado,
    required this.aplicado,
    this.motivo,
    this.estadoPedido,
    required this.total,
  });

  bool get aprobado => estado == 'aprobado';

  factory CobroQrResultado.fromJson(Map<String, dynamic> json) => CobroQrResultado(
        idPago: json['id_pago'] as int,
        idPedido: json['id_pedido'] as int,
        estado: json['estado'] as String,
        aplicado: json['aplicado'] as bool? ?? false,
        motivo: json['motivo'] as String?,
        estadoPedido: json['estado_pedido'] as String?,
        total: (json['total'] as num).toDouble(),
      );
}