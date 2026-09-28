import 'dart:convert';
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
import 'mis_reservas_screen.dart';

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

  String _metodoPago = 'tarjeta';
  String _tipoTarjeta = 'credito';
  QrDigitalResponse? _qrData;
  bool _cargandoQr = false;
  bool _simularRechazo = false;

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
    if (_carrito.disponibles.isEmpty) {
      _mensaje('Todas las prendas del carrito ya están reservadas.');
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
            for (final item in _carrito.disponibles)
              ReservaItemCreate(varianteId: item.varianteId, cantidad: item.cantidad),
          ],
        ),
      );
      await _carrito.marcarReservados(fecha, reserva.idReserva);
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

  Future<void> _abrirMisReservas() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MisReservasScreen()),
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
              const SizedBox(height: 8),
              Text(
                'La guardamos en Mis reservas, donde podés verla o cancelarla.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Text(
                'Número de reserva: #${reserva.idReserva}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _abrirMisReservas,
                icon: const Icon(Icons.event_note),
                label: const Text('Ver mis reservas'),
              ),
              const SizedBox(height: 8),
              TextButton(
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
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _abrirMisReservas,
              icon: const Icon(Icons.event_note),
              label: const Text('Ver mis reservas'),
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
              : '${_carrito.totalDisponibles} prenda(s) a reservar',
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
          onSelectionChanged: (s) => _onCambiarModo(s.first),
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
                  if (item.reservado) ...[
                    const SizedBox(height: 6),
                    _badgeReservado(item),
                  ],
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
                      onPressed: item.reservado
                          ? null
                          : () => _carrito
                              .cambiarCantidad(item.varianteId, item.cantidad - 1)
                              .then((_) => mounted ? setState(() {}) : null),
                    ),
                    Text('${item.cantidad}'),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'Agregar unidad',
                      onPressed: item.reservado
                          ? null
                          : () => _carrito
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

  Widget _badgeReservado(CarritoItem item) {
    final esquema = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: esquema.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Reservado para el ${_fmtFecha(item.reservadoHasta!)}'
        '${item.idReserva == null ? '' : ' · reserva #${item.idReserva}'}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: esquema.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _cardDetalle() {
    final sucursal = _sucursalSel;
    final sinDisponibles = _carrito.disponibles.isEmpty;
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
                onPressed: (_cargando || sinDisponibles) ? null : _confirmar,
                child: _cargando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(sinDisponibles
                        ? 'Todo reservado'
                        : 'Confirmar reserva'),
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

  void _onCambiarModo(_ModoCheckout modo) {
    setState(() {
      _modo = modo;
      _error = null;
    });
    if (modo == _ModoCheckout.compra && _metodoPago == 'qr' && _qrData == null) {
      _cargarQr();
    }
  }

  void _seleccionarMetodoPago(String metodo) {
    setState(() {
      _metodoPago = metodo;
      _error = null;
    });
    if (metodo == 'qr' && _qrData == null) {
      _cargarQr();
    }
  }

  Future<void> _cargarQr() async {
    final items = List.of(_carrito.items);
    if (items.isEmpty) return;
    setState(() {
      _cargandoQr = true;
      _error = null;
    });
    try {
      final compra = CompraDigitalCreate(
        sucursalId: _sucursalId ?? 1,
        tipoPago: 'qr',
        items: [
          for (final i in items)
            CompraItemCreate(varianteId: i.varianteId, cantidad: i.cantidad),
        ],
      );
      final qr = await VentasService.generarQrDigital(compra);
      if (!mounted) return;
      setState(() {
        _qrData = qr;
        _cargandoQr = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoQr = false;
        _qrData = QrDigitalResponse(
          monto: _carrito.items.fold(0.0, (acc, it) => acc + it.precio * it.cantidad),
          qrUrl: '',
          referencia: 'QR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
          moneda: 'BOB',
        );
      });
    }
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
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal'),
                Text('Bs. ${total.toStringAsFixed(2)}'),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Envío a domicilio'),
                Text(
                  'Gratis (Promoción)',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total a pagar',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Bs. ${total.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Selecciona tu método de pago',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _chipMetodo(
                    id: 'tarjeta',
                    titulo: 'Tarjetas',
                    subtitulo: 'Crédito/Débito',
                    icono: Icons.credit_card,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _chipMetodo(
                    id: 'qr',
                    titulo: 'Código QR',
                    subtitulo: 'Simple / Banco',
                    icono: Icons.qr_code_2,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _chipMetodo(
                    id: 'efectivo',
                    titulo: 'Efectivo',
                    subtitulo: 'Contra entrega',
                    icono: Icons.payments,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_metodoPago == 'tarjeta') _panelTarjeta(total)
            else if (_metodoPago == 'qr') _panelQr(total)
            else _panelEfectivo(total),
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

  Widget _chipMetodo({
    required String id,
    required String titulo,
    required String subtitulo,
    required IconData icono,
  }) {
    final sel = _metodoPago == id;
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: () => _seleccionarMetodoPago(id),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: sel ? primary.withOpacity(0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? primary : Colors.grey.shade300,
            width: sel ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icono, color: sel ? primary : Colors.grey.shade700, size: 24),
            const SizedBox(height: 4),
            Text(
              titulo,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: sel ? primary : Colors.black87,
              ),
            ),
            Text(
              subtitulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: sel ? primary : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelTarjeta(double total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const Center(child: Text('Tarjeta de Crédito')),
                selected: _tipoTarjeta == 'credito',
                onSelected: (s) => setState(() => _tipoTarjeta = 'credito'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const Center(child: Text('Tarjeta de Débito')),
                selected: _tipoTarjeta == 'debito',
                onSelected: (s) => setState(() => _tipoTarjeta = 'debito'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E1B4B), Color(0xFF4338CA), Color(0xFF6366F1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.indigo.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _tipoTarjeta == 'debito' ? 'DÉBITO' : 'CRÉDITO',
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const Text('VISA / MASTERCARD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: 32,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.amber.shade400,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '4242 4242 4242 4242',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  letterSpacing: 2,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('CLIENTE REGISTRADO', style: TextStyle(color: Colors.white70, fontSize: 10)),
                  Text('EXP: 12/28', style: TextStyle(color: Colors.white70, fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Simular fallo/rechazo bancario', style: TextStyle(fontSize: 12, color: Colors.black87)),
              Switch(
                value: _simularRechazo,
                onChanged: (v) => setState(() => _simularRechazo = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _procesando ? null : _procesarPago,
            icon: _procesando
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.lock),
            label: Text(_procesando ? 'Procesando pago...' : 'Pagar Bs. ${total.toStringAsFixed(2)} con Tarjeta'),
          ),
        ),
      ],
    );
  }

  Widget _panelQr(double total) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.deepPurple.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.deepPurple.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '📱 Instrucciones de Pago QR:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepPurple),
              ),
              const SizedBox(height: 4),
              const Text(
                '1. Abre la app de tu banco (Banco Unión, BNB, BCP, Mercantil, etc.).\n'
                '2. Escanea el código QR que se muestra abajo.\n'
                '3. Confirma la transferencia y pulsa el botón para validar.',
                style: TextStyle(fontSize: 12, height: 1.4, color: Colors.black87),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.purple.shade200, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              if (_cargandoQr) ...[
                const SizedBox(height: 40),
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Generando código QR dinámico...', style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 40),
              ] else ...[
                _widgetImagenQr(),
                const SizedBox(height: 12),
                Text(
                  'Bs. ${total.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple.shade700,
                  ),
                ),
                Text(
                  _qrData?.referencia ?? 'FASHIONSTORE-QR',
                  style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timer, size: 14, color: Colors.green.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Válido por 15 minutos',
                      style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Simular rechazo de transferencia QR', style: TextStyle(fontSize: 12, color: Colors.black87)),
              Switch(
                value: _simularRechazo,
                onChanged: (v) => setState(() => _simularRechazo = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.deepPurple,
            ),
            onPressed: _procesando ? null : _procesarPago,
            icon: _procesando
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle_outline),
            label: Text(_procesando ? 'Verificando pago QR...' : 'Ya realicé el pago QR (Confirmar)'),
          ),
        ),
      ],
    );
  }

  Widget _widgetImagenQr() {
    final qrUrl = _qrData?.qrUrl ?? '';
    if (qrUrl.startsWith('data:image')) {
      try {
        final base64Str = qrUrl.split(',').last;
        final bytes = base64Decode(base64Str);
        return Image.memory(bytes, width: 190, height: 190, fit: BoxFit.contain);
      } catch (_) {}
    }
    if (qrUrl.startsWith('http')) {
      return Image.network(qrUrl, width: 190, height: 190, fit: BoxFit.contain);
    }
    return Container(
      width: 190,
      height: 190,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Icon(Icons.qr_code_2, size: 100, color: Colors.deepPurple),
      ),
    );
  }

  Widget _panelEfectivo(double total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            children: [
              Icon(Icons.payments, color: Colors.green.shade700, size: 38),
              const SizedBox(height: 6),
              Text(
                'Pago en Efectivo contra entrega',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green.shade900),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tu pedido digital será procesado de inmediato. Podrás pagar en efectivo al momento de recibir tus prendas o al retirarlas en la sucursal.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<int?>(
          initialValue: _sucursalId,
          decoration: const InputDecoration(
            labelText: 'Sucursal de retiro / entrega',
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
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'Por favor ten a mano el monto exacto para agilizar la entrega.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            onPressed: _procesando ? null : _procesarPago,
            icon: _procesando
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.local_shipping),
            label: Text(_procesando ? 'Registrando pedido...' : 'Confirmar en Efectivo (Bs. ${total.toStringAsFixed(2)})'),
          ),
        ),
      ],
    );
  }

  Future<void> _procesarPago() async {
    setState(() {
      _error = null;
      _procesando = true;
    });
    final items = List.of(_carrito.items);
    if (items.isEmpty) {
      setState(() => _procesando = false);
      return;
    }

    if (_simularRechazo) {
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;
      setState(() => _procesando = false);
      _mostrarDialogoRechazo('La transacción fue rechazada por la entidad bancaria. Verifique que cuenta con fondos suficientes o intente con otro método.');
      return;
    }

    String tipoPagoPayload = 'tarjeta_credito';
    if (_metodoPago == 'tarjeta') {
      tipoPagoPayload = _tipoTarjeta == 'debito' ? 'tarjeta_debito' : 'tarjeta_credito';
    } else if (_metodoPago == 'qr') {
      tipoPagoPayload = 'qr';
    } else if (_metodoPago == 'efectivo') {
      tipoPagoPayload = 'efectivo';
    }

    try {
      final compra = CompraDigitalCreate(
        sucursalId: _sucursalId ?? 1,
        tipoPago: tipoPagoPayload,
        items: [
          for (final i in items)
            CompraItemCreate(varianteId: i.varianteId, cantidad: i.cantidad),
        ],
      );
      final res = await VentasService.confirmarCompra(compra);
      await _carrito.limpiar();
      if (!mounted) return;
      setState(() => _procesando = false);
      _mostrarDialogoAprobado(res);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _procesando = false);
      _mostrarDialogoRechazo(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _procesando = false);
      _mostrarDialogoRechazo('Error al procesar el pago: $e');
    }
  }

  void _mostrarDialogoAprobado(CompraConfirmada res) {
    String metodoLabel = 'Tarjeta de Crédito / Débito';
    IconData metodoIcon = Icons.credit_card;
    if (_metodoPago == 'qr') {
      metodoLabel = 'Código QR Simple';
      metodoIcon = Icons.qr_code_2;
    } else if (_metodoPago == 'efectivo') {
      metodoLabel = 'Efectivo contra entrega';
      metodoIcon = Icons.payments;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle, color: Colors.green.shade600, size: 54),
            ),
            const SizedBox(height: 12),
            const Text(
              '¡Pago Aprobado!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _metodoPago == 'efectivo'
                  ? 'Tu pedido digital ha sido registrado exitosamente para cobro contra entrega.'
                  : 'Tu pago digital ha sido procesado y aprobado exitosamente.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Número de pedido:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      Text('#${res.idPedido}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Método de pago:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      Row(
                        children: [
                          Icon(metodoIcon, size: 16, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(metodoLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      Text(
                        'Bs. ${res.total.toStringAsFixed(2)}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary, fontSize: 15),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Estado:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _metodoPago == 'efectivo' ? Colors.amber.shade100 : Colors.green.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _metodoPago == 'efectivo' ? 'PENDIENTE (ENTREGA)' : 'PAGADO',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _metodoPago == 'efectivo' ? Colors.amber.shade900 : Colors.green.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Entendido y volver al catálogo'),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoRechazo(String motivo) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cancel, color: Colors.red.shade600, size: 54),
            ),
            const SizedBox(height: 12),
            const Text(
              'Pago Rechazado',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.red),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No se pudo completar la transacción digital.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                motivo,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade900, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Verifica que tu tarjeta o banca móvil cuente con saldo disponible o intenta con otro método de pago.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cerrar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _procesarPago();
                  },
                  child: const Text('Reintentar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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