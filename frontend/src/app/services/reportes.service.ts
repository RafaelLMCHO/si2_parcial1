import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';

import { environment } from '../../environments/environment';
import {
  MasVendidoRow,
  ReservasReporte,
  ResumenReporte,
  RotacionRow,
  StockCriticoRow,
  TendenciaRow,
  VentaSucursalRow,
} from '../models/reportes';

export interface ReporteFiltros {
  fecha_desde?: string | null;
  fecha_hasta?: string | null;
  sucursal_id?: number | null;
  categoria_id?: number | null;
  temporada_id?: number | null;
}

@Injectable({ providedIn: 'root' })
export class ReportesService {
  private http = inject(HttpClient);
  private api = `${environment.apiUrl}/reportes`;

  private params(filtros: ReporteFiltros, extra?: Record<string, string | number | boolean>) {
    let p = new HttpParams();
    if (filtros.fecha_desde) p = p.set('fecha_desde', filtros.fecha_desde);
    if (filtros.fecha_hasta) p = p.set('fecha_hasta', filtros.fecha_hasta);
    if (filtros.sucursal_id != null) p = p.set('sucursal_id', filtros.sucursal_id);
    if (filtros.categoria_id != null) p = p.set('categoria_id', filtros.categoria_id);
    if (filtros.temporada_id != null) p = p.set('temporada_id', filtros.temporada_id);
    if (extra) {
      for (const k of Object.keys(extra)) p = p.set(k, String(extra[k]));
    }
    return p;
  }

  resumen(filtros: ReporteFiltros) {
    return this.http.get<ResumenReporte>(`${this.api}/resumen`, { params: this.params(filtros) });
  }

  ventasPorSucursal(filtros: ReporteFiltros) {
    return this.http.get<VentaSucursalRow[]>(`${this.api}/ventas-por-sucursal`, {
      params: this.params(filtros),
    });
  }

  masVendidos(filtros: ReporteFiltros, limit = 10) {
    return this.http.get<MasVendidoRow[]>(`${this.api}/mas-vendidos`, {
      params: this.params(filtros, { limit }),
    });
  }

  rotacionInvetario(filtros: ReporteFiltros, limit = 10) {
    return this.http.get<RotacionRow[]>(`${this.api}/rotacion-inventario`, {
      params: this.params(filtros, { limit }),
    });
  }

  stockCritico(filtros: ReporteFiltros) {
    return this.http.get<StockCriticoRow[]>(`${this.api}/stock-critico`, {
      params: this.params(filtros),
    });
  }

  reservas(filtros: ReporteFiltros) {
    return this.http.get<ReservasReporte>(`${this.api}/reservas`, { params: this.params(filtros) });
  }

  tendencias(filtros: ReporteFiltros) {
    return this.http.get<TendenciaRow[]>(`${this.api}/tendencias-temporada`, {
      params: this.params(filtros),
    });
  }
}