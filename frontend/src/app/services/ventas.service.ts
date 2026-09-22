import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../environments/environment';
import {
  VentaDigitalCreate,
  PaymentIntent,
  CheckoutSession,
  CompraDigitalResponse,
  PedidoHistorial,
  VentaPresencialCreate,
  ComprobantePresencialResponse,
} from '../models/ventas';

@Injectable({
  providedIn: 'root',
})
export class VentasService {
  private http = inject(HttpClient);
  private apiUrl = `${environment.apiUrl}/ventas`;

  crearIntencionPago(data: VentaDigitalCreate): Observable<PaymentIntent> {
    return this.http.post<PaymentIntent>(`${this.apiUrl}/digital/payment-intent`, data);
  }

  crearCheckout(data: VentaDigitalCreate & { return_url?: string }): Observable<CheckoutSession> {
    return this.http.post<CheckoutSession>(`${this.apiUrl}/digital/checkout`, data);
  }

  confirmarSesion(sessionId: string): Observable<CompraDigitalResponse> {
    return this.http.post<CompraDigitalResponse>(`${this.apiUrl}/digital/confirmar`, { session_id: sessionId });
  }

  confirmarCompra(data: VentaDigitalCreate): Observable<CompraDigitalResponse> {
    return this.http.post<CompraDigitalResponse>(`${this.apiUrl}/digital/confirmar`, data);
  }

  pagarReservaDigital(reservaId: number): Observable<CompraDigitalResponse> {
    return this.http.post<CompraDigitalResponse>(`${this.apiUrl}/digital/pagar-reserva/${reservaId}`, {});
  }

  obtenerHistorial(): Observable<PedidoHistorial[]> {
    return this.http.get<PedidoHistorial[]>(`${this.apiUrl}/historial`);
  }

  registrarVentaPresencial(data: VentaPresencialCreate): Observable<ComprobantePresencialResponse> {
    return this.http.post<ComprobantePresencialResponse>(`${this.apiUrl}/presencial`, data);
  }
}
