import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/carrito.dart';
import '../models/ciudad.dart';
import '../models/producto.dart';
import '../models/sucursal_disponibilidad.dart';
import '../services/carrito_service.dart';
import '../services/catalogo_service.dart';
import '../services/inventario_service.dart';
import '../services/sucursal_service.dart';
import '../services/auth_service.dart';
import 'carrito_screen.dart';
import 'vestidor_virtual_screen.dart';

class ProductoDetalleScreen extends StatefulWidget {
  const ProductoDetalleScreen({super.key, required this.productoId});

  final int productoId;

  @override
  State<ProductoDetalleScreen> createState() => _ProductoDetalleScreenState();
}

class _ProductoDetalleScreenState extends State<ProductoDetalleScreen> {
  Producto? _producto;
  String? _productoError;
  bool _cargandoProducto = true;

  List<Talla> _tallas = [];
  List<Color> _colores = [];
  int? _tallaSel;
  int? _colorSel;

  List<SucursalDisponibilidad> _disponibilidad = [];
  List<Ciudad> _ciudades = [];
  int? _ciudadSel;
  bool _cargandoDisp = false;
  String? _errorDisp;

  @override
  void initState() {
    super.initState();
    _cargarProducto();
    _cargarCiudades();
  }

  Future<void> _cargarProducto() async {
    setState(() {
      _cargandoProducto = true;
      _productoError = null;
    });
    try {
      final producto = await CatalogoService.verProducto(widget.productoId);
      if (!mounted) return;
      setState(() {
        _producto = producto;
        _cargandoProducto = false;
        _prepararVariantes(producto);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoProducto = false;
        _productoError = e.toString();
      });
    }
  }

  void _prepararVariantes(Producto producto) {
    final tallas = <int, Talla>{};
    final colores = <int, Color>{};
    for (final v in producto.variantes) {
      if (v.talla != null) tallas[v.talla!.idTalla] = v.talla!;
      if (v.color != null) colores[v.color!.idColor] = v.color!;
    }
    _tallas = tallas.values.toList();
    _colores = colores.values.toList();
    if (_tallas.isNotEmpty) _tallaSel = _tallas.first.idTalla;
    if (_colores.isNotEmpty) _colorSel = _colores.first.idColor;
    _cargarDisponibilidad();
  }

  Future<void> _cargarCiudades() async {
    try {
      final ciudades = await SucursalService.ciudades();
      if (!mounted) return;
      setState(() => _ciudades = ciudades);
    } catch (_) {}
  }

  ProductoVariante? _encontrarVariante() {
    final colorId = _colorSel;
    final tallaId = _tallaSel;
    if (colorId == null || tallaId == null) return null;
    for (final v in _producto!.variantes) {
      if (v.colorId == colorId && v.tallaId == tallaId) return v;
    }
    return null;
  }

  Future<void> _cargarDisponibilidad() async {
    final variante = _encontrarVariante();
    if (variante == null) {
      setState(() {
        _disponibilidad = [];
        _errorDisp = null;
      });
      return;
    }
    setState(() {
      _cargandoDisp = true;
      _errorDisp = null;
    });
    try {
      final lista = await InventarioService.disponibilidad(
        variante.idVariante,
        ciudadId: _ciudadSel,
      );
      if (!mounted) return;
      setState(() {
        _disponibilidad = lista;
        _cargandoDisp = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoDisp = false;
        _errorDisp = e is ApiException && e.status == 401
            ? 'Inicia sesión para consultar disponibilidad por sucursal.'
            : 'Error al cargar disponibilidad, intente de nuevo.';
      });
    }
  }

  void _onTalla(int? id) {
    setState(() => _tallaSel = id);
    _cargarDisponibilidad();
  }

  void _onColor(int? id) {
    setState(() => _colorSel = id);
    _cargarDisponibilidad();
  }

  void _onCiudad(int? id) {
    setState(() => _ciudadSel = id);
    _cargarDisponibilidad();
  }

