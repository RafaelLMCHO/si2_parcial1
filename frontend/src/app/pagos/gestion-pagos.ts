import { Component, inject, OnInit, signal } from '@angular/core';
import { CommonModule, CurrencyPipe, DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatSelectModule } from '@angular/material/select';
import { MatSnackBar, MatSnackBarModule } from '@angular/material/snack-bar';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatDividerModule } from '@angular/material/divider';
import { MatTabsModule } from '@angular/material/tabs';
import { MatInputModule } from '@angular/material/input';

import { PagoOut } from '../models/pagos';
import { PagosService } from '../services/pagos.service';
import { NavbarComponent } from '../shared/navbar';

@Component({
  selector: 'app-gestion-pagos',
  templateUrl: './gestion-pagos.html',
  styleUrl: './gestion-pagos.scss',
  standalone: true,
  imports: [
    CommonModule,
    FormsModule,
    CurrencyPipe,
    DatePipe,
    MatCardModule,
    MatButtonModule,
    MatIconModule,
    MatFormFieldModule,
    MatSelectModule,
    MatSnackBarModule,
    MatProgressSpinnerModule,
    MatDividerModule,
    MatTabsModule,
    MatInputModule,
    NavbarComponent,
  ],
})
export class GestionPagosComponent implements OnInit {
  private pagosServ = inject(PagosService);
  private snackbar = inject(MatSnackBar);

  readonly pagos = signal<PagoOut[]>([]);
  readonly cargando = signal(true);
  readonly error = signal<string | null>(null);

  readonly estadoFiltro = signal<string>('todos');
  readonly proveedorFiltro = signal<string>('todos');
  readonly reembolsandoId = signal<number | null>(null);

  // Módulo Simulador de Pasarela Sandbox
  readonly testTarjeta = signal<string>('4242424242424242');
  readonly testMonto = signal<number>(150);
  readonly probandoPasarela = signal(false);
  readonly resultadoPrueba = signal<{ exito: boolean; mensaje: string } | null>(null);

  ngOnInit(): void {
    this.cargar();
  }

  cargar(): void {
    this.cargando.set(true);
    this.error.set(null);
    const est = this.estadoFiltro() === 'todos' ? undefined : this.estadoFiltro();
    const prov = this.proveedorFiltro() === 'todos' ? undefined : this.proveedorFiltro();

    this.pagosServ.listarPagos(est, prov).subscribe({
      next: (data) => {
        this.pagos.set(data);
        this.cargando.set(false);
      },
      error: (err) => {
        this.cargando.set(false);
        const detail = err?.error?.detail?.toString() ?? 'Error al cargar las transacciones de pago';
        this.error.set(detail);
      },
    });
  }

  reembolsar(idPago: number): void {
    const ok = window.confirm(`¿Estás seguro de solicitar el reembolso del pago #${idPago}? Esta acción anulará la transacción.`);
    if (!ok) return;

    this.reembolsandoId.set(idPago);
    this.pagosServ.reembolsarPago(idPago).subscribe({
      next: (res) => {
        this.reembolsandoId.set(null);
        this.snackbar.open(res.mensaje, 'Cerrar', { duration: 4000 });
        this.cargar();
      },
      error: (err) => {
        this.reembolsandoId.set(null);
        const detail = err?.error?.detail?.toString() ?? 'Error al procesar el reembolso';
        this.snackbar.open(detail, 'Cerrar', { duration: 5000 });
      },
    });
  }

  probarTarjetaSandbox(): void {
    const num = this.testTarjeta().replace(/\s/g, '');
    this.probandoPasarela.set(true);
    this.resultadoPrueba.set(null);

    setTimeout(() => {
      this.probandoPasarela.set(false);
      if (num.startsWith('4000') || num.endsWith('0002') || num.includes('0000')) {
        this.resultadoPrueba.set({
          exito: false,
          mensaje: 'Transacción rechazada por la pasarela: Fondos insuficientes o tarjeta inválida (Error 4002).',
        });
      } else {
        this.resultadoPrueba.set({
          exito: true,
          mensaje: `Transacción APROBADA exitosamente por Stripe Sandbox por el monto de Bs. ${this.testMonto().toFixed(2)}. Transacción ID: TXN-TEST-${Date.now()}`,
        });
      }
    }, 1200);
  }

  simularWebhookPrueba(): void {
    const txnId = `TXN-WEBHOOK-${Math.floor(Math.random() * 90000 + 10000)}`;
    this.pagosServ.simularWebhook({
      transaccion_id: txnId,
      monto: this.testMonto(),
      estado: 'aprobado',
      proveedor: 'STRIPE',
    }).subscribe({
      next: (res) => {
        this.snackbar.open(`Webhook: ${res.mensaje}`, 'OK', { duration: 4000 });
        this.cargar();
      },
      error: () => {
        this.snackbar.open('Error al simular webhook', 'Cerrar', { duration: 4000 });
      },
    });
  }
}
