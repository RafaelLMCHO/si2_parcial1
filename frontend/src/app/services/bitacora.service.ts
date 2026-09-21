import { HttpClient, HttpParams, HttpResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';

import { environment } from '../../environments/environment';
import { RegistroBitacora } from '../models/bitacora';

export interface BitacoraFiltros {
  usuario_id?: number | null;
  accion?: string | null;
  entidad?: string | null;
  fecha_desde?: string | null;
  fecha_hasta?: string | null;
}

/** CU-23 · Bitácora. Solo administradores puede consultarla (el backend lo valida). */
@Injectable({ providedIn: 'root' })
export class BitacoraService {
  private http = inject(HttpClient);
  private readonly api = `${environment.apiUrl}/bitacora`;

  /** Devuelve la respuesta completa para leer `X-Total-Count` (total de coincidencias). */
  listar(filtros: BitacoraFiltros, pagina = 1, limite = 200) {
    let p = new HttpParams();
    p = p.set('pagina', String(pagina)).set('limite', String(limite));
    if (filtros.usuario_id != null) p = p.set('usuario_id', String(filtros.usuario_id));
    if (filtros.accion) p = p.set('accion', filtros.accion);
    if (filtros.entidad) p = p.set('entidad', filtros.entidad);
    if (filtros.fecha_desde) p = p.set('fecha_desde', filtros.fecha_desde);
    if (filtros.fecha_hasta) p = p.set('fecha_hasta', filtros.fecha_hasta);
    return this.http.get<RegistroBitacora[]>(`${this.api}/`, {
      params: p,
      observe: 'response',
    });
  }

  tope(n: HttpResponse<RegistroBitacora[]>): number {
    return Number(n.headers.get('X-Total-Count') ?? 0);
  }
}