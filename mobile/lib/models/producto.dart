class Color {
  final int idColor;
  final String nombre;
  final String codigoHex;

  Color({required this.idColor, required this.nombre, required this.codigoHex});

  factory Color.fromJson(Map<String, dynamic> json) => Color(
        idColor: json['id_color'] as int,
        nombre: json['nombre'] as String,
        codigoHex: json['codigo_hex'] as String? ?? '',
      );
}

class Talla {
  final int idTalla;
  final String nombre;

  Talla({required this.idTalla, required this.nombre});

  factory Talla.fromJson(Map<String, dynamic> json) => Talla(
        idTalla: json['id_talla'] as int,
        nombre: json['nombre'] as String,
      );
}

class ProductoVariante {
  final int idVariante;
  final int productoId;
  final int colorId;
  final int tallaId;
  final String sku;
  final double precioExtra;
  final Color? color;
  final Talla? talla;

  ProductoVariante({
    required this.idVariante,
    required this.productoId,
    required this.colorId,
    required this.tallaId,
    required this.sku,
    required this.precioExtra,
    this.color,
    this.talla,
  });

  factory ProductoVariante.fromJson(Map<String, dynamic> json) =>
      ProductoVariante(
        idVariante: json['id_variante'] as int,
        productoId: json['producto_id'] as int,
        colorId: json['color_id'] as int,
        tallaId: json['talla_id'] as int,
        sku: json['sku'] as String? ?? '',
        precioExtra: (json['precio_extra'] as num?)?.toDouble() ?? 0,
        color: json['color'] == null
            ? null
            : Color.fromJson(json['color'] as Map<String, dynamic>),
        talla: json['talla'] == null
            ? null
            : Talla.fromJson(json['talla'] as Map<String, dynamic>),
      );
}

class Producto {
  final int idProducto;
  final String nombre;
  final String? descripcion;
  final double precio;
  final String? imagenUrl;
  final String? modelo3dUrl;
  final String? promptVestidor;
  final List<ProductoVariante> variantes;

  Producto({
    required this.idProducto,
    required this.nombre,
    this.descripcion,
    required this.precio,
    this.imagenUrl,
    this.modelo3dUrl,
    this.promptVestidor,
    this.variantes = const [],
  });

  factory Producto.fromJson(Map<String, dynamic> json) => Producto(
        idProducto: json['id_producto'] as int,
        nombre: json['nombre'] as String,
        descripcion: json['descripcion'] as String?,
        precio: (json['precio'] as num).toDouble(),
        imagenUrl: json['imagen_url'] as String?,
        modelo3dUrl: json['modelo_3d_url'] as String?,
        promptVestidor: json['prompt_vestidor'] as String?,
        variantes: (json['variantes'] as List? ?? [])
            .map((e) => ProductoVariante.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}