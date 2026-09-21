export interface RegistroBitacora {
  id_bitacora: number;
  usuario_id: number | null;
  accion: string;
  entidad: string | null;
  entidad_id: number | null;
  detalle: string | null;
  ip_origen: string | null;
  fecha: string;
  usuario_nombre: string | null;
}