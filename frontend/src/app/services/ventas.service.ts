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
  QrCobroResponse,
  QrCobroEstado,
  QrDigitalResponse,
  CobroTarjetaResponse,
  CobroTarjetaVerificacion,
  VerificarCobroTarjeta,
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

  generarQrDigital(data: VentaDigitalCreate): Observable<QrDigitalResponse> {
    return this.http.post<QrDigitalResponse>(`${this.apiUrl}/digital/qr-generar`, data);
  }

  pagarReservaDigital(reservaId: number, tipoPago: string = 'tarjeta_credito'): Observable<CompraDigitalResponse> {
    return this.http.post<CompraDigitalResponse>(`${this.apiUrl}/digital/pagar-reserva/${reservaId}`, {
      tipo_pago: tipoPago,
    });
  }

  obtenerHistorial(): Observable<PedidoHistorial[]> {
    return this.http.get<PedidoHistorial[]>(`${this.apiUrl}/historial`);
  }

  registrarVentaPresencial(data: VentaPresencialCreate): Observable<ComprobantePresencialResponse> {
    return this.http.post<ComprobantePresencialResponse>(`${this.apiUrl}/presencial`, data);
  }

  crearCobroQr(data: VentaPresencialCreate): Observable<QrCobroResponse> {
    return this.http.post<QrCobroResponse>(`${this.apiUrl}/qr/cobrar`, data);
  }

  estadoCobroQr(idPago: number): Observable<QrCobroEstado> {
    return this.http.get<QrCobroEstado>(`${this.apiUrl}/qr/${idPago}/estado`);
  }

  simularPagoQr(idPago: number): Observable<{ estado: string; aplicado: boolean }> {
    return this.http.post<{ estado: string; aplicado: boolean }>(
      `${this.apiUrl}/qr/${idPago}/simular-pago`,
      {},
    );
  }

  crearCobroTarjeta(data: VentaPresencialCreate): Observable<CobroTarjetaResponse> {
    return this.http.post<CobroTarjetaResponse>(`${this.apiUrl}/presencial/tarjeta`, data);
  }

  /** Pregunta a la pasarela si el pago entro. A diferencia del sondeo del QR,
   *  este POST no es solo lectura: cierra el cobro si la pasarela confirma.
   *  Es idempotente, asi que el intervalo puede llamarlo sin riesgo. */
  verificarCobroTarjeta(
    idPago: number,
    data: VerificarCobroTarjeta = {},
  ): Observable<CobroTarjetaVerificacion> {
    return this.http.post<CobroTarjetaVerificacion>(
      `${this.apiUrl}/presencial/tarjeta/${idPago}/verificar`,
      data,
    );
  }
}
