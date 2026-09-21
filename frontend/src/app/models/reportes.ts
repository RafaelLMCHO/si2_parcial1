export interface ProductoRank {
  producto: string;
  categoria?: string;
  unidades: number;
  monto: number;
}

export interface ResumenReporte {
  ventas_total: number;
  total_pedidos: number;
  total_productos: number;
  stock_critico: number;
  reservas_activas: number;
  top_productos: ProductoRank[];
}

export interface VentaSucursalRow {
  sucursal_id: number | null;
  sucursal: string;
  total: number;
}

export interface MasVendidoRow extends ProductoRank {
  producto: string;
  unidades: number;
  monto: number;
}

export interface RotacionRow {
  producto: string;
  unidades_vendidas: number;
  stock_actual: number;
  rotacion: number;
}

export interface StockCriticoRow {
  producto: string;
  talla: string;
  color: string;
  sku: string;
  sucursal: string;
  stock_minimo: number;
  disponible: number;
  faltante: number;
}

export interface ReservaEstadoRow {
  estado: string;
  total: number;
}

export interface ReservaSucursalRow {
  sucursal: string;
  total: number;
}

export interface ReservasReporte {
  por_estado: ReservaEstadoRow[];
  por_sucursal: ReservaSucursalRow[];
}

export interface TendenciaRow {
  temporada: string;
  unidades: number;
  monto: number;
}
