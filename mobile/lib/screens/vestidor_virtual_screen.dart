import 'dart:math' as math;

import 'package:arcore_flutter_plus/arcore_flutter_plus.dart' as ar;
import 'package:arcore_flutter_plus/arcore_flutter_plus.dart'
    show ArCoreViewType;
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../services/bitacora_service.dart';

/// CU-07 · Vestidor virtual (RA).
///
/// Intenta abrir la cámara con ARCore (coloca el modelo 3D sobre el plano
/// detectado). Si el dispositivo no soporta ARCore, o ante cualquier error,
/// cae automáticamente al visor 3D interactivo. La consulta se registra en la
/// bitácora (CU-23) y el cliente puede compartir la prenda.
class VestidorVirtualScreen extends StatefulWidget {
  const VestidorVirtualScreen({
    super.key,
    required this.productoId,
    required this.productoNombre,
    required this.precio,
    required this.modeloUrl,
  });

  final int productoId;
  final String productoNombre;
  final double precio;
  final String modeloUrl;

  @override
  State<VestidorVirtualScreen> createState() => _VestidorVirtualScreenState();
}

class _VestidorVirtualScreenState extends State<VestidorVirtualScreen> {
  static const String _nombreNodo = 'prenda_vestidor';

  /// `true`=AR disponible, `false`=visor 3D, `null`=decidiendo.
  bool? _modoAr;
  ar.ArCoreController? _ar;
  bool _errorAr = false;

  Vector3? _ultimaPosicion;
  double _rotacionGrados = 0;
  double _escala = 1.0;

  bool _bitacoraRegistrada = false;

  @override
  void initState() {
    super.initState();
    _decidirModo();
  }

  Future<void> _decidirModo() async {
    if (!mounted) return;
    var disponible = false;
    try {
      disponible = await ar.ArCoreController.checkArCoreAvailability();
    } catch (_) {
      disponible = false;
    }
    if (!mounted) return;
    setState(() => _modoAr = disponible);
  }

  void _onArCoreViewCreated(ar.ArCoreController controller) {
    _ar = controller;
    controller.onPlaneTap = _onPlaneTap;
    controller.onError = (mensaje) {
      if (!mounted) return;
      setState(() => _errorAr = true);
      _usarVisor3D();
      _mostrar('ARCore no disponible: $mensaje. Usando visor 3D.');
    };
    _registrarBitacora();
  }

  Future<void> _onPlaneTap(List<ar.ArCoreHitTestResult> hits) async {
    if (hits.isEmpty || _ar == null) return;
    final hit = hits.first;
    await _colocar(hit.pose.translation, cuaternio: hit.pose.rotation);
  }

  Vector4 get _cuaternioUsuario {
    final rad = _rotacionGrados * math.pi / 180;
    final mitad = rad / 2;
    return Vector4(0, math.sin(mitad), 0, math.cos(mitad));
  }

  /// Producto de dos cuaterniones (vector_math no lo expone).
  Vector4 _mulQuaternios(Vector4 a, Vector4 b) {
    return Vector4(
      a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
      a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
      a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
      a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    );
  }

  Future<void> _colocar(Vector3 posicion, {Vector4? cuaternio}) async {
    final controller = _ar;
    if (controller == null || !mounted) return;
    _ultimaPosicion = posicion.clone();
    try {
      await controller.removeNode(nodeName: _nombreNodo);
      final rotacionFinal = cuaternio == null
          ? _cuaternioUsuario
          : _mulQuaternios(cuaternio, _cuaternioUsuario);
      final nodo = ar.ArCoreReferenceNode(
        name: _nombreNodo,
        objectUrl: widget.modeloUrl,
        position: posicion,
        scale: Vector3(1, 1, 1) * _escala,
        rotation: rotacionFinal,
      );
      await controller.addArCoreNodeWithAnchor(nodo);
    } catch (_) {
      if (mounted) _mostrar('No se pudo colocar el modelo. Mueve el teléfono para detectar el suelo.');
    }
    _registrarBitacora();
  }

  Future<void> _girar() async {
    setState(() => _rotacionGrados = (_rotacionGrados + 45) % 360);
    final pos = _ultimaPosicion;
    if (pos != null) await _colocar(pos);
  }

  Future<void> _cambiarEscala() async {
    const opciones = [1.0, 1.5, 0.6];
    final idx = opciones.indexOf(_escala);
    setState(() => _escala = opciones[(idx + 1) % opciones.length]);
    final pos = _ultimaPosicion;
    if (pos != null) await _colocar(pos);
  }

  Future<void> _quitarModelo() async {
    final controller = _ar;
    if (controller == null) return;
    await controller.removeNode(nodeName: _nombreNodo);
  }

  void _registrarBitacora() {
    if (_bitacoraRegistrada) return;
    _bitacoraRegistrada = true;
    BitacoraService.registrarConsultaVestidor(
      productoId: widget.productoId,
      nombre: widget.productoNombre,
      modo: _modoAr == true ? 'ARCore' : 'Visor 3D',
    );
  }

  void _usarVisor3D() {
    setState(() => _modoAr = false);
    _registrarBitacora();
  }

  void _compartir() {
    SharePlus.instance.share(ShareParams(
      subject: widget.productoNombre,
      text:
          'Probé "${widget.productoNombre}" con el vestidor virtual de FashionStore '
          '(Bs. ${widget.precio.toStringAsFixed(2)}). ¿Te gusta?',
    ));
  }

  void _mostrar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Vestidor virtual — ${widget.productoNombre}'),
        actions: [
          IconButton(
            tooltip: 'Compartir prenda',
            onPressed: _compartir,
            icon: const Icon(Icons.share),
          ),
        ],
      ),
      body: switch (_modoAr) {
        null => const Center(child: CircularProgressIndicator()),
        false => _visor3D(),
        true => _errorAr ? _visor3D() : _modoARNativo(),
      },
    );
  }

  Widget _modoARNativo() {
    return Stack(
      fit: StackFit.expand,
      children: [
        ar.ArCoreView(
          onArCoreViewCreated: _onArCoreViewCreated,
          type: ArCoreViewType.STANDARDVIEW,
          enableTapRecognizer: true,
          enablePlaneRenderer: true,
          planeColor: Colors.teal,
          debug: false,
        ),
        const Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: _Chip([
            'Mueve el teléfono para detectar el suelo y toca para colocar la prenda.'
          ]),
        ),
        if (_ultimaPosicion != null)
          Positioned(
            left: 16,
            bottom: 96,
            child: _BotonRedondo(
              tooltip: 'Girar 45°',
              icon: Icons.rotate_right,
              onPressed: _girar,
            ),
          ),
        Positioned(
          left: 72,
          bottom: 96,
          child: _BotonRedondo(
            tooltip: 'Cambiar escala',
            icon: Icons.aspect_ratio,
            onPressed: _cambiarEscala,
          ),
        ),
        Positioned(
          left: 128,
          bottom: 96,
          child: _BotonRedondo(
            tooltip: 'Quitar modelo',
            icon: Icons.delete_outline,
            onPressed: _quitarModelo,
          ),
        ),
        Positioned(
          right: 16,
          bottom: 24,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
            ),
            onPressed: _usarVisor3D,
            icon: const Icon(Icons.view_in_ar),
            label: const Text('Ver en 3D'),
          ),
        ),
      ],
    );
  }

  Widget _visor3D() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: const Color(0xFFE8EAF6)),
        ModelViewer(
          src: widget.modeloUrl,
          alt: widget.productoNombre,
          cameraControls: true,
          autoRotate: true,
          autoRotateDelay: 1200,
          backgroundColor: const Color(0xFFE8EAF6),
          scale: '1 1 1',
          debugLogging: false,
          onWebViewCreated: (_) => _registrarBitacora(),
          javascriptChannels: {},
        ),
        const Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: _Chip([
            'Visor 3D: arrastra para girar, pellizca para acercar o alejar.',
            'Este dispositivo no soporta ARCore, por eso se muestra el modelo '
                'en 3D.',
          ]),
        ),
        if (_modoAr != false)
          Positioned(
            right: 16,
            bottom: 24,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
              ),
              onPressed: () => setState(() => _modoAr = true),
              icon: const Icon(Icons.videocam),
              label: const Text('Intentar RA'),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _ar?.dispose();
    super.dispose();
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.textos);

  final List<String> textos;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final t in textos)
            Text(
              t,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
        ],
      ),
    );
  }
}

class _BotonRedondo extends StatelessWidget {
  const _BotonRedondo({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: FloatingActionButton.small(
        heroTag: tooltip,
        onPressed: onPressed,
        child: Icon(icon),
      ),
    );
  }
}