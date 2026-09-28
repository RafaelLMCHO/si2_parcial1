export interface Categoria {
  id_categoria: number;
  nombre: string;
  descripcion?: string | null;
}

export interface Color {
  id_color: number;
  nombre: string;
  codigo_hex: string;
}

export interface Talla {
  id_talla: number;
  nombre: string;
}

export interface Proveedor {
  id_proveedor: number;
  nombre: string;
  contacto?: string | null;
  telefono?: string | null;
  email?: string | null;
  direccion?: string | null;
}

export interface ProveedorForm {
  nombre: string;
  contacto?: string | null;
  telefono?: string | null;
  email?: string | null;
  direccion?: string | null;
}

export interface Temporada {
  id_temporada: number;
  nombre: string;
  fecha_inicio: string;
  fecha_fin: string;
}

export interface TemporadaForm {
  nombre: string;
  fecha_inicio: string;
  fecha_fin: string;
}

export interface Coleccion {
  id_coleccion: number;
  temporada_id: number;
  nombre: string;
  descripcion?: string | null;
  es_promocional: boolean;
}

export interface ColeccionForm {
  temporada_id: number;
  nombre: string;
  descripcion?: string | null;
  es_promocional?: boolean;
}

export interface ProductoVariante {
  id_variante: number;
  producto_id: number;
  color_id: number;
  talla_id: number;
  sku: string;
  precio_extra: number;
  color?: Color | null;
  talla?: Talla | null;
}

export interface Producto {
  id_producto: number;
  nombre: string;
  descripcion?: string | null;
  precio: number;
  categoria_id: number;
  temporada_id: number;
  coleccion_id?: number | null;
  proveedor_id: number;
  imagen_url?: string | null;
  modelo_3d_url?: string | null;
  prompt_vestidor?: string | null;
  activo: boolean;
  categoria?: Categoria | null;
  temporada?: Temporada | null;
  proveedor?: Proveedor | null;
  coleccion?: Coleccion | null;
  variantes?: ProductoVariante[];
}

export interface SucursalDisponibilidad {
  variante_id: number;
  sucursal_id: number;
  nombre_sucursal: string;
  ciudad: string;
  cantidad_disponible: number;
  cantidad_reservada: number;
  cantidad_recibida: number;
  stock_minimo: number;
  estado: string;
}

export interface ProductoForm {
  nombre: string;
  descripcion?: string | null;
  precio: number;
  categoria_id: number;
  temporada_id: number;
  coleccion_id?: number | null;
  proveedor_id: number;
  imagen_url?: string | null;
  modelo_3d_url?: string | null;
  prompt_vestidor?: string | null;
}