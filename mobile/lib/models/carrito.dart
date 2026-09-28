class CarritoItem {
  final int varianteId;
  int cantidad;
  final String nombre;
  final String sku;
  final String? color;
  final String? talla;
  final double precio;
  final String? imagenUrl;
  DateTime? reservadoHasta;
  int? idReserva;

  CarritoItem({
    required this.varianteId,
    required this.cantidad,
    required this.nombre,
    required this.sku,
    this.color,
    this.talla,
    required this.precio,
    this.imagenUrl,
    this.reservadoHasta,
    this.idReserva,
  });

  bool get reservado => reservadoHasta != null;

  Map<String, dynamic> toJson() => {
        'variante_id': varianteId,
        'cantidad': cantidad,
        'nombre': nombre,
        'sku': sku,
        'color': color,
        'talla': talla,
        'precio': precio,
        'imagen_url': imagenUrl,
        'reservado_hasta': reservadoHasta?.toIso8601String(),
        'id_reserva': idReserva,
      };

  factory CarritoItem.fromJson(Map<String, dynamic> json) => CarritoItem(
        varianteId: json['variante_id'] as int,
        cantidad: json['cantidad'] as int,
        nombre: json['nombre'] as String,
        sku: json['sku'] as String? ?? '',
        color: json['color'] as String?,
        talla: json['talla'] as String?,
        precio: (json['precio'] as num).toDouble(),
        imagenUrl: json['imagen_url'] as String?,
        reservadoHasta: _parseFecha(json['reservado_hasta']),
        idReserva: json['id_reserva'] as int?,
      );

  static DateTime? _parseFecha(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v);
  }
}