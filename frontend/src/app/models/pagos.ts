export interface PagoOut {
  id_pago: number;
  pedido_id: number;
  monto: number;
  proveedor_pago: string;
  transaccion_id?: string | null;
  estado: 'pendiente' | 'aprobado' | 'rechazado' | 'reembolsado' | string;
  fecha_pago?: string | null;
  cliente_nombre?: string;
  cliente_email?: string;
  sucursal_nombre?: string;
}

export interface ReembolsoResponse {
  id_pago: number;
  transaccion_id?: string | null;
  monto: number;
  estado: string;
  mensaje: string;
}

export interface WebhookPayload {
  transaccion_id: string;
  monto: number;
  estado?: string;
  proveedor?: string;
}
