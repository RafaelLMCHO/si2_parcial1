import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../environments/environment';
import {
  Categoria,
  Coleccion,
  Color,
  Producto,
  ProductoForm,
  ProductoVariante,
  Proveedor,
  Talla,
  Temporada,
} from '../models/catalogo';

export interface ProductoFiltro {
  categoria_id?: number | null;
  q?: string | null;
  precio_min?: number | null;
  precio_max?: number | null;
}

export interface VarianteForm {
  producto_id: number;
  color_id: number;
  talla_id: number;
  sku?: string | null;
  precio_extra?: number;
}

@Injectable({ providedIn: 'root' })
export class CatalogoService {
  private http = inject(HttpClient);

  private api = `${environment.apiUrl}/catalogo`;

  listarCategorias(): Observable<Categoria[]> {
    return this.http.get<Categoria[]>(`${this.api}/categorias`);
  }

  listarTallas(): Observable<Talla[]> {
    return this.http.get<Talla[]>(`${this.api}/tallas`);
  }

  listarColores(): Observable<Color[]> {
    return this.http.get<Color[]>(`${this.api}/colores`);
  }

  listarProveedores(): Observable<Proveedor[]> {
    return this.http.get<Proveedor[]>(`${this.api}/proveedores`);
  }

  listarTemporadas(): Observable<Temporada[]> {
    return this.http.get<Temporada[]>(`${this.api}/temporadas`);
  }

  listarColecciones(): Observable<Coleccion[]> {
    return this.http.get<Coleccion[]>(`${this.api}/colecciones`);
  }

  listarProductos(filtro: ProductoFiltro = {}): Observable<Producto[]> {
    let params = new HttpParams();
    if (filtro.categoria_id) params = params.set('categoria_id', filtro.categoria_id);
    if (filtro.q) params = params.set('q', filtro.q);
    if (filtro.precio_min != null) params = params.set('precio_min', filtro.precio_min);
    if (filtro.precio_max != null) params = params.set('precio_max', filtro.precio_max);

    return this.http.get<Producto[]>(`${this.api}/productos`, { params });
  }

  listarTodos(): Observable<Producto[]> {
    return this.http.get<Producto[]>(`${this.api}/productos`, {
      params: { todas: 'true' },
    });
  }

  verProducto(id: number): Observable<Producto> {
    return this.http.get<Producto>(`${this.api}/productos/${id}`);
  }

  crearProducto(data: ProductoForm): Observable<Producto> {
    return this.http.post<Producto>(`${this.api}/productos`, data);
  }

  actualizarProducto(
    id: number,
    data: Partial<ProductoForm> & { activo?: boolean },
  ): Observable<Producto> {
    return this.http.patch<Producto>(`${this.api}/productos/${id}`, data);
  }

  desactivarProducto(id: number, forzar: boolean): Observable<Producto> {
    return this.http.patch<Producto>(`${this.api}/productos/${id}`, { activo: false }, {
      params: { forzar: String(forzar) },
    });
  }

  subirImagen(id: number, archivo: File): Observable<Producto> {
    const form = new FormData();
    form.append('archivo', archivo, archivo.name);
    return this.http.post<Producto>(`${this.api}/productos/${id}/imagen`, form);
  }

  crearVariante(data: VarianteForm): Observable<ProductoVariante> {
    return this.http.post<ProductoVariante>(`${this.api}/productos/variantes`, data);
  }

  eliminarVariante(id: number): Observable<unknown> {
    return this.http.delete(`${this.api}/productos/variantes/${id}`);
  }
}