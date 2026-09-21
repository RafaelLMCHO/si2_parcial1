import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/reporte.dart';
import '../models/sucursal.dart';
import '../services/auth_service.dart';
import '../services/catalogo_service.dart';
import '../services/reportes_service.dart';
import '../services/sucursal_service.dart';

const List<Color> _paleta = [
  Color(0xFF4F46E5),
  Color(0xFF7C3AED),
  Color(0xFFDB2777),
  Color(0xFFEA580C),
  Color(0xFFF59E0B),
  Color(0xFF16A34A),
  Color(0xFF0891B2),
  Color(0xFF2563EB),
  Color(0xFF9333EA),
  Color(0xFFE11D48),
];

String _acortar(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…';

class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  bool _esEncargado = false;
  int? _sucursalFijaId;

  bool _cargandoFiltros = true;
  bool _generando = false;
  bool _generado = false;
  String? _error;

  DateTime? _desde;
  DateTime? _hasta;
  int? _categoriaId;
  int? _temporadaId;
  int? _sucursalId;

  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _temporadas = [];
  List<Sucursal> _sucursales = [];

  ResumenReporte? _resumen;
  List<VentaSucursalRow> _ventas = [];
  List<MasVendidoRow> _masVendidos = [];
  List<RotacionRow> _rotacion = [];
  List<StockCriticoRow> _stockCritico = [];
  ReservasReporte? _reservas;
  List<TendenciaRow> _tendencias = [];

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    final rol = await AuthService.currentRol();
    final sucursalId = await AuthService.currentSucursalId();
    if (!mounted) return;
    setState(() {
      _esEncargado = rol == 'encargado';
      _sucursalFijaId = _esEncargado ? sucursalId : null;
      if (_esEncargado) _sucursalId = sucursalId;
    });
    try {
      final categorias = await CatalogoService.listarCategorias();
      final temporadas = await CatalogoService.listarTemporadas();
      final sucs = _esEncargado
          ? <Sucursal>[]
          : await SucursalService.sucursales();
      if (!mounted) return;
      setState(() {
        _categorias = categorias;
        _temporadas = temporadas;
        _sucursales = sucs;
        _cargandoFiltros = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoFiltros = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _seleccionarFecha({required bool desde}) async {
    final actual = desde ? _desde : _hasta;
    final picked = await showDatePicker(
      context: context,
      initialDate: actual ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    setState(() {
      if (desde) {
        _desde = picked;
      } else {
        _hasta = picked;
      }
    });
  }

  String _fmtFecha(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _generar() async {
    final desde = _desde;
    final hasta = _hasta;
    if (desde != null && hasta != null && desde.isAfter(hasta)) {
      setState(() {
        _error = 'La fecha de inicio no puede ser mayor que la fecha de fin';
      });
      return;
    }
    setState(() {
      _generando = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ReportesService.resumen(
          fechaDesde: desde == null ? null : _fmtFecha(desde),
          fechaHasta: hasta == null ? null : _fmtFecha(hasta),
          sucursalId: _sucursalId,
          categoriaId: _categoriaId,
          temporadaId: _temporadaId,
        ),
        ReportesService.ventasPorSucursal(
          fechaDesde: desde == null ? null : _fmtFecha(desde),
          fechaHasta: hasta == null ? null : _fmtFecha(hasta),
          sucursalId: _sucursalId,
          categoriaId: _categoriaId,
          temporadaId: _temporadaId,
        ),
        ReportesService.masVendidos(
          fechaDesde: desde == null ? null : _fmtFecha(desde),
          fechaHasta: hasta == null ? null : _fmtFecha(hasta),
          sucursalId: _sucursalId,
          categoriaId: _categoriaId,
          temporadaId: _temporadaId,
        ),
        ReportesService.rotacionInventario(
          fechaDesde: desde == null ? null : _fmtFecha(desde),
          fechaHasta: hasta == null ? null : _fmtFecha(hasta),
          sucursalId: _sucursalId,
          categoriaId: _categoriaId,
          temporadaId: _temporadaId,
        ),
        ReportesService.stockCritico(
          fechaDesde: desde == null ? null : _fmtFecha(desde),
          fechaHasta: hasta == null ? null : _fmtFecha(hasta),
          sucursalId: _sucursalId,
          categoriaId: _categoriaId,
          temporadaId: _temporadaId,
        ),
        ReportesService.reservas(
          fechaDesde: desde == null ? null : _fmtFecha(desde),
          fechaHasta: hasta == null ? null : _fmtFecha(hasta),
          sucursalId: _sucursalId,
          categoriaId: _categoriaId,
          temporadaId: _temporadaId,
        ),
        ReportesService.tendencias(
          fechaDesde: desde == null ? null : _fmtFecha(desde),
          fechaHasta: hasta == null ? null : _fmtFecha(hasta),
          sucursalId: _sucursalId,
          categoriaId: _categoriaId,
          temporadaId: _temporadaId,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _resumen = results[0] as ResumenReporte;
        _ventas = results[1] as List<VentaSucursalRow>;
        _masVendidos = results[2] as List<MasVendidoRow>;
        _rotacion = results[3] as List<RotacionRow>;
        _stockCritico = results[4] as List<StockCriticoRow>;
        _reservas = results[5] as ReservasReporte;
        _tendencias = results[6] as List<TendenciaRow>;
        _generado = true;
        _generando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generando = false;
        _error = e.toString();
      });
    }
  }

  bool get _sinDatos =>
      _generado &&
      !_generando &&
      (_resumen == null ||
          (_resumen!.ventasTotal == 0 &&
              _resumen!.totalPedidos == 0 &&
              _resumen!.stockCritico == 0 &&
              _resumen!.reservasActivas == 0));

  Future<void> _exportarCSV() async {
    final resumen = _resumen;
    if (resumen == null) return;
    final buf = StringBuffer();
    buf.writeln('FashionStore - Reporte generado');
    buf.writeln();
    buf.writeln('RESUMEN EJECUTIVO');
    buf.writeln('Ventas totales (Bs),${resumen.ventasTotal.toStringAsFixed(2)}');
    buf.writeln('Pedidos,${resumen.totalPedidos}');
    buf.writeln('Productos activos,${resumen.totalProductos}');
    buf.writeln('Stock critico,${resumen.stockCritico}');
    buf.writeln('Reservas activas,${resumen.reservasActivas}');
    buf.writeln();
    buf.writeln('Ventas por sucursal');
    for (final v in _ventas) {
      buf.writeln('${v.sucursal},${v.total.toStringAsFixed(2)}');
    }
    buf.writeln();
    buf.writeln('Productos mas vendidos');
    buf.writeln('Producto,Categoria,Unidades,Monto');
    for (final v in _masVendidos) {
      buf.writeln(
          '${v.producto},${v.categoria},${v.unidades},${v.monto.toStringAsFixed(2)}');
    }
    buf.writeln();
    buf.writeln('Rotacion de inventario');
    buf.writeln('Producto,Unidades vendidas,Stock actual,Rotacion');
    for (final v in _rotacion) {
      buf.writeln('${v.producto},${v.unidadesVendidas},${v.stockActual},${v.rotacion}');
    }
    buf.writeln();
    buf.writeln('Stock critico');
    buf.writeln('Producto,Talla,Color,SKU,Sucursal,Stock minimo,Disponible,Faltante');
    for (final v in _stockCritico) {
      buf.writeln(
          '${v.producto},${v.talla},${v.color},${v.sku},${v.sucursal},${v.stockMinimo},${v.disponible},${v.faltante}');
    }
    try {
      await SharePlus.instance.share(ShareParams(
        text: buf.toString(),
        subject: 'Reporte FashionStore',
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al compartir el archivo, intente de nuevo'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes y Dashboards'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Exportar CSV',
            onPressed: _generado && _resumen != null ? _exportarCSV : null,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _seccionFiltros(),
          const SizedBox(height: 12),
          if (_error != null) _anexoError(context),
          if (_generando) const _CargandoReporte(),
          if (_sinDatos) _anexoVacio(context),
          if (_generado && !_generando && !_sinDatos && _resumen != null) ...[
            _seccionKpis(context),
            const SizedBox(height: 16),
            _seccionGraficos(context),
            const SizedBox(height: 16),
            if (_stockCritico.isNotEmpty) _seccionStockCritico(context),
            const SizedBox(height: 16),
            if (_rotacion.isNotEmpty) _seccionRotacion(context),
          ],
        ],
      ),
    );
  }

  Widget _seccionFiltros() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Filtros', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _cargandoFiltros ? null : () => _seleccionarFecha(desde: true),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      _desde == null ? 'Desde' : 'Desde ${_fmtFecha(_desde!)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _cargandoFiltros ? null : () => _seleccionarFecha(desde: false),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      _hasta == null ? 'Hasta' : 'Hasta ${_fmtFecha(_hasta!)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              initialValue: _categoriaId,
              decoration: const InputDecoration(
                labelText: 'Categoría',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Todas')),
                ..._categorias.map((c) => DropdownMenuItem<int?>(
                      value: (c['id_categoria'] as num).toInt(),
                      child: Text(c['nombre'] as String? ?? ''),
                    )),
              ],
              onChanged: (v) => setState(() => _categoriaId = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              initialValue: _temporadaId,
              decoration: const InputDecoration(
                labelText: 'Temporada',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Todas')),
                ..._temporadas.map((t) => DropdownMenuItem<int?>(
                      value: (t['id_temporada'] as num).toInt(),
                      child: Text(t['nombre'] as String? ?? ''),
                    )),
              ],
              onChanged: (v) => setState(() => _temporadaId = v),
            ),
            if (_esEncargado)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _sucursalFijaId == null
                      ? 'No tiene sucursal asignada, contacte al administrador'
                      : 'Sucursal fija: #$_sucursalFijaId',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                initialValue: _sucursalId,
                decoration: const InputDecoration(
                  labelText: 'Sucursal',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Todas')),
                  ..._sucursales.map((s) => DropdownMenuItem<int?>(
                        value: s.idSucursal,
                        child: Text(
                          _acortar(s.nombre.replaceFirst('FashionStore ', ''), 34),
                        ),
                      )),
                ],
                onChanged: (v) => setState(() => _sucursalId = v),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _generando ? null : _generar,
              icon: _generando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.query_stats),
              label: Text(_generando ? 'Generando...' : 'Generar reporte'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _anexoError(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!)),
          ],
        ),
      ),
    );
  }

  Widget _anexoVacio(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 40, color: Colors.grey),
              SizedBox(height: 8),
              Text('No hay información disponible para los criterios seleccionados.'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seccionKpis(BuildContext context) {
    final r = _resumen!;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.9,
      children: [
        _KpiCard(
          icon: Icons.payments_outlined,
          label: 'Ventas del período',
          value: 'Bs. ${r.ventasTotal.toStringAsFixed(2)}',
        ),
        _KpiCard(
          icon: Icons.receipt_long_outlined,
          label: 'Pedidos',
          value: '${r.totalPedidos}',
        ),
        _KpiCard(
          icon: Icons.warning_amber_outlined,
          label: 'Stock crítico',
          value: '${r.stockCritico}',
          warn: r.stockCritico > 0,
        ),
        _KpiCard(
          icon: Icons.calendar_month_outlined,
          label: 'Reservas activas',
          value: '${r.reservasActivas}',
        ),
      ],
    );
  }

  Widget _seccionGraficos(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GraficoCard(
          titulo: 'Ventas por sucursal',
          child: _barChart(
            _ventas.map((v) => _acortar(v.sucursal.replaceFirst('FashionStore ', ''), 15)).toList(),
            _ventas.map((v) => v.total).toList(),
            'Bs.',
          ),
        ),
        const SizedBox(height: 12),
        _GraficoCard(
          titulo: 'Productos más vendidos',
          child: _barChart(
            _masVendidos.map((v) => _acortar(v.producto, 15)).toList(),
            _masVendidos.map((v) => v.unidades.toDouble()).toList(),
            'un.',
          ),
        ),
        const SizedBox(height: 12),
        _GraficoCard(
          titulo: 'Reservas por estado',
          child: _pieChart(),
        ),
        const SizedBox(height: 12),
        _GraficoCard(
          titulo: 'Tendencias por temporada',
          child: _barChart(
            _tendencias.map((t) => _acortar(t.temporada, 15)).toList(),
            _tendencias.map((t) => t.monto).toList(),
            'Bs.',
          ),
        ),
      ],
    );
  }

  Widget _barChart(List<String> labels, List<double> values, String prefijo) {
    final maxV = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxV == 0 ? 1.0 : maxV * 1.2,
          barGroups: [
            for (var i = 0; i < values.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i],
                    width: 22,
                    color: _paleta[i % _paleta.length],
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 40),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                  return RotatedBox(
                    quarterTurns: 1,
                    child: Text(
                      labels[i],
                      style: const TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.black87,
              getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(
                '$prefijo${rod.toY.toStringAsFixed(2)}',
                const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pieChart() {
    final datos = _reservas?.porEstado ?? [];
    return SizedBox(
      height: 220,
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 34,
          sections: [
            for (var i = 0; i < datos.length; i++)
              PieChartSectionData(
                value: datos[i].total.toDouble(),
                title: '${datos[i].estado}\n${datos[i].total}',
                color: _paleta[i % _paleta.length],
                radius: 44,
                titleStyle: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _seccionStockCritico(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Niveles de stock crítico (${_stockCritico.length})',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final s in _stockCritico.take(20))
              ListTile(
                dense: true,
                leading: Icon(
                  s.disponible == 0 ? Icons.error_outline : Icons.warning_amber_outlined,
                  color: s.disponible == 0 ? Colors.red : Colors.orange,
                ),
                title: Text('${s.producto} (${s.talla} · ${s.color})'),
                subtitle: Text('${s.sucursal} · SKU ${s.sku}'),
                trailing: Text(
                  'disp. ${s.disponible}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: s.disponible == 0 ? Colors.red : Colors.black87,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _seccionRotacion(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rotación de inventario', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Rotación = unidades vendidas / stock actual',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final r in _rotacion.take(10))
              ListTile(
                dense: true,
                title: Text(r.producto),
                trailing: Text(
                  '${r.rotacion.toStringAsFixed(2)}x',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    this.warn = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final color = warn ? const Color(0xFFEA580C) : Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 6),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _CargandoReporte extends StatelessWidget {
  const _CargandoReporte();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _GraficoCard extends StatelessWidget {
  const _GraficoCard({required this.titulo, required this.child});

  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}