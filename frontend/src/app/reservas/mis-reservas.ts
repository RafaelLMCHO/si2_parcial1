import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterLink } from '@angular/router';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatSnackBar, MatSnackBarModule } from '@angular/material/snack-bar';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';

import { AuthService } from '../core/auth.service';
import { Reserva } from '../models/reservas';
import { ReservaService } from '../services/reserva.service';
import { VentasService } from '../services/ventas.service';
import { NavbarComponent } from '../shared/navbar';

const ESTADO_STYLE: Record<string, { label: string; color: string }> = {
  pendiente: { label: 'PENDIENTE', color: '#f57c00' },
  preparada: { label: 'PREPARADA', color: '#1976d2' },
  completada: { label: 'COMPLETADA', color: '#2e7d32' },
  cancelada: { label: 'CANCELADA', color: '#757575' },
};

@Component({
  selector: 'app-mis-reservas',
  templateUrl: './mis-reservas.html',
  styleUrl: './mis-reservas.scss',
  standalone: true,
  imports: [
    CommonModule,
    RouterLink,
    MatCardModule,
    MatButtonModule,
    MatIconModule,
    MatSnackBarModule,
    MatProgressSpinnerModule,
    NavbarComponent,
  ],
})
export class MisReservasComponent implements OnInit {
  private reservasServ = inject(ReservaService);
  private ventasServ = inject(VentasService);
  private auth = inject(AuthService);
  private snackbar = inject(MatSnackBar);
  private router = inject(Router);

  readonly reservas = signal<Reserva[]>([]);
  readonly cargando = signal(true);
  readonly error = signal<string | null>(null);
  readonly cancelandoId = signal<number | null>(null);
  readonly actualizandoId = signal<number | null>(null);
  readonly pagandoId = signal<number | null>(null);

  readonly esCliente = computed(() => this.auth.usuario()?.rol === 'cliente');
  readonly esEncargado = computed(() => this.auth.usuario()?.rol === 'encargado');
  readonly titulo = computed(() =>
    this.esCliente() ? 'Mis reservas' : 'Reservas de mi sucursal',
  );

  ngOnInit(): void {
    // En ngOnInit el signal ya tiene el usuario cargado desde localStorage
    // El encargado tiene su propio panel dedicado con todos los botones de CU-18
    if (this.auth.usuario()?.rol === 'encargado') {
      this.router.navigate(['/encargado/reservas/pendientes']);
      return;
    }
    this.cargar();
  }

  cargar(): void {
    this.cargando.set(true);
    this.error.set(null);
    this.reservasServ.misReservas().subscribe({
      next: (r) => {
        this.reservas.set(r);
        this.cargando.set(false);
      },
      error: () => {
        this.cargando.set(false);
        this.error.set('Error al cargar las reservas, intente de nuevo');
      },
    });
  }

  estadoDe(estado: string): { label: string; color: string } {
    return ESTADO_STYLE[estado] ?? { label: estado, color: '#757575' };
  }

  puedeCancelar(r: Reserva): boolean {
    return r.estado === 'pendiente' || r.estado === 'preparada';
  }

  itemLabel(item: { producto?: { nombre: string } | null; variante?: { talla?: { nombre: string } | null; color?: { nombre: string } | null } | null; cantidad: number }): string {
    const nombre = item.producto?.nombre ?? 'Prenda';
    const talla = item.variante?.talla?.nombre;
    const color = item.variante?.color?.nombre;
    const specs = [talla ? `Talla ${talla}` : '', color ? `Color ${color}` : '']
      .filter((s) => s)
      .join(' · ');
    return `${nombre}${specs ? ` (${specs})` : ''} ×${item.cantidad}`;
  }

  cancelar(id: number): void {
    const ok = window.confirm(`¿Deseas cancelar la reserva #${id}?`);
    if (!ok) return;
    this.cancelandoId.set(id);
    this.reservasServ.cancelar(id).subscribe({
      next: () => {
        this.cancelandoId.set(null);
        this.snackbar.open('Reserva cancelada exitosamente', 'Cerrar', { duration: 4000 });
        this.cargar();
      },
      error: (err) => {
        this.cancelandoId.set(null);
        const detail = err?.error?.detail?.toString() ?? 'No se pudo cancelar la reserva';
        this.snackbar.open(detail, 'Cerrar', { duration: 5000 });
      },
    });
  }

  preparar(id: number): void {
    if (!this.esEncargado()) return;
    this.actualizandoId.set(id);
    this.reservasServ.preparar(id).subscribe({
      next: () => {
        this.actualizandoId.set(null);
        this.snackbar.open('Reserva marcada como preparada. Se notificó al cliente.', 'Cerrar', { duration: 4000 });
        this.cargar();
      },
      error: (err) => {
        this.actualizandoId.set(null);
        const detail = err?.error?.detail?.toString() ?? 'No se pudo preparar la reserva';
        this.snackbar.open(detail, 'Cerrar', { duration: 5000 });
      }
    });
  }

  completar(id: number): void {
    if (!this.esEncargado()) return;
    this.actualizandoId.set(id);
    this.reservasServ.completar(id).subscribe({
      next: () => {
        this.actualizandoId.set(null);
        this.snackbar.open('Reserva marcada como completada.', 'Cerrar', { duration: 4000 });
        this.cargar();
      },
      error: (err) => {
        this.actualizandoId.set(null);
        const detail = err?.error?.detail?.toString() ?? 'No se pudo completar la reserva';
        this.snackbar.open(detail, 'Cerrar', { duration: 5000 });
      }
    });
  }

  pagar(id: number): void {
    const ok = window.confirm(`¿Deseas pagar la reserva #${id} mediante la pasarela Stripe Sandbox y completarla como compra digital?`);
    if (!ok) return;
    this.pagandoId.set(id);
    this.ventasServ.pagarReservaDigital(id).subscribe({
      next: (res) => {
        this.pagandoId.set(null);
        this.snackbar.open(`¡Pago exitoso! Pedido #${res.id_pedido} registrado como COMPRA DIGITAL.`, 'Ver Compras', { duration: 6000 })
          .onAction().subscribe(() => this.router.navigate(['/compras']));
        this.cargar();
      },
      error: (err) => {
        this.pagandoId.set(null);
        const detail = err?.error?.detail?.toString() ?? 'No se pudo procesar el pago digital';
        this.snackbar.open(detail, 'Cerrar', { duration: 5000 });
      },
    });
  }
}