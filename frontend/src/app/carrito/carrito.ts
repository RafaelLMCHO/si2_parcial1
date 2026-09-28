import { Component, computed, inject, signal } from '@angular/core';
import { CommonModule, CurrencyPipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatSelectModule } from '@angular/material/select';
import { MatInputModule } from '@angular/material/input';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';

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
    FormsModule,
    RouterLink,
    MatCardModule,
    MatButtonModule,
    MatIconModule,
    MatFormFieldModule,
    MatSelectModule,
    MatInputModule,
    MatProgressSpinnerModule,
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

  // Metodos de pago digital solicitados: Tarjeta, QR, Efectivo
  readonly metodoPago = signal<'tarjeta' | 'qr' | 'efectivo'>('tarjeta');
  readonly tipoTarjeta = signal<'credito' | 'debito'>('credito');
  readonly qrData = signal<{ qr_url: string; monto: number; referencia: string } | null>(null);
  readonly cargandoQr = signal(false);

  // Datos simulados de tarjeta
  readonly numeroTarjeta = signal('4242 4242 4242 4242');
  readonly expTarjeta = signal('12/28');
  readonly cvcTarjeta = signal('123');

  readonly cargando = signal(false);
  readonly pagando = signal(false);
  readonly resultado = signal<{ id: number; tipo: string; metodo?: string; total?: number; estado?: string } | null>(null);
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
    this.qrData.set(null);
  }

  quitar(id: number): void {
    this.carrito.quitar(id);
    this.error.set(null);
    this.qrData.set(null);
  }

  onImagenError(event: Event): void {
    const img = event.target as HTMLImageElement;
    img.src = 'assets/placeholder.svg';
  }

  onModoCompra(): void {
    this.modo.set('compra');
    this.error.set(null);
    if (this.metodoPago() === 'qr' && !this.qrData()) {
      this.cargarQr();
    }
  }

  seleccionarMetodo(metodo: 'tarjeta' | 'qr' | 'efectivo'): void {
    this.metodoPago.set(metodo);
    this.error.set(null);
    if (metodo === 'qr' && !this.qrData()) {
      this.cargarQr();
    }
  }

  cargarQr(): void {
    const lista = this.items();
    if (lista.length === 0) return;

    this.cargandoQr.set(true);
    this.ventas
      .generarQrDigital({
        sucursal_id: this.sucursalSel() || 1,
        items: lista.map((i) => ({ variante_id: i.variante_id, cantidad: i.cantidad })),
      })
      .subscribe({
        next: (data) => {
          this.cargandoQr.set(false);
          this.qrData.set(data);
        },
        error: () => {
          this.cargandoQr.set(false);
          this.qrData.set({
            monto: this.totalPrecio(),
            qr_url: '',
            referencia: `QR-${Math.floor(100000 + Math.random() * 900000)}`,
          });
        },
      });
  }

  procesarPagoDigital(): void {
    const lista = this.items();
    if (lista.length === 0) return;

    this.error.set(null);
    this.pagando.set(true);

    let tipoPagoPayload = 'tarjeta_credito';
    if (this.metodoPago() === 'tarjeta') {
      tipoPagoPayload = this.tipoTarjeta() === 'debito' ? 'tarjeta_debito' : 'tarjeta_credito';
    } else if (this.metodoPago() === 'qr') {
      tipoPagoPayload = 'qr';
    } else if (this.metodoPago() === 'efectivo') {
      tipoPagoPayload = 'efectivo';
    }

    this.ventas
      .confirmarCompra({
        sucursal_id: this.sucursalSel() || 1,
        items: lista.map((i) => ({ variante_id: i.variante_id, cantidad: i.cantidad })),
        tipo_pago: tipoPagoPayload,
      })
      .subscribe({
        next: (res) => {
          this.pagando.set(false);
          this.resultado.set({
            id: res.id_pedido,
            tipo: 'compra',
            metodo: this.metodoPago(),
            total: res.total,
            estado: res.estado,
          });
          this.carrito.limpiar();
        },
        error: (err) => {
          this.pagando.set(false);
          const detail = err?.error?.detail?.toString();
          this.error.set(detail ?? 'Error al procesar el pago o confirmar la compra digital.');
        },
      });
  }

  confirmar(): void {
    if (this.modo() === 'compra') {
      this.procesarPagoDigital();
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