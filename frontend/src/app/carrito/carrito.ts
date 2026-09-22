import { Component, computed, inject, signal } from '@angular/core';
import { CommonModule, CurrencyPipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatSelectModule } from '@angular/material/select';
import { MatInputModule } from '@angular/material/input';

import { CarritoService } from '../services/carrito.service';
import { ReservaService } from '../services/reserva.service';
import { SucursalService } from '../services/sucursal.service';
import { VentasService } from '../services/ventas.service';
import { NavbarComponent } from '../shared/navbar';

@Component({
  selector: 'app-carrito',
  templateUrl: './carrito.html',
  styleUrl: './carrito.scss',
  standalone: true,
  imports: [
    CommonModule,
    CurrencyPipe,
    RouterLink,
    MatCardModule,
    MatButtonModule,
    MatIconModule,
    MatFormFieldModule,
    MatSelectModule,
    MatInputModule,
    NavbarComponent,
  ],
})
export class CarritoComponent {
  private carrito = inject(CarritoService);
  private reservas = inject(ReservaService);
  private sucursalesServ = inject(SucursalService);
  private ventas = inject(VentasService);

  readonly items = this.carrito.items;
  readonly totalPrendas = this.carrito.totalPrendas;
  readonly vacio = this.carrito.vacio;
  readonly sucursales = this.sucursalesServ.sucursales;

  readonly sucursalSel = signal<number | null>(null);
  readonly fechaSel = signal('');
  readonly horaSel = signal('10:00');
  readonly modo = signal<'reserva' | 'compra'>('reserva');
  readonly cargando = signal(false);
  readonly pagando = signal(false);
  readonly mostrarPago = signal(false);
  readonly resultado = signal<{ id: number; tipo: string } | null>(null);
  readonly error = signal<string | null>(null);

  readonly hoy = new Date().toISOString().slice(0, 10);
  readonly totalPrecio = computed(() =>
    this.items().reduce((acc, i) => acc + i.precio * i.cantidad, 0),
  );

  readonly sucursalActual = computed(() =>
    this.sucursales().find((s) => s.id_sucursal === this.sucursalSel()),
  );

  readonly horarioLabel = computed(() => {
    const s = this.sucursalActual();
    return s?.horario_apertura && s?.horario_cierre
      ? `Atención: ${s.horario_apertura.slice(0, 5)} a ${s.horario_cierre.slice(0, 5)}`
      : null;
  });

  cambiarCantidad(id: number, cantidad: number): void {
    this.carrito.cambiarCantidad(id, cantidad);
  }

  quitar(id: number): void {
    this.carrito.quitar(id);
    this.error.set(null);
  }

  onImagenError(event: Event): void {
    const img = event.target as HTMLImageElement;
    img.src = 'assets/placeholder.svg';
  }

  iniciarCompra(): void {
    const lista = this.items();
    if (lista.length === 0) return;

    this.error.set(null);
    this.cargando.set(true);
    const returnUrl = window.location.origin;

    this.ventas
      .crearCheckout({
        sucursal_id: this.sucursalSel() || 1,
        items: lista.map((i) => ({ variante_id: i.variante_id, cantidad: i.cantidad })),
        return_url: returnUrl,
      })
      .subscribe({
        next: (sesion) => {
          this.cargando.set(false);
          if (sesion.simulado || !sesion.checkout_url) {
            // Pasarela en modo simulado (sin claves reales): formulario inline
            this.mostrarPago.set(true);
            return;
          }
          // Pasarela real: redirigir a la página de Stripe (Checkout alojado)
          window.location.href = sesion.checkout_url;
        },
        error: (err) => {
          this.cargando.set(false);
          const detail = err?.error?.detail?.toString();
          this.error.set(detail ?? 'No se pudo iniciar el pago, verifique stock e intente de nuevo');
        },
      });
  }

  procesarPagoSimulado(): void {
    const lista = this.items();
    this.error.set(null);
    this.pagando.set(true);

    this.ventas
      .confirmarCompra({
        sucursal_id: this.sucursalSel() || 1,
        items: lista.map((i) => ({ variante_id: i.variante_id, cantidad: i.cantidad })),
      })
      .subscribe({
        next: (res) => {
          this.pagando.set(false);
          this.mostrarPago.set(false);
          this.resultado.set({ id: res.id_pedido, tipo: 'compra' });
          this.carrito.limpiar();
        },
        error: (err) => {
          this.pagando.set(false);
          const detail = err?.error?.detail?.toString();
          this.error.set(detail ?? 'Error al procesar el pago o confirmar la compra.');
        },
      });
  }

  confirmar(): void {
    if (this.modo() === 'compra') {
      this.iniciarCompra();
      return;
    }

    const sucursalId = this.sucursalSel();
    const fecha = this.fechaSel();
    const hora = this.horaSel();
    const lista = this.items();

    if (sucursalId == null) {
      this.error.set('Selecciona la sucursal donde te probarás las prendas');
      return;
    }
    if (!fecha || fecha < this.hoy) {
      this.error.set('Selecciona una fecha de atención válida (hoy o posterior)');
      return;
    }
    if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(hora)) {
      this.error.set('Selecciona un horario de atención válido (HH:MM)');
      return;
    }

    this.error.set(null);
    this.cargando.set(true);
    this.reservas
      .crear({
        sucursal_id: sucursalId,
        fecha_reserva: fecha,
        hora_atencion: hora,
        items: lista.map((i) => ({ variante_id: i.variante_id, cantidad: i.cantidad })),
      })
      .subscribe({
        next: (r) => {
          this.cargando.set(false);
          this.resultado.set({ id: r.id_reserva, tipo: 'reserva' });
          this.carrito.limpiar();
        },
        error: (err) => {
          this.cargando.set(false);
          const detail = err?.error?.detail?.toString();
          this.error.set(detail ?? 'No se pudo crear la reserva, intente de nuevo');
        },
      });
  }
}