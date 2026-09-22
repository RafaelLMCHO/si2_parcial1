export interface ReservaItemCreate {
  variante_id: number;
  cantidad: number;
}

export interface ReservaCreate {
  sucursal_id: number;
  fecha_reserva: string;
  hora_atencion: string;
  items: ReservaItemCreate[];
}

export interface ReservaItem {
  id_reserva_item: number;
  variante_id: number;
  cantidad: number;
  variante?: {
    id_variante: number;
    sku?: string | null;
    talla?: { id_talla: number; nombre: string } | null;
    color?: { id_color: number; nombre: string } | null;
  } | null;
  producto?: { id_producto: number; nombre: string } | null;
}

export interface Reserva {
  id_reserva: number;
  usuario_id: number;
  sucursal_id: number;
  fecha_reserva: string;
  hora_atencion: string;
  estado: string;
  usuario?: { id_usuario: number; nombre: string; email?: string | null; telefono?: string | null } | null;
  sucursal?: {
    id_sucursal: number;
    nombre: string;
    ciudad?: { id_ciudad: number; nombre: string } | null;
  } | null;
  items: ReservaItem[];
}