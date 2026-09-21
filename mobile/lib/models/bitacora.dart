class RegistroBitacora {
  final int idBitacora;
  final int? usuarioId;
  final String accion;
  final String? entidad;
  final int? entidadId;
  final String? detalle;
  final String? ipOrigen;
  final DateTime fecha;
  final String? usuarioNombre;

  RegistroBitacora({
    required this.idBitacora,
    this.usuarioId,
    required this.accion,
    this.entidad,
    this.entidadId,
    this.detalle,
    this.ipOrigen,
    required this.fecha,
    this.usuarioNombre,
  });

  factory RegistroBitacora.fromJson(Map<String, dynamic> json) {
    return RegistroBitacora(
      idBitacora: json['id_bitacora'] as int,
      usuarioId: json['usuario_id'] as int?,
      accion: json['accion'] as String,
      entidad: json['entidad'] as String?,
      entidadId: json['entidad_id'] as int?,
      detalle: json['detalle'] as String?,
      ipOrigen: json['ip_origen'] as String?,
      fecha: DateTime.tryParse(json['fecha'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      usuarioNombre: json['usuario_nombre'] as String?,
    );
  }

  String get usuarioLabel =>
      usuarioNombre ?? (usuarioId != null ? '#$usuarioId' : 'Anónimo');
}