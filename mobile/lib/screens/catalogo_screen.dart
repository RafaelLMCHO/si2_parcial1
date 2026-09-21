import 'package:flutter/material.dart';

import '../models/producto.dart';
import '../services/auth_service.dart';
import '../services/carrito_service.dart';
import '../services/catalogo_service.dart';
import '../services/ia_service.dart';
import 'carrito_screen.dart';
import 'bitacora_screen.dart';
import 'login_screen.dart';
import 'mis_reservas_screen.dart';
import 'producto_detalle_screen.dart';
import 'reportes_screen.dart';

class CatalogoScreen extends StatefulWidget {
  const CatalogoScreen({super.key});

  @override
  State<CatalogoScreen> createState() => _CatalogoScreenState();
}

class _CatalogoScreenState extends State<CatalogoScreen> {
  final _carrito = CarritoService.instance;
  List<Producto>? _productos;
  List<Producto>? _recomendados;
  String? _error;
  bool _esPersonalDeGestion = false;
  bool _esAdmin = false;

  @override
  void initState() {
    super.initState();
    _iniciarCarrito();
    _cargar();
    _cargarRecomendados();
    _cargarRol();
  }

  Future<void> _cargarRol() async {
    final rol = await AuthService.currentRol();
    if (!mounted) return;
    setState(() {
      _esPersonalDeGestion = rol == 'admin' || rol == 'encargado';
      _esAdmin = rol == 'admin';
    });
  }

  Future<void> _iniciarCarrito() async {
    await _carrito.init();
    if (mounted) setState(() {});
  }

  Future<void> _cargar() async {
    setState(() {
      _productos = null;
      _error = null;
    });
    try {
      final lista = await CatalogoService.listarProductos();
      if (!mounted) return;
      setState(() => _productos = lista);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _cargarRecomendados() async {
    try {
      final lista = await IaService.recomendar(limit: 6);
      if (!mounted) return;
      setState(() => _recomendados = lista);
    } catch (_) {
      // La sección de recomendados es opcional: no bloquea el catálogo.
    }
  }

  Future<void> _refrescar() async {
    await Future.wait([_cargar(), _cargarRecomendados()]);
  }

  Future<void> _salir() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _abrirCarrito() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CarritoScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _abrirMisReservas() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MisReservasScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _abrirBitacora() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BitacoraScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _abrirReportes() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ReportesScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _abrirProducto(int idProducto) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductoDetalleScreen(productoId: idProducto),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final productos = _productos;
    final total = _carrito.totalPrendas;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo'),
        actions: [
          if (_esAdmin)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Bitácora (CU-23)',
              onPressed: _abrirBitacora,
            ),
          if (_esPersonalDeGestion)
            IconButton(
              icon: const Icon(Icons.insights_outlined),
              tooltip: 'Reportes y dashboards',
              onPressed: _abrirReportes,
            ),
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Mis reservas',
            onPressed: _abrirMisReservas,
          ),
          Badge(
            label: Text('$total'),
            isLabelVisible: total > 0,
            child: IconButton(
              icon: const Icon(Icons.shopping_cart_outlined),
              tooltip: 'Carrito de reservas',
              onPressed: _abrirCarrito,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: _salir,
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        color: Theme.of(context).colorScheme.error, size: 40),
                    const SizedBox(height: 8),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _cargar,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : productos == null
              ? const Center(child: CircularProgressIndicator())
              : productos.isEmpty
                  ? const Center(
                      child: Text('No hay productos disponibles en este momento.'),
                    )
                  : RefreshIndicator(
                      onRefresh: _refrescar,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          if (_recomendados != null && _recomendados!.isNotEmpty)
                            SliverToBoxAdapter(
                              child: _SeccionRecomendados(
                                productos: _recomendados!,
                                onTap: _abrirProducto,
                              ),
                            ),
                          SliverPadding(
                            padding: const EdgeInsets.all(16),
                            sliver: SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 420,
                                childAspectRatio: 0.72,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, i) => _ProductoCard(
                                  producto: productos[i],
                                  onTap: () =>
                                      _abrirProducto(productos[i].idProducto),
                                ),
                                childCount: productos.length,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }
}

class _SeccionRecomendados extends StatelessWidget {
  const _SeccionRecomendados({required this.productos, required this.onTap});

  final List<Producto> productos;
  final void Function(int idProducto) onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Recomendados para ti',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 220,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: productos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final p = productos[i];
                return SizedBox(
                  width: 160,
                  child: _ProductoCard(
                    producto: p,
                    onTap: () => onTap(p.idProducto),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductoCard extends StatelessWidget {
  const _ProductoCard({required this.producto, required this.onTap});

  final Producto producto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: _ImagenProducto(imagenUrl: producto.imagenUrl),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      producto.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    Text(
                      'Bs. ${producto.precio.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagenProducto extends StatelessWidget {
  const _ImagenProducto({this.imagenUrl});

  final String? imagenUrl;

  @override
  Widget build(BuildContext context) {
    final url = imagenUrl;
    if (url == null || url.isEmpty) {
      return _placeholder(context);
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, _, _) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.checkroom,
          size: 40,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}