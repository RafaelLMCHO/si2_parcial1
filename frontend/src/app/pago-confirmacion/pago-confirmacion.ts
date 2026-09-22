import { Component, inject, OnInit, signal } from '@angular/core';
import { CommonModule, CurrencyPipe, DatePipe } from '@angular/common';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';

import { VentasService } from '../services/ventas.service';
import { CompraDigitalResponse } from '../models/ventas';
import { NavbarComponent } from '../shared/navbar';

@Component({
  selector: 'app-pago-confirmacion',
  templateUrl: './pago-confirmacion.html',
  styleUrl: './pago-confirmacion.scss',
  standalone: true,
  imports: [
    CommonModule,
    CurrencyPipe,
    DatePipe,
    RouterLink,
    MatCardModule,
    MatButtonModule,
    MatIconModule,
    MatProgressSpinnerModule,
    NavbarComponent,
  ],
})
export class PagoConfirmacionComponent implements OnInit {
  private route = inject(ActivatedRoute);
  private ventas = inject(VentasService);

  readonly cargando = signal(true);
  readonly confirmado = signal<CompraDigitalResponse | null>(null);
  readonly error = signal<string | null>(null);

  ngOnInit(): void {
    const sessionId = this.route.snapshot.queryParamMap.get('session_id');
    if (!sessionId) {
      this.cargando.set(false);
      this.error.set('No se recibió una sesión de pago válida.');
      return;
    }
    this.ventas.confirmarSesion(sessionId).subscribe({
      next: (res) => {
        this.cargando.set(false);
        this.confirmado.set(res);
      },
      error: (err) => {
        this.cargando.set(false);
        const detail = err?.error?.detail?.toString();
        this.error.set(detail ?? 'No se pudo confirmar el pago del pedido.');
      },
    });
  }
}
