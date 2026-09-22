export interface InventarioGlobalOut {
  id_inventario: number;
  variante_id: number;
  sucursal_id: number;
  sucursal_nombre: string;
  producto_nombre: string;
  sku?: string | null;
  talla?: string | null;
  color?: string | null;
  precio: number;
  cantidad_disponible: number;
  cantidad_reservada: number;
  cantidad_recibida: number;
  stock_minimo: number;
  stock_bajo: boolean;
  imagen_url?: string | null;
}

export interface MovimientoCreate {
  variante_id: number;
  sucursal_id: number;
  tipo_movimiento: 'entrada' | 'salida' | 'ajuste';
  cantidad: number;
  observacion?: string;
}

export interface TransferenciaCreate {
  variante_id: number;
  sucursal_origen_id: number;
  sucursal_destino_id: number;
  cantidad: number;
  observacion?: string;
}

export interface MovimientoOut {
  id_movimiento: number;
  variante_id: number;
  sucursal_id: number;
  tipo_movimiento: string;
  cantidad: number;
  observacion?: string | null;
  fecha_movimiento: string;
}
