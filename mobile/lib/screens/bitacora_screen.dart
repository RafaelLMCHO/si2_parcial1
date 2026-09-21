import 'package:flutter/material.dart';

import '../models/bitacora.dart';
import '../services/bitacora_service.dart';

class BitacoraScreen extends StatefulWidget {
  const BitacoraScreen({super.key});

  @override
  State<BitacoraScreen> createState() => _BitacoraScreenState();
}

class _BitacoraScreenState extends State<BitacoraScreen> {
  final _accionCtrl = TextEditingController();
  final _entidadCtrl = TextEditingController();

  List<RegistroBitacora> _registros = [];
  int _total = 0;
  bool _cargando = false;
  String? _error;
  DateTime? _desde;
  DateTime? _hasta;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _accionCtrl.dispose();
    _entidadCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool reiniciar = true}) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final result = await BitacoraService.listar(
        accion: _accionCtrl.text.trim(),
        entidad: _entidadCtrl.text.trim(),
        fechaDesde: _desde == null ? null : _fechaSql(_desde!),
        fechaHasta: _hasta == null ? null : _fechaSql(_hasta!),
        pagina: reiniciar ? 1 : (_aplicadas + 1),
      );
      if (!mounted) return;
      setState(() {
        _registros =
            reiniciar ? result.registros : [..._registros, ...result.registros];
        _total = result.total;
        _aplicadas = reiniciar ? 1 : (_aplicadas + 1);
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.toString();
      });
    }
  }

  int _aplicadas = 1;

  void _buscar() => _cargar(reiniciar: true);

  void _limpiar() {
    _accionCtrl.clear();
    _entidadCtrl.clear();
    setState(() {
      _desde = null;
      _hasta = null;
    });
    _cargar(reiniciar: true);
  }

  Future<void> _elegirDesde() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _desde ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (p != null) setState(() => _desde = p);
  }

  Future<void> _elegirHasta() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _hasta ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (p != null) setState(() => _hasta = p);
  }

  String _fechaSql(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fechaLegible(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bitácora'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            onPressed: _buscar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _accionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Acción',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _buscar(),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _entidadCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Entidad',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _buscar(),
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.arrow_left),
                  label: Text(_desde == null ? 'Desde: -' : _fechaLegible(_desde!)),
                  onPressed: _elegirDesde,
                ),
                ActionChip(
                  avatar: const Icon(Icons.arrow_right),
                  label: Text(_hasta == null ? 'Hasta: -' : _fechaLegible(_hasta!)),
                  onPressed: _elegirHasta,
                ),
                FilledButton.icon(
                  onPressed: _cargando ? null : _buscar,
                  icon: const Icon(Icons.search),
                  label: const Text('Buscar'),
                ),
                OutlinedButton.icon(
                  onPressed: _cargando ? null : _limpiar,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Limpiar'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$_total registro${_total == 1 ? '' : 's'} en total · mostrando ${_registros.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const Divider(),
          Expanded(child: _cuerpo(scheme)),
        ],
      ),
    );
  }

  Widget _cuerpo(ColorScheme scheme) {
    if (_cargando && _registros.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: scheme.error, size: 40),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _buscar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    if (_registros.isEmpty) {
      return const Center(child: Text('No hay registros para los criterios seleccionados.'));
    }
    return RefreshIndicator(
      onRefresh: () => _cargar(reiniciar: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        children: [
          for (final r in _registros) _tarjeta(r),
          if (_registros.length < _total)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: _cargando
                    ? const CircularProgressIndicator()
                    : OutlinedButton.icon(
                        onPressed: () => _cargar(reiniciar: false),
                        icon: const Icon(Icons.more_horiz),
                        label: const Text('Cargar más'),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tarjeta(RegistroBitacora r) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(Icons.history, color: scheme.onPrimaryContainer, size: 20),
        ),
        title: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              r.accion,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              '${r.fecha.day.toString().padLeft(2, '0')}/${r.fecha.month.toString().padLeft(2, '0')}/${r.fecha.year} ${r.fecha.hour.toString().padLeft(2, '0')}:${r.fecha.minute.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Usuario: ${r.usuarioLabel}'),
            if (r.entidad != null)
              Text(
                'Entidad: ${r.entidad}${r.entidadId != null ? ' #${r.entidadId}' : ''}',
              ),
            if (r.detalle != null && r.detalle!.isNotEmpty)
              Text(r.detalle!, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (r.ipOrigen != null) Text('IP: ${r.ipOrigen}'),
          ].map((w) => Padding(padding: const EdgeInsets.only(bottom: 2), child: w)).toList(),
        ),
        isThreeLine: true,
      ),
    );
  }
}