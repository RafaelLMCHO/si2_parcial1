import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../models/venta.dart';
import '../services/ventas_service.dart';

/// Pago de un cobro QR desde el celular del cliente.
///
/// El cajero emite el QR en el punto de venta y el cliente escribe aqui el
/// codigo `Transaccion:` que aparece impreso al lado del QR. El pago ocurre en
/// la pagina de la pasarela y, al volver, la app pide el veredicto.
///
/// Importante: esta pantalla nunca declara que el pago se aprobo. Solo muestra
/// lo que responde el backend, que a su vez se lo pregunto a la pasarela. El
/// mismo cobro que se paga desde aca es el que el punto de venta ya esta
/// sondeando, asi que el cajero ve el resultado sin hacer nada.
class PagoQrScreen extends StatefulWidget {
  const PagoQrScreen({super.key});

  @override
  State<PagoQrScreen> createState() => _PagoQrScreenState();
}

class _PagoQrScreenState extends State<PagoQrScreen> {
  final _codigoCtrl = TextEditingController();
  final _codigoFocus = FocusNode();

  bool _ocupado = false;
  String? _error;

  /// El codigo tal como lo escribio el usuario, ya recortado. Viaja a la
  /// confirmacion porque el backend lo usa para localizar el cobro.
  String _referencia = '';

  /// El session_id que devolvio /pagar. Se guarda aparte de la pantalla porque
  /// el veredicto tiene que poder consultarse de nuevo sin volver a pagar.
  String _sessionId = '';

  /// Si la pasarela no respondio con una pagina de pago, la confirmacion va
  /// simulada y la tarjeta la decide el servidor.
  bool _simulado = false;
  String _tarjeta = '';

  CobroQrResultado? _resultado;

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _codigoFocus.dispose();
    super.dispose();
  }

  /// Paso 1: pedir la pagina de pago de la pasarela.
  Future<void> _iniciarPago() async {
    final codigo = _codigoCtrl.text.trim();
    if (codigo.isEmpty) {
      setState(() => _error = 'Escribe el codigo que aparece junto al QR.');
      return;
    }

    setState(() {
      _error = null;
      _ocupado = true;
      _resultado = null;
    });

    try {
      final cobro = await VentasService.pagarCobroQr(codigo);
      _referencia = codigo;
      _sessionId = cobro.sessionId;
      _simulado = cobro.simulado;
      if (!mounted) return;

      final confirmo = await _confirmarMonto(cobro);
      if (confirmo) await _abrirPasarela(cobro);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo iniciar el pago: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Muestra el monto antes de cobrar. El monto lo pone el servidor; esta
  /// pantalla solo lo lee.
  ///
  /// Sin pasarela se pide tambien la tarjeta, para poder demostrar el rechazo
  /// con una tarjeta que la pasarela rechaza. Devuelve false si el cliente se
  /// arrepiente.
  Future<bool> _confirmarMonto(CobroQrPago cobro) async {
    if (!cobro.simulado) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmar pago'),
          content: Text(
            'El punto de venta est\u00e1 cobrando Bs. '
            '${cobro.total.toStringAsFixed(2)}.\n\n'
            'Vas a pagar en la p\u00e1gina segura de la pasarela.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Pagar'),
            ),
          ],
        ),
      );
      return ok ?? false;
    }

    final ctrl = TextEditingController(text: '4242 4242 4242 4242');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pago en modo prueba'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total: Bs. ${cobro.total.toStringAsFixed(2)}'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'N\u00famero de tarjeta',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'La pasarela no est\u00e1 configurada, as\u00ed que la confirmaci\u00f3n es '
              'simulada. Usa una tarjeta terminada en 0002 para ver el rechazo.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              _tarjeta = ctrl.text;
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Pagar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return ok ?? false;
  }

  /// Paso 2: abrir la pagina de la pasarela. Al volver (pagado o cancelado) se
  /// consulta el resultado.
  ///
  /// Sin pasarela no hay pagina: el backend devuelve `simulado` y se confirma
  /// directo, igual que hace el carrito digital en ese caso.
  Future<void> _abrirPasarela(CobroQrPago cobro) async {
    final url = cobro.checkoutUrl;
    if (cobro.simulado || url == null || url.isEmpty) {
      await _consultarResultado();
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!mounted) return;
    await _consultarResultado();
  }

  /// Paso 3: pedir el veredicto. Idempotente: se puede volver a tocar sin fear
  /// de cobrar dos veces.
  Future<void> _consultarResultado() async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final res = await VentasService.confirmarCobroQr(
        _referencia,
        _sessionId,
        numeroTarjeta: _simulado ? _tarjeta : null,
      );
      if (!mounted) return;
      setState(() {
        _resultado = res;
        _ocupado = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _ocupado = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo consultar el resultado: $e';
        _ocupado = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pagar QR del punto de venta')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_resultado == null) _formulario(context) else _panel(context),
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
          ],
        ),
      ),
    );
  }

  Widget _formulario(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pagar el cobro que te mostr\u00f3 el cajero',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Escribe el c\u00f3digo de transacci\u00f3n que aparece impreso junto al '
          'c\u00f3digo QR. Empieza con TXN-.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codigoCtrl,
          focusNode: _codigoFocus,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'TXN-...',
            hintText: 'TXN-SIM-XXXXXXXXXXXXXXXXXXXX',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _ocupado ? null : _iniciarPago(),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _ocupado ? null : _iniciarPago,
          icon: _ocupado
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.qr_code_scanner),
          label: Text(_ocupado ? 'Procesando...' : 'Buscar cobro y pagar'),
        ),
      ],
    );
  }

  Widget _panel(BuildContext context) {
    final r = _resultado!;
    final esquema = Theme.of(context).colorScheme;
    final aprobado = r.aprobado;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Icon(
          aprobado ? Icons.check_circle : Icons.cancel,
          size: 88,
          color: aprobado ? Colors.green.shade700 : esquema.error,
        ),
        const SizedBox(height: 12),
        Text(
          aprobado ? 'Pago aprobado' : 'Pago rechazado',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: aprobado ? Colors.green.shade800 : esquema.error,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          aprobado
              ? 'Tu pago fue confirmado. El punto de venta ya lo ve.'
              : (r.motivo ?? 'La pasarela no confirm\u00f3 el pago.'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _fila('Estado', r.estado),
                _fila('Monto', 'Bs. ${r.total.toStringAsFixed(2)}'),
                _fila('Pedido', '#${r.idPedido}'),
                if (r.estadoPedido != null) _fila('Estado pedido', r.estadoPedido!),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (aprobado)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Listo'),
          )
        else ...[
          OutlinedButton.icon(
            onPressed: _ocupado ? null : _consultarResultado,
            icon: const Icon(Icons.refresh),
            label: const Text('Consultar de nuevo'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {
              _resultado = null;
              _error = null;
            }),
            child: const Text('Probar con otro c\u00f3digo'),
          ),
        ],
      ],
    );
  }

  Widget _fila(String etiqueta, String valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
            Text(valor, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
}