  Future<void> _agregarCarrito() async {
    final producto = _producto;
    if (producto == null) return;
    final variante = _encontrarVariante();
    if (variante == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Elige la talla y el color antes de agregar al carrito.'),
        ),
      );
      return;
    }
    await CarritoService.instance.agregar(
      CarritoItem(
        varianteId: variante.idVariante,
        cantidad: 1,
        nombre: producto.nombre,
        sku: variante.sku,
        color: variante.color?.nombre,
        talla: variante.talla?.nombre,
        precio: producto.precio,
        imagenUrl: producto.imagenUrl,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Prenda agregada al carrito de reservas.'),
        action: SnackBarAction(
          label: 'Ver carrito',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CarritoScreen()),
            );
          },
        ),
      ),
    );
  }

  Future<void> _abrirVestidor(Producto producto) async {
    final rol = await AuthService.currentRol();
    if (!mounted) return;
    if (rol == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inicia sesión para usar el vestidor virtual.'),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VestidorVirtualScreen(
          productoId: producto.idProducto,
          productoNombre: producto.nombre,
          precio: producto.precio,
          modeloUrl: ApiClient.resolveMediaUrl(producto.modelo3dUrl!),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del producto')),
      body: _cargandoProducto
          ? const Center(child: CircularProgressIndicator())
          : _productoError != null
              ? _CentroError(
                  mensaje: _productoError!,
                  onReintentar: _cargarProducto,
                )
              : _contenido(),
    );
  }

  Widget _contenido() {
    final producto = _producto!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _ImagenProducto(
                        imagenUrl: producto.imagenUrl, alto: 220),
                  ),
                ),
                const SizedBox(height: 16),
                Text(producto.nombre,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Bs. ${producto.precio.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
                if (producto.descripcion != null &&
                    producto.descripcion!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(producto.descripcion!),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _agregarCarrito,
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Agregar a carrito de reservas'),
                  ),
                ),
                if ((producto.modelo3dUrl ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _abrirVestidor(producto),
                      icon: const Icon(Icons.view_in_ar),
                      label: const Text('Probar con vestidor virtual (RA)'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (producto.variantes.isNotEmpty) _cardDisponibilidad(),
      ],
    );
  }

  Widget _cardDisponibilidad() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Disponibilidad por sucursal',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Elige talla y color para consultar el stock en cada sucursal.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _tallaSel,
                    decoration: const InputDecoration(
                      labelText: 'Talla',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final t in _tallas)
                        DropdownMenuItem(value: t.idTalla, child: Text(t.nombre)),
                    ],
                    onChanged: _onTalla,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _colorSel,
                    decoration: const InputDecoration(
                      labelText: 'Color',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final c in _colores)
                        DropdownMenuItem(value: c.idColor, child: Text(c.nombre)),
                    ],
                    onChanged: _onColor,
                  ),
                ),
              ],
            ),
            if (_ciudades.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _ciudadSel,
                decoration: const InputDecoration(
                  labelText: 'Filtrar por ciudad',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Todas las ciudades')),
                  for (final c in _ciudades)
                    DropdownMenuItem<int?>(value: c.idCiudad, child: Text(c.nombre)),
                ],
                onChanged: _onCiudad,
              ),
            ],
            const SizedBox(height: 16),
            if (_cargandoDisp)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else if (_errorDisp != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _errorDisp!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              )
            else if (_disponibilidad.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Este producto no está disponible en ninguna tienda.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              for (final d in _disponibilidad) _filaSucursal(d),
          ],
        ),
      ),
    );
  }

  Widget _filaSucursal(SucursalDisponibilidad d) {
    final chipColor = d.estado == 'Disponible'
        ? Colors.green.shade100
        : Colors.orange.shade100;
    final chipText = d.estado == 'Disponible'
        ? Colors.green.shade900
        : Colors.orange.shade900;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(d.nombreSucursal,
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: chipColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  d.estado,
                  style: TextStyle(
                    color: chipText,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            d.ciudad,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _dato('Disponible', '${d.cantidadDisponible}'),
              _dato('Reservadas', '${d.cantidadReservada}'),
              _dato('Próximas a ingresar', '${d.cantidadRecibida}'),
              _dato('Stock mínimo', '${d.stockMinimo}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dato(String label, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.outline,
            )),
        Text(valor,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      ],
    );
  }
}

class _ImagenProducto extends StatelessWidget {
  const _ImagenProducto({this.imagenUrl, required this.alto});

  final String? imagenUrl;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final url = imagenUrl;
    if (url == null || url.isEmpty) return _placeholder(context);
    return Image.network(
      url,
      height: alto,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      height: alto,
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.checkroom,
          size: 48,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

class _CentroError extends StatelessWidget {
  const _CentroError({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error, size: 40),
            const SizedBox(height: 8),
            Text(mensaje, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onReintentar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}