export interface VentaItem {
  variante_id: number;
  cantidad: number;
}

export interface VentaDigitalCreate {
  items: VentaItem[];
  sucursal_id?: number;
  tipo_pago?: string;
  pasarela?: string;
  payment_intent_id?: string;
  session_id?: string;
  return_url?: string;
}

export interface QrDigitalResponse {
  monto: number;
  qr_url: string;
  referencia: string;
  moneda: string;
}

export interface PaymentIntent {
  id: string;
  client_secret: string;
  simulado: boolean;
  monto: number;
}

export interface CheckoutSession {
  monto: number;
  session_id: string | null;
  checkout_url: string | null;
  simulado: boolean;
}

export interface CompraDigitalResponse {
  id_pedido: number;
  total: number;
  estado: string;
  fecha_pedido?: string | null;
}

export interface PedidoItemHistorial {
  id_pedido_item: number;
  cantidad: number;
  precio_unitario: number;
  subtotal: number;
  producto_nombre: string;
  imagen_url?: string | null;
  sku?: string | null;
  talla?: string | null;
  color?: string | null;
}

export interface PedidoHistorial {
  id_pedido: number;
  fecha_pedido: string;
  total: number;
  metodo_compra: string;
  estado: string;
  tipo_pago?: string | null;
  sucursal_nombre: string;
  items: PedidoItemHistorial[];
}

export interface VentaPresencialCreate {
  sucursal_id: number;
  tipo_pago: 'efectivo' | 'tarjeta_debito' | 'tarjeta_credito' | 'qr';
  items: VentaItem[];
}

export interface ComprobanteItem {
  variante_id: number;
  cantidad: number;
  precio_unitario: number;
  subtotal: number;
  producto_nombre: string;
  sku?: string | null;
  talla?: string | null;
  color?: string | null;
}

export interface ComprobantePresencialResponse {
  id_pedido: number;
  total: number;
  estado: string;
  tipo_pago: string;
  fecha_pedido?: string;
  sucursal_nombre?: string;
  cajero_nombre?: string;
  items: ComprobanteItem[];
}

export interface QrCobroResponse {
  id_pago: number;
  id_pedido: number;
  transaccion_id: string;
  proveedor_pago: string;
  qr_url: string;
  url_pago: string | null;
  estado: string;
  simulado: boolean;
  expires_at: string;
  total: number;
  stock_reservado: boolean;
}

export interface QrCobroEstado {
  id_pago: number;
  id_pedido: number;
  estado: 'pendiente' | 'aprobado' | 'rechazado' | string;
  motivo: 'vencido' | null;
  transaccion_id: string | null;
  estado_pedido: string | null;
  total: number;
  simulado: boolean;
}

export interface CobroTarjetaResponse {
  id_pago: number;
  id_pedido: number;
  transaccion_id: string;
  estado: string;
  total: number;
  simulado: boolean;
  checkout_url: string | null;
}

/** Lo que el punto de venta manda al preguntar si entro el pago.
 *
 *  `numero_tarjeta` no declara el resultado: es la tarjeta que el cajero dice
 *  que uso el cliente, y la decision la toma el servidor. */
export interface VerificarCobroTarjeta {
  numero_tarjeta?: string;
}

export interface CobroTarjetaVerificacion {
  estado: string;
  aplicado: boolean;
  motivo?: string | null;
  id_pago?: number;
  id_pedido?: number;
}

