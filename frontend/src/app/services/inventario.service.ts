import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../environments/environment';
import { SucursalDisponibilidad } from '../models/catalogo';
import {
  InventarioGlobalOut,
  MovimientoCreate,
  MovimientoOut,
  TransferenciaCreate,
} from '../models/inventario';

export interface DisponibilidadFiltro {
  sucursal_id?: number | null;
  ciudad_id?: number | null;
}

export interface InventarioFiltro {
  sucursal_id?: number | null;
  categoria_id?: number | null;
  q?: string | null;
  stock_bajo_solo?: boolean;
}

@Injectable({ providedIn: 'root' })
export class InventarioService {
  private http = inject(HttpClient);
  private api = `${environment.apiUrl}/inventario`;

  obtenerInventarioGlobal(filtro: InventarioFiltro = {}): Observable<InventarioGlobalOut[]> {
    let params = new HttpParams();
    if (filtro.sucursal_id) params = params.set('sucursal_id', filtro.sucursal_id);
    if (filtro.categoria_id) params = params.set('categoria_id', filtro.categoria_id);
    if (filtro.q) params = params.set('q', filtro.q);
    if (filtro.stock_bajo_solo) params = params.set('stock_bajo_solo', 'true');

    return this.http.get<InventarioGlobalOut[]>(`${this.api}/global`, { params });
  }

  crearMovimiento(data: MovimientoCreate): Observable<unknown> {
    return this.http.post(`${this.api}/movimientos`, data);
  }

  transferirStock(data: TransferenciaCreate): Observable<{ status: string; mensaje: string }> {
    return this.http.post<{ status: string; mensaje: string }>(`${this.api}/transferir`, data);
  }

  actualizarStockMinimo(idInventario: number, stockMinimo: number): Observable<unknown> {
    return this.http.patch(`${this.api}/movimientos/${idInventario}`, { stock_minimo: stockMinimo });
  }

  obtenerMovimientos(sucursalId?: number, varianteId?: number): Observable<MovimientoOut[]> {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    if (varianteId) params = params.set('variante_id', varianteId);
    return this.http.get<MovimientoOut[]>(`${this.api}/movimientos`, { params });
  }

  disponibilidad(
    varianteId: number,
    filtro: DisponibilidadFiltro = {},
  ): Observable<SucursalDisponibilidad[]> {
    let params = new HttpParams();
    if (filtro.sucursal_id) params = params.set('sucursal_id', filtro.sucursal_id);
    if (filtro.ciudad_id) params = params.set('ciudad_id', filtro.ciudad_id);
    return this.http.get<SucursalDisponibilidad[]>(
      `${this.api}/disponibilidad`,
      { params: params.set('variante_id', varianteId) },
    );
  }
}