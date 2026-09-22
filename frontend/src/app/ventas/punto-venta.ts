import { Component, computed, inject, OnInit, signal } from '@angular/core';
import { CommonModule, CurrencyPipe, DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';
import { MatSnackBar, MatSnackBarModule } from '@angular/material/snack-bar';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatDividerModule } from '@angular/material/divider';
import { MatRadioModule } from '@angular/material/radio';

import { AuthService } from '../core/auth.service';
import { CatalogoService } from '../services/catalogo.service';
import { SucursalService } from '../services/sucursal.service';
import { VentasService } from '../services/ventas.service';
import { Producto } from '../models/catalogo';
import { ComprobantePresencialResponse } from '../models/ventas';
import { NavbarComponent } from '../shared/navbar';

export interface TicketItem {
  variante_id: number;
  producto_nombre: string;
  sku: string;
  talla: string;
  color: string;
  precio: number;
  cantidad: number;
  imagen_url?: string | null;
}

@Component({
  selector: 'app-punto-venta',
  templateUrl: './punto-venta.html',
  styleUrl: './punto-venta.scss',
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
    MatInputModule,
    MatSelectModule,
    MatSnackBarModule,
    MatProgressSpinnerModule,
    MatDividerModule,
    MatRadioModule,
    NavbarComponent,
  ],
})
export class PuntoVentaComponent implements OnInit {
  private auth = inject(AuthService);
  private catalogoServ = inject(CatalogoService);
  private sucursalesServ = inject(SucursalService);
  private ventasServ = inject(VentasService);
  private snackbar = inject(MatSnackBar);

  readonly usuario = this.auth.usuario;
  readonly sucursales = this.sucursalesServ.sucursales;

  readonly sucursalSel = signal<number>(1);
  readonly busqueda = signal('');
  readonly productos = signal<Producto[]>([]);
  readonly cargandoProductos = signal(false);
  readonly error = signal<string | null>(null);

  readonly ticket = signal<TicketItem[]>([]);
  readonly tipoPago = signal<'efectivo' | 'tarjeta_debito' | 'tarjeta_credito' | 'qr'>('efectivo');
  readonly montoEntregado = signal<number>(0);
  readonly procesandoVenta = signal(false);
  readonly comprobante = signal<ComprobantePresencialResponse | null>(null);

  readonly totalTicket = computed(() =>
    this.ticket().reduce((acc, i) => acc + i.precio * i.cantidad, 0),
  );

  readonly cambioCalculado = computed(() => {
    const entregado = this.montoEntregado() || 0;
    const total = this.totalTicket();
    return entregado >= total ? entregado - total : 0;
  });

  readonly sucursalNombre = computed(() =>
    this.sucursalesServ.nombreDe(this.sucursalSel()),
  );

  ngOnInit(): void {
    const userSuc = this.usuario()?.sucursal_id;
    if (userSuc) {
      this.sucursalSel.set(userSuc);
    }
    this.cargarCatalogo();
  }

  cargarCatalogo(): void {
    this.cargandoProductos.set(true);
    this.catalogoServ.listarProductos({ q: this.busqueda() }).subscribe({
      next: (list) => {
        this.productos.set(list);
        this.cargandoProductos.set(false);
      },
      error: () => {
        this.cargandoProductos.set(false);
        this.snackbar.open('Error al obtener productos', 'Cerrar', { duration: 3000 });
      },
    });
  }

  onBuscar(): void {
    this.cargarCatalogo();
  }

  agregarAlTicket(p: Producto, v: { id_variante: number; sku?: string | null; talla?: { nombre: string } | null; color?: { nombre: string } | null; precio_extra?: number }): void {
    const precioBase = p.precio + (v.precio_extra || 0);
    const varianteId = v.id_variante;

    const actual = this.ticket();
    const idx = actual.findIndex((i) => i.variante_id === varianteId);

    if (idx >= 0) {
      const copy = [...actual];
      copy[idx] = { ...copy[idx], cantidad: copy[idx].cantidad + 1 };
      this.ticket.set(copy);
    } else {
      this.ticket.set([
        ...actual,
        {
          variante_id: varianteId,
          producto_nombre: p.nombre,
          sku: v.sku || `VAR-${varianteId}`,
          talla: v.talla?.nombre || '—',
          color: v.color?.nombre || '—',
          precio: precioBase,
          cantidad: 1,
          imagen_url: p.imagen_url,
        },
      ]);
    }
    this.snackbar.open(`Agregado a ticket: ${p.nombre}`, undefined, { duration: 1500 });
  }

  cambiarCantidad(varianteId: number, delta: number): void {
    const actual = this.ticket();
    const idx = actual.findIndex((i) => i.variante_id === varianteId);
    if (idx < 0) return;

    const copy = [...actual];
    const nuevaCant = copy[idx].cantidad + delta;
    if (nuevaCant <= 0) {
      copy.splice(idx, 1);
    } else {
      copy[idx] = { ...copy[idx], cantidad: nuevaCant };
    }
    this.ticket.set(copy);
  }

  quitarDelTicket(varianteId: number): void {
    this.ticket.set(this.ticket().filter((i) => i.variante_id !== varianteId));
  }

  limpiarTicket(): void {
    this.ticket.set([]);
    this.montoEntregado.set(0);
    this.error.set(null);
  }

  procesarVentaPresencial(): void {
    const items = this.ticket();
    if (items.length === 0) {
      this.error.set('El ticket de venta está vacío');
      return;
    }

    if (this.tipoPago() === 'efectivo' && this.montoEntregado() < this.totalTicket()) {
      this.error.set(`Monto entregado insuficiente. El total es Bs. ${this.totalTicket().toFixed(2)}`);
      return;
    }

    this.error.set(null);
    this.procesandoVenta.set(true);

    const payload = {
      sucursal_id: this.sucursalSel(),
      tipo_pago: this.tipoPago(),
      items: items.map((i) => ({ variante_id: i.variante_id, cantidad: i.cantidad })),
    };

    this.ventasServ.registrarVentaPresencial(payload).subscribe({
      next: (res) => {
        this.procesandoVenta.set(false);
        this.comprobante.set(res);
        this.limpiarTicket();
        this.snackbar.open('¡Venta registrada exitosamente!', 'OK', { duration: 4000 });
      },
      error: (err) => {
        this.procesandoVenta.set(false);
        const detail = err?.error?.detail?.toString() ?? 'Error al procesar la venta en caja';
        this.error.set(detail);
      },
    });
  }

  cerrarComprobante(): void {
    this.comprobante.set(null);
  }

  onImagenError(event: Event): void {
    const img = event.target as HTMLImageElement;
    img.src = 'assets/placeholder.svg';
  }
}
