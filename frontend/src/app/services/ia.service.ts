import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../environments/environment';
import { Producto } from '../models/catalogo';

@Injectable({ providedIn: 'root' })
export class IaService {
  private http = inject(HttpClient);

  private api = `${environment.apiUrl}/ia`;

  recomendar(limit = 6): Observable<Producto[]> {
    const params = new HttpParams().set('limit', String(limit));
    return this.http.get<Producto[]>(`${this.api}/recomendaciones`, { params });
  }

  disponibles(sucursalId: number, limit = 6): Observable<Producto[]> {
    const params = new HttpParams()
      .set('sucursal_id', String(sucursalId))
      .set('limit', String(limit));
    return this.http.get<Producto[]>(`${this.api}/recomendaciones/disponibles`, {
      params,
    });
  }
}