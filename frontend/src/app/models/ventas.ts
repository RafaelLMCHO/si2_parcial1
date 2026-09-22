export interface VentaItem {
  variante_id: number;
  cantidad: number;
}

export interface VentaDigitalCreate {
  items: VentaItem[];
  sucursal_id?: number;
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

