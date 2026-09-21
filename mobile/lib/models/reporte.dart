class ProductoRank {
  final String producto;
  final String categoria;
  final int unidades;
  final double monto;

  ProductoRank({
    required this.producto,
    this.categoria = '',
    this.unidades = 0,
    this.monto = 0,
  });

  factory ProductoRank.fromJson(Map<String, dynamic> json) => ProductoRank(
        producto: json['producto'] as String? ?? '',
        categoria: json['categoria'] as String? ?? '',
        unidades: (json['unidades'] as num?)?.toInt() ?? 0,
        monto: (json['monto'] as num?)?.toDouble() ?? 0,
      );
}

class ResumenReporte {
  final double ventasTotal;
  final int totalPedidos;
  final int totalProductos;
  final int stockCritico;
  final int reservasActivas;
  final List<ProductoRank> topProductos;

  ResumenReporte({
    required this.ventasTotal,
    required this.totalPedidos,
    required this.totalProductos,
    required this.stockCritico,
    required this.reservasActivas,
    required this.topProductos,
  });

  factory ResumenReporte.fromJson(Map<String, dynamic> json) => ResumenReporte(
        ventasTotal: (json['ventas_total'] as num?)?.toDouble() ?? 0,
        totalPedidos: (json['total_pedidos'] as num?)?.toInt() ?? 0,
        totalProductos: (json['total_productos'] as num?)?.toInt() ?? 0,
        stockCritico: (json['stock_critico'] as num?)?.toInt() ?? 0,
        reservasActivas: (json['reservas_activas'] as num?)?.toInt() ?? 0,
        topProductos: (json['top_productos'] as List? ?? [])
            .map((e) => ProductoRank.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class VentaSucursalRow {
  final int sucursalId;
  final String sucursal;
  final double total;

  VentaSucursalRow({
    required this.sucursalId,
    required this.sucursal,
    required this.total,
  });

  factory VentaSucursalRow.fromJson(Map<String, dynamic> json) => VentaSucursalRow(
        sucursalId: (json['sucursal_id'] as num?)?.toInt() ?? 0,
        sucursal: json['sucursal'] as String? ?? '',
        total: (json['total'] as num?)?.toDouble() ?? 0,
      );
}

class MasVendidoRow {
  final String producto;
  final String categoria;
  final int unidades;
  final double monto;

  MasVendidoRow({
    required this.producto,
    required this.categoria,
    required this.unidades,
    required this.monto,
  });

  factory MasVendidoRow.fromJson(Map<String, dynamic> json) => MasVendidoRow(
        producto: json['producto'] as String? ?? '',
        categoria: json['categoria'] as String? ?? '',
        unidades: (json['unidades'] as num?)?.toInt() ?? 0,
        monto: (json['monto'] as num?)?.toDouble() ?? 0,
      );
}

class RotacionRow {
  final String producto;
  final int unidadesVendidas;
  final int stockActual;
  final double rotacion;

  RotacionRow({
    required this.producto,
    required this.unidadesVendidas,
    required this.stockActual,
    required this.rotacion,
  });

  factory RotacionRow.fromJson(Map<String, dynamic> json) => RotacionRow(
        producto: json['producto'] as String? ?? '',
        unidadesVendidas: (json['unidades_vendidas'] as num?)?.toInt() ?? 0,
        stockActual: (json['stock_actual'] as num?)?.toInt() ?? 0,
        rotacion: (json['rotacion'] as num?)?.toDouble() ?? 0,
      );
}

class StockCriticoRow {
  final String producto;
  final String talla;
  final String color;
  final String sku;
  final String sucursal;
  final int stockMinimo;
  final int disponible;
  final int faltante;

  StockCriticoRow({
    required this.producto,
    required this.talla,
    required this.color,
    required this.sku,
    required this.sucursal,
    required this.stockMinimo,
    required this.disponible,
    required this.faltante,
  });

  factory StockCriticoRow.fromJson(Map<String, dynamic> json) => StockCriticoRow(
        producto: json['producto'] as String? ?? '',
        talla: json['talla'] as String? ?? '',
        color: json['color'] as String? ?? '',
        sku: json['sku'] as String? ?? '',
        sucursal: json['sucursal'] as String? ?? '',
        stockMinimo: (json['stock_minimo'] as num?)?.toInt() ?? 0,
        disponible: (json['disponible'] as num?)?.toInt() ?? 0,
        faltante: (json['faltante'] as num?)?.toInt() ?? 0,
      );
}

class ReservaEstadoRow {
  final String estado;
  final int total;

  ReservaEstadoRow({required this.estado, required this.total});

  factory ReservaEstadoRow.fromJson(Map<String, dynamic> json) => ReservaEstadoRow(
        estado: json['estado'] as String? ?? '',
        total: (json['total'] as num?)?.toInt() ?? 0,
      );
}

class ReservaSucursalRow {
  final String sucursal;
  final int total;

  ReservaSucursalRow({required this.sucursal, required this.total});

  factory ReservaSucursalRow.fromJson(Map<String, dynamic> json) =>
      ReservaSucursalRow(
        sucursal: json['sucursal'] as String? ?? '',
        total: (json['total'] as num?)?.toInt() ?? 0,
      );
}

class ReservasReporte {
  final List<ReservaEstadoRow> porEstado;
  final List<ReservaSucursalRow> porSucursal;

  ReservasReporte({required this.porEstado, required this.porSucursal});

  factory ReservasReporte.fromJson(Map<String, dynamic> json) => ReservasReporte(
        porEstado: (json['por_estado'] as List? ?? [])
            .map((e) => ReservaEstadoRow.fromJson(e as Map<String, dynamic>))
            .toList(),
        porSucursal: (json['por_sucursal'] as List? ?? [])
            .map((e) => ReservaSucursalRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class TendenciaRow {
  final String temporada;
  final int unidades;
  final double monto;

  TendenciaRow({
    required this.temporada,
    required this.unidades,
    required this.monto,
  });

  factory TendenciaRow.fromJson(Map<String, dynamic> json) => TendenciaRow(
        temporada: json['temporada'] as String? ?? '',
        unidades: (json['unidades'] as num?)?.toInt() ?? 0,
        monto: (json['monto'] as num?)?.toDouble() ?? 0,
      );
}