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
  final String? paymentIntentId;
  final List<CompraItemCreate> items;

  CompraDigitalCreate({
    this.sucursalId = 1,
    this.pasarela = 'stripe',
    this.paymentIntentId,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'sucursal_id': sucursalId,
        'pasarela': pasarela,
        if (paymentIntentId != null) 'payment_intent_id': paymentIntentId,
        'items': items.map((e) => e.toJson()).toList(),
      };
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

  CompraConfirmada({
    required this.idPedido,
    required this.total,
    required this.estado,
  });

  factory CompraConfirmada.fromJson(Map<String, dynamic> json) =>
      CompraConfirmada(
        idPedido: json['id_pedido'] as int,
        total: (json['total'] as num).toDouble(),
        estado: json['estado'] as String,
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