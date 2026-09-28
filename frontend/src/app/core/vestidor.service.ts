import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { environment } from '../../environments/environment';
import { Producto } from '../models/catalogo';

/**
 * Probador de ropa por foto (CU-07).
 *
 * A diferencia del flujo realtime (WebRTC, que factura por segundo), el
 * cliente sube una foto —que toma con la cámara o elige de su galería— y el
 * backend la procesa en la Process API de Decart (`lucy-image-2`) junto con
 * la foto de la prenda del catálogo. Cada generación cuesta tarifa plana
 * ($0.01 en 480p), sin costo por tiempo, y el resultado es una imagen lista
 * para mostrar.
 */
@Injectable({ providedIn: 'root' })
export class VestidorService {
  private http = inject(HttpClient);

  /**
   * Manda la foto del cliente y devuelve la misma foto con la prenda puesta.
   */
  probar(producto: Producto, foto: Blob): Observable<Blob> {
    const form = new FormData();
    form.append('id_producto', String(producto.id_producto));
    form.append('persona', foto, 'foto.jpg');
    return this.http.post(`${environment.apiUrl}/virtual/prueba`, form, {
      responseType: 'blob',
    }).pipe(
      map((blob) => {
        // El backend puede devolver JSON en vez de imagen cuando la generación
        // falló pero con status 2xx (comportamiento raro); se traduce a un
        // error legible en vez de pintar un blob de texto como «resultado».
        if (blob.type.includes('json')) {
          throw new Error('El probador no devolvió una imagen.');
        }
        return blob;
      }),
    );
  }

  /**
   * Traduce un error HTTP del endpoint a texto para pantalla.
   *
   * Con `responseType: 'blob'` el cuerpo del error también llega como Blob,
   * así que el `detail` JSON hay que parsearlo a mano.
   */
  async mensajeDeError(error: unknown): Promise<string> {
    if (error instanceof HttpErrorResponse) {
      const status = error.status;
      let detalle = '';
      try {
        const texto = await (error.error as Blob).text();
        const json = texto ? JSON.parse(texto) : null;
        detalle = json?.detail ?? texto;
      } catch {
        detalle = error.message ?? '';
      }

      if (status === 501) {
        return (
          'El probador por foto está deshabilitado: falta configurar la clave '
          + 'de Decart (DECART_API_KEY) en el backend.'
        );
      }
      const m = String(detalle ?? '').toLowerCase();
      if (m.includes('insufficient credit') || m.includes('insufficient_credit')) {
        return 'La cuenta de Decart no tiene credito suficiente para generar imagen. Recargala en platform.decart.ai.';
      }
      if (m.includes('moderation')) {
        return 'Decart rechazó la imagen por su política de contenido. Probá con otra foto.';
      }
      if (detalle) return detalle;
      return `No se pudo generar la imagen (${status}).`;
    }
    if (error instanceof Error) return error.message;
    return 'No se pudo generar la imagen.';
  }
}