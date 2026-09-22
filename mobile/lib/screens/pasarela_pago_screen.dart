import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;

import '../api/api_client.dart';
import '../models/venta.dart';
import '../services/ventas_service.dart';

class PasarelaPagoScreen extends StatefulWidget {
  const PasarelaPagoScreen({
    super.key,
    required this.intencion,
    required this.publishableKey,
    required this.pasarelaSimulada,
    required this.compra,
  });

  final IntencionPago intencion;
  final String? publishableKey;
  final bool pasarelaSimulada;
  final CompraDigitalCreate compra;

  @override
  State<PasarelaPagoScreen> createState() => _PasarelaPagoScreenState();
}

class _PasarelaPagoScreenState extends State<PasarelaPagoScreen> {
  bool _pagando = false;
  String? _error;
  final CardFormEditController _cardController = CardFormEditController();

  Future<void> _aplicarConfigStripe() async {
    final pk = widget.publishableKey;
    if (pk == null || pk.isEmpty) {
      throw Exception('La pasarela no está configurada (falta la clave publicable de Stripe).');
    }
    Stripe.publishableKey = pk;
    await Stripe.instance.applySettings();
  }

  Future<void> _pagar() async {
    setState(() {
      _error = null;
      _pagando = true;
    });
    try {
      if (widget.pasarelaSimulada) {
        await _pagarSimulado();
      } else {
        await _pagarConStripe();
      }
    } finally {
      if (mounted) setState(() => _pagando = false);
    }
  }

  Future<void> _pagarSimulado() async {
    try {
      final res = await VentasService.confirmarCompra(widget.compra);
      if (!mounted) return;
      Navigator.of(context).pop(res);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.toLowerCase().contains('rechazado')
            ? 'Pago rechazado por la pasarela. Intenta con la tarjeta 4242 4242 4242 4242.'
            : e.message;
      });
    }
  }

  Future<void> _pagarConStripe() async {
    try {
      await _aplicarConfigStripe();
      final intent = await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: widget.intencion.clientSecret,
        data: PaymentMethodParams.card(paymentMethodData: PaymentMethodData()),
      );
      if (intent.status == PaymentIntentsStatus.Succeeded) {
        final conPago = CompraDigitalCreate(
          sucursalId: widget.compra.sucursalId,
          pasarela: widget.compra.pasarela,
          paymentIntentId: widget.intencion.id,
          items: widget.compra.items,
        );
        final res = await VentasService.confirmarCompra(conPago);
        if (!mounted) return;
        Navigator.of(context).pop(res);
      } else {
        if (!mounted) return;
        setState(() {
          _error = 'El pago no fue aprobado por la pasarela (estado: ${intent.status.name}).';
        });
      }
    } on StripeException catch (e) {
      if (!mounted) return;
      final msg = e.error.localizedMessage ??
          e.error.message ??
          'El pago fue rechazado por la pasarela.';
      setState(() => _error = msg);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pasarela de Pago (Stripe Sandbox)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pago de la compra digital',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Total a pagar: Bs. ${widget.intencion.monto.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.pasarelaSimulada
                        ? 'Modo de prueba (sandbox simulado). Usa la tarjeta 4242 4242 4242 4242.'
                        : 'Introduce los datos de tu tarjeta de prueba de Stripe.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  if (widget.pasarelaSimulada) ...[
                    _campoSimulado('Número de Tarjeta', '4242 4242 4242 4242'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _campoSimulado('MM/AA', '12/26'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _campoSimulado('CVC', '123'),
                        ),
                      ],
                    ),
                  ] else ...[
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: CardFormField(
                        controller: _cardController,
                        enablePostalCode: false,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'El formulario es seguro: los datos de la tarjeta son procesados directamente por Stripe.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _pagando ? null : _pagar,
            icon: _pagando
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.payment),
            label: Text(
              _pagando
                  ? 'Procesando pago...'
                  : 'Pagar Bs. ${widget.intencion.monto.toStringAsFixed(2)}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoSimulado(String label, String value) {
    return TextField(
      enabled: false,
      controller: TextEditingController(text: value),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        filled: true,
      ),
    );
  }
}