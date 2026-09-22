import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../environments/environment';
import { PagoOut, ReembolsoResponse, WebhookPayload } from '../models/pagos';

@Injectable({
  providedIn: 'root',
})
export class PagosService {
  private http = inject(HttpClient);
  private apiUrl = `${environment.apiUrl}/pagos`;

  listarPagos(estado?: string, proveedor?: string): Observable<PagoOut[]> {
    let params = new HttpParams();
    if (estado) params = params.set('estado', estado);
    if (proveedor) params = params.set('proveedor', proveedor);
    return this.http.get<PagoOut[]>(this.apiUrl, { params });
  }

  obtenerPago(idPago: number): Observable<PagoOut> {
    return this.http.get<PagoOut>(`${this.apiUrl}/${idPago}`);
  }

  reembolsarPago(idPago: number): Observable<ReembolsoResponse> {
    return this.http.post<ReembolsoResponse>(`${this.apiUrl}/${idPago}/reembolsar`, {});
  }

  simularWebhook(payload: WebhookPayload): Observable<{ status: string; mensaje: string; id_pago?: number }> {
    return this.http.post<{ status: string; mensaje: string; id_pago?: number }>(`${this.apiUrl}/webhook`, payload);
  }
}
