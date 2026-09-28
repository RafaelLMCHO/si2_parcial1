import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../services/bitacora_service.dart';

/// CU-07 · Probador de ropa por foto (Decart, foto→foto).
///
/// El cliente toma una foto con la cámara (o la sube de su galería) y el
/// backend la procesa con la Process API de Decart (`lucy-image-2`) junto con
/// la foto de la prenda del catálogo como referencia. Cada generación cuesta
/// tarifa plana (480p ≈ $0.01), sin facturar por tiempo.
class VestidorFotoScreen extends StatefulWidget {
  const VestidorFotoScreen({
    super.key,
    required this.productoId,
    required this.productoNombre,
  });

  final int productoId;
  final String productoNombre;

  @override
  State<VestidorFotoScreen> createState() => _VestidorFotoScreenState();
}

class _VestidorFotoScreenState extends State<VestidorFotoScreen> {
  final _picker = ImagePicker();

  String? _mime;
  Uint8List? _foto;
  Uint8List? _resultado;
  bool _cargando = false;
  bool _bitacoraRegistrada = false;

  Future<void> _tomarFoto() async {
    final archivo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      preferredCameraDevice: CameraDevice.front,
    );
    await _usarArchivo(archivo);
  }

  Future<void> _subirFoto() async {
    final archivo = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    await _usarArchivo(archivo);
  }

  Future<void> _usarArchivo(XFile? archivo) async {
    if (archivo == null || !mounted) return;
    final bytes = await archivo.readAsBytes();
    if (!mounted) return;
    setState(() {
      _foto = bytes;
      _resultado = null;
      _bitacoraRegistrada = false;
      _mime = archivo.mimeType ?? _mimePorNombre(archivo.name);
    });
  }

  String _mimePorNombre(String nombre) {
    final lower = nombre.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _probar() async {
    final foto = _foto;
    if (foto == null) return;
    setState(() => _cargando = true);
    try {
      final bytes = await ApiClient.postImage(
        '/virtual/prueba',
        fileBytes: foto,
        filename: 'foto.jpg',
        mimeType: _mime ?? 'image/jpeg',
        fields: {'id_producto': '${widget.productoId}'},
      );
      if (!mounted) return;
      setState(() {
        _resultado = bytes;
        _cargando = false;
      });
      _registrarBitacora();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _mostrar(_mensajeLegible(e.message));
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _mostrar('No se pudo generar la imagen. Intente de nuevo.');
    }
  }

  /// Traduce los motivos que importan; el resto (p. ej. el 501 de clave
  /// faltante) ya llega como texto para pantalla desde el backend.
  String _mensajeLegible(String detalle) {
    final m = detalle.toLowerCase();
    if (m.contains('insufficient credit') || m.contains('insufficient_credit')) {
      return 'La cuenta de Decart no tiene credito suficiente para generar imagen. Recargala en platform.decart.ai.';
    }
    if (m.contains('moderation')) {
      return 'Decart rechazó la imagen por su política de contenido. Probá con otra foto.';
    }
    return detalle;
  }

  void _registrarBitacora() {
    if (_bitacoraRegistrada) return;
    _bitacoraRegistrada = true;
    BitacoraService.registrarConsultaVestidor(
      productoId: widget.productoId,
      nombre: widget.productoNombre,
      modo: 'Foto',
    );
  }

  void _repetir() {
    setState(() {
      _resultado = null;
      _foto = null;
      _bitacoraRegistrada = false;
    });
  }

  void _mostrar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Probador virtual — ${widget.productoNombre}')),
      body: _lienzo(),
      bottomNavigationBar: SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: _acciones(),
      )),
    );
  }

  Widget _lienzo() {
    final resultado = _resultado;
    final foto = _foto;
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (resultado != null)
            Image.memory(resultado, fit: BoxFit.contain)
          else if (foto != null)
            Image.memory(foto, fit: BoxFit.contain)
          else
            const _GuiaEncuadre(),
          if (_cargando)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Poniendo la prenda sobre tu foto…',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Puede tardar unos segundos.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _acciones() {
    if (_resultado != null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _repetir,
              icon: const Icon(Icons.replay),
              label: const Text('Repetir'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check),
              label: const Text('Cerrar'),
            ),
          ),
        ],
      );
    }
    if (_cargando) {
      return const SizedBox(
        width: double.infinity,
        child: ElevatedButton(onPressed: null, child: Text('Generando…')),
      );
    }
    if (_foto != null) {
      return Row(
        children: [
          OutlinedButton.icon(
            onPressed: _tomarFoto,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Otra foto'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _subirFoto,
            icon: const Icon(Icons.photo_library),
            label: const Text('Subir'),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _probar,
            icon: const Icon(Icons.checkroom),
            label: const Text('Probar esta prenda'),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _subirFoto,
            icon: const Icon(Icons.photo_library),
            label: const Text('Subir foto'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: _tomarFoto,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Tomar foto'),
          ),
        ),
      ],
    );
  }
}

class _GuiaEncuadre extends StatelessWidget {
  const _GuiaEncuadre();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checkroom, color: Colors.white70, size: 48),
            SizedBox(height: 12),
            Text(
              'Tomá una foto o subí una desde tu galería y '
              'el probador pondrá la prenda sobre vos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
            SizedBox(height: 8),
            Text(
              'Encuadrá el torso (o piernas completas si es pantalón/falda) '
              'con buena luz.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}