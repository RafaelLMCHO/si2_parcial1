import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../environments/environment';
import {
  Categoria,
  Coleccion,
  ColeccionForm,
  Color,
  Producto,
  ProductoForm,
  ProductoVariante,
  Proveedor,
  ProveedorForm,
  Talla,
  Temporada,
  TemporadaForm,
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

  crearProveedor(data: ProveedorForm): Observable<Proveedor> {
    return this.http.post<Proveedor>(`${this.api}/proveedores`, data);
  }

  actualizarProveedor(id: number, data: Partial<ProveedorForm>): Observable<Proveedor> {
    return this.http.patch<Proveedor>(`${this.api}/proveedores/${id}`, data);
  }

  eliminarProveedor(id: number): Observable<{ ok: boolean; eliminado: number }> {
    return this.http.delete<{ ok: boolean; eliminado: number }>(`${this.api}/proveedores/${id}`);
  }

  listarTemporadas(): Observable<Temporada[]> {
    return this.http.get<Temporada[]>(`${this.api}/temporadas`);
  }

  crearTemporada(data: TemporadaForm): Observable<Temporada> {
    return this.http.post<Temporada>(`${this.api}/temporadas`, data);
  }

  actualizarTemporada(id: number, data: Partial<TemporadaForm>): Observable<Temporada> {
    return this.http.patch<Temporada>(`${this.api}/temporadas/${id}`, data);
  }

  eliminarTemporada(id: number): Observable<{ ok: boolean; eliminado: number }> {
    return this.http.delete<{ ok: boolean; eliminado: number }>(`${this.api}/temporadas/${id}`);
  }

  listarColecciones(): Observable<Coleccion[]> {
    return this.http.get<Coleccion[]>(`${this.api}/colecciones`);
  }

  crearColeccion(data: ColeccionForm): Observable<Coleccion> {
    return this.http.post<Coleccion>(`${this.api}/colecciones`, data);
  }

  actualizarColeccion(id: number, data: Partial<ColeccionForm>): Observable<Coleccion> {
    return this.http.patch<Coleccion>(`${this.api}/colecciones/${id}`, data);
  }

  eliminarColeccion(id: number): Observable<{ ok: boolean; eliminado: number }> {
    return this.http.delete<{ ok: boolean; eliminado: number }>(`${this.api}/colecciones/${id}`);
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