import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/carrito.dart';
import '../models/reserva.dart';
import '../models/sucursal.dart';
import '../models/venta.dart';
import '../services/carrito_service.dart';
import '../services/reserva_service.dart';
import '../services/sucursal_service.dart';
import '../services/ventas_service.dart';
import 'pasarela_pago_screen.dart';

import 'package:url_launcher/url_launcher.dart';

enum _ModoCheckout { reserva, compra }

class CarritoScreen extends StatefulWidget {
  const CarritoScreen({super.key});

  @override
  State<CarritoScreen> createState() => _CarritoScreenState();
}

class _CarritoScreenState extends State<CarritoScreen> {
  final _carrito = CarritoService.instance;

  List<Sucursal> _sucursales = [];
  bool _cargandoSucursales = true;
  String? _errorSucursal;

  int? _sucursalId;
  DateTime? _fecha;
  TimeOfDay? _hora;
  bool _cargando = false;
  String? _error;

  _ModoCheckout _modo = _ModoCheckout.reserva;
  bool _procesando = false;
  int? _pedidoId;

  Reserva? _resultado;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    await _carrito.init();
    await _cargarSucursales();
    if (mounted) setState(() {});
  }

  Future<void> _cargarSucursales() async {
    setState(() {
      _cargandoSucursales = true;
      _errorSucursal = null;
    });
    try {
      final lista = await SucursalService.sucursales();
      if (!mounted) return;
      setState(() {
        _sucursales = lista;
        _cargandoSucursales = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoSucursales = false;
        _errorSucursal = e is ApiException ? e.message : e.toString();
      });
    }
  }

  Sucursal? get _sucursalSel {
    for (final s in _sucursales) {
      if (s.idSucursal == _sucursalId) return s;
    }
    return null;
  }

  Future<void> _elegirFecha() async {
    final now = DateTime.now();
    final hoy = DateTime(now.year, now.month, now.day);
    final sel = await showDatePicker(
      context: context,
      initialDate: _fecha ?? hoy,
      firstDate: hoy,
      lastDate: hoy.add(const Duration(days: 365)),
    );
    if (sel != null && mounted) setState(() => _fecha = sel);
  }

  Future<void> _elegirHora() async {
    final sel = await showTimePicker(
      context: context,
      initialTime: _hora ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (sel != null && mounted) setState(() => _hora = sel);
  }

  Future<void> _confirmar() async {
    final sucursalId = _sucursalId;
    final fecha = _fecha;
    final hora = _hora;
    setState(() => _error = null);
    if (sucursalId == null) {
      _mensaje('Selecciona la sucursal donde desea probarse las prendas.');
      return;
    }
    if (fecha == null) {
      _mensaje('Selecciona una fecha de atención válida.');
      return;
    }
    if (hora == null) {
      _mensaje('Selecciona un horario de atención válido.');
      return;
    }
    setState(() => _cargando = true);
    try {
      final reserva = await ReservaService.crear(
        ReservaCreate(
          sucursalId: sucursalId,
          fechaReserva: _fmtFecha(fecha),
          horaAtencion: _fmtHora(hora),
          items: [
            for (final item in _carrito.items)
              ReservaItemCreate(varianteId: item.varianteId, cantidad: item.cantidad),
          ],
        ),
      );
      await _carrito.limpiar();
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _resultado = reserva;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.toString();
      });
    }
  }

  void _mensaje(String texto) {
    setState(() => _error = texto);
  }

  String _fmtFecha(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtHora(TimeOfDay h) =>
      '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final resultado = _resultado;
    if (resultado != null) return _vistaExito(resultado);
    final pedidoId = _pedidoId;
    if (pedidoId != null) return _vistaExitoCompra(pedidoId);
    return Scaffold(
      appBar: AppBar(title: const Text('Carrito de reservas')),
      body: _carrito.vacio ? _vistaVacia() : _contenido(),
    );
  }

  Widget _vistaExito(Reserva reserva) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Carrito de reservas'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade600, size: 64),
              const SizedBox(height: 16),
              Text(
                'Reserva creada exitosamente',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text('le esperamos en la tienda'),
              const SizedBox(height: 16),
              Text(
                'Número de reserva: #${reserva.idReserva}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Seguir explorando'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vistaVacia() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 8),
            const Text('Tu carrito de reservas está vacío.'),
            const SizedBox(height: 4),
            const Text(
              'Agrega prendas desde el catálogo para reservarlas.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Explorar catálogo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenido() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _modo == _ModoCheckout.compra
              ? '${_carrito.totalPrendas} prenda(s) a comprar'
              : '${_carrito.totalPrendas} prenda(s) a reservar',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final item in _carrito.items) _filaItem(item),
        const SizedBox(height: 16),
        SegmentedButton<_ModoCheckout>(
          segments: const [
            ButtonSegment(
              value: _ModoCheckout.reserva,
              icon: Icon(Icons.storefront),
              label: Text('Probar en tienda'),
            ),
            ButtonSegment(
              value: _ModoCheckout.compra,
              icon: Icon(Icons.local_shipping),
              label: Text('Comprar ahora (Digital)'),
            ),
          ],
          selected: {_modo},
          onSelectionChanged: (s) => setState(() {
            _modo = s.first;
            _error = null;
          }),
        ),
        const SizedBox(height: 16),
        if (_modo == _ModoCheckout.reserva) _cardDetalle() else _cardCompra(),
      ],
    );
  }

  Widget _filaItem(CarritoItem item) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _MiniImagen(imagenUrl: item.imagenUrl),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Talla ${item.talla ?? '-'} · Color ${item.color ?? '-'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bs. ${item.precio.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: 'Quitar unidad',
                      onPressed: () => _carrito
                          .cambiarCantidad(item.varianteId, item.cantidad - 1)
                          .then((_) => mounted ? setState(() {}) : null),
                    ),
                    Text('${item.cantidad}'),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'Agregar unidad',
                      onPressed: () => _carrito
                          .cambiarCantidad(item.varianteId, item.cantidad + 1)
                          .then((_) => mounted ? setState(() {}) : null),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Quitar del carrito',
                  onPressed: () => _carrito
                      .quitar(item.varianteId)
                      .then((_) => mounted ? setState(() {}) : null),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardDetalle() {
    final sucursal = _sucursalSel;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dónde y cuándo',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Elige la sucursal donde deseas probarte las prendas y el horario de atención.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              initialValue: _sucursalId,
              decoration: const InputDecoration(
                labelText: 'Sucursal',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final s in _sucursales)
                  DropdownMenuItem(
                    value: s.idSucursal,
                    child: Text('${s.nombre} — ${s.ciudad?.nombre ?? ''}'),
                  ),
              ],
              onChanged: (v) => setState(() => _sucursalId = v),
            ),
            if (_errorSucursal != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorSucursal!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              OutlinedButton(
                onPressed: _cargarSucursales,
                child: const Text('Reintentar'),
              ),
            ] else if (_cargandoSucursales)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (sucursal != null && sucursal.horarioApertura != null) ...[
              const SizedBox(height: 8),
              Text(
                'Horario de atención: ${sucursal.horarioApertura} - ${sucursal.horarioCierre ?? ''}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _elegirFecha,
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(
                      _fecha == null ? 'Seleccionar fecha' : _fmtFecha(_fecha!),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _elegirHora,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(
                      _hora == null ? 'Seleccionar hora' : _fmtHora(_hora!),
                    ),
                  ),
                ),
              ],
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
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _cargando ? null : _confirmar,
                child: _cargando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirmar reserva'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaExitoCompra(int pedidoId) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compra digital'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade600, size: 64),
              const SizedBox(height: 16),
              Text(
                '¡Compra digital exitosa!',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text('Recibirás un correo con el comprobante.'),
              const SizedBox(height: 16),
              Text(
                'Número de pedido: #$pedidoId',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Seguir explorando'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardCompra() {
    double total = 0;
    for (final item in _carrito.items) {
      total += item.precio * item.cantidad;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumen de la compra digital',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Al confirmar verificaremos el stock y se abrirá la pasarela de pago segura.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal'),
                Text('Bs. ${total.toStringAsFixed(2)}'),
              ],
            ),
            const SizedBox(height: 4),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Envío'),
                Text('Gratis (Promoción)'),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total a pagar',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Bs. ${total.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
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
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _procesando ? null : _procederPago,
                icon: _procesando
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.shopping_bag),
                label: Text(_procesando ? 'Verificando...' : 'Proceder al pago'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _procederPago() async {
    setState(() {
      _error = null;
      _procesando = true;
    });
    final items = List.of(_carrito.items);
    double total = 0;
    for (final item in items) {
      total += item.precio * item.cantidad;
    }
    try {
      final compra = CompraDigitalCreate(
        sucursalId: 1,
        pasarela: 'stripe',
        items: [
          for (final i in items)
            CompraItemCreate(varianteId: i.varianteId, cantidad: i.cantidad),
        ],
      );
      final sesion = await VentasService.crearCheckout(
        compra,
        returnUrl: 'fashionstore://pago/confirmacion',
      );
      final cfg = await VentasService.configPublica();
      if (!mounted) return;

      if (!sesion.simulado && sesion.checkoutUrl != null) {
        // Pasarela real: abrir el Checkout alojado de Stripe en el navegador.
        await launchUrl(
          Uri.parse(sesion.checkoutUrl!),
          mode: LaunchMode.externalApplication,
        );
        await _carrito.limpiar();
        if (!mounted) return;
        // Al volver de Stripe, el deep link dispara la confirmación; aquí
        // descartamos el carrito y pasamos al historial.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => CarritoScreen(),
          ),
        );
        return;
      }

      final res = await Navigator.of(context).push<CompraConfirmada>(
        MaterialPageRoute(
          builder: (_) => PasarelaPagoScreen(
            intencion: IntencionPago(monto: total, id: sesion.sessionId, clientSecret: '', simulado: true),
            publishableKey: cfg.stripePublishableKey,
            pasarelaSimulada: cfg.pasarelaSimulada,
            compra: compra,
          ),
        ),
      );
      if (!mounted) return;
      if (res != null) {
        await _carrito.limpiar();
        setState(() {
          _procesando = false;
          _pedidoId = res.idPedido;
        });
      } else {
        setState(() => _procesando = false);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _procesando = false;
        _error = e.message;
      });
    }
  }
}

class _MiniImagen extends StatelessWidget {
  const _MiniImagen({this.imagenUrl});

  final String? imagenUrl;

  @override
  Widget build(BuildContext context) {
    final url = imagenUrl;
    if (url == null || url.isEmpty) return _placeholder(context);
    return Image.network(
      url,
      width: 64,
      height: 64,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.checkroom,
        size: 28,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}