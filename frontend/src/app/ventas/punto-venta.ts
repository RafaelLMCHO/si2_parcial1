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
import { ComprobantePresencialResponse, CobroTarjetaResponse, CobroTarjetaVerificacion, QrCobroEstado, QrCobroResponse } from '../models/ventas';
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

const INTERVALO_SONDEO_MS = 2500;

// Tarjetas de prueba de Stripe. Los botones de demo no mandan "aprobado" ni
// "rechazado": mandan la tarjeta que el cajero dice que uso el cliente, y la
// pasarela (o su version simulada) es la que decide. Por eso el mismo par de
// tarjetas sirve para el modo real y para la demostracion sin clave.
const TARJETA_APROBADA = '4242 4242 4242 4242';
const TARJETA_RECHAZADA = '4000 0000 0000 0002';

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

  readonly cobroQr = signal<QrCobroResponse | null>(null);
  // El estado se comparte con el cobro QR porque la forma de mostrarlo es la
  // misma: pendiente, aprobado o rechazado, con su motivo. Lo que cambia entre
  // QR y tarjeta es como se pide el pago, no como se ve el resultado.
  readonly estadoCobroQr = signal<QrCobroEstado | null>(null);
  // Marca que el cobro abierto quedo sin resolver (vencido o rechazado) y hay
  // que generar otro. No es solo de QR: el rechazo de tarjeta tambien lo usa.
  readonly cobroFallido = signal(false);
  readonly cobroTarjeta = signal<CobroTarjetaResponse | null>(null);

  private intervaloQr: ReturnType<typeof setInterval>[] = [];
  private modoSondeo: 'qr' | 'tarjeta' = 'qr';
  // Se recuerda que boton se aprieto al abrir el cobro. Si se usara el que este
  // seleccionado ahora, cambiar el radio a mitad de cobro anotaria mal el tipo en
  // el comprobante.
  private tipoPagoCobro = 'efectivo';
  private ticketSnapshot: TicketItem[] = [];

  /** El boton de cobrar se bloquea mientras haya un cobro esperando pago.
   *  Abrir otro para el mismo ticket cobraria dos veces las mismas prendas, y
   *  el inventario ya esta reservado por el primero. Vale igual para QR y
   *  tarjeta. */
  readonly esperandoPago = computed(() => this.estadoCobroQr()?.estado === 'pendiente');

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
    this.cancelarSondeoQr();
    this.ticket.set([]);
    this.montoEntregado.set(0);
    this.error.set(null);
    this.cobroQr.set(null);
    this.estadoCobroQr.set(null);
    this.cobroFallido.set(false);
    this.cobroTarjeta.set(null);
  }

  private itemsParaPayload() {
    return this.ticket().map((i) => ({ variante_id: i.variante_id, cantidad: i.cantidad }));
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

    if (this.tipoPago() === 'qr') {
      this.iniciarCobroQr();
      return;
    }

    // Débito y crédito tampoco se aprueban solos: abren un cobro pendiente y
    // esperan a que la pasarela confirme, igual que el QR.
    if (this.tipoPago() === 'tarjeta_debito' || this.tipoPago() === 'tarjeta_credito') {
      this.iniciarCobroTarjeta();
      return;
    }

    this.procesandoVenta.set(true);

    const payload = {
      sucursal_id: this.sucursalSel(),
      tipo_pago: this.tipoPago(),
      items: this.itemsParaPayload(),
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

  /**
   * Cobra por QR contra la pasarela y queda a la espera de su confirmación.
   * El pago no se aprueba aqui: se registra como pendiente y el inventario
   * queda intacto hasta que la pasarela (o el disparador de demostracion)
   * confirme el pago.
   */
  private iniciarCobroQr(): void {
    this.cancelarSondeoQr();
    this.cobroFallido.set(false);
    this.procesandoVenta.set(true);
    this.ticketSnapshot = [...this.ticket()];

    const payload = {
      sucursal_id: this.sucursalSel(),
      tipo_pago: 'qr' as const,
      items: this.itemsParaPayload(),
    };

    this.ventasServ.crearCobroQr(payload).subscribe({
      next: (res) => {
        this.procesandoVenta.set(false);
        this.cobroQr.set(res);
        this.estadoCobroQr.set({
          id_pago: res.id_pago,
          id_pedido: res.id_pedido,
          estado: res.estado,
          motivo: null,
          transaccion_id: res.transaccion_id,
          estado_pedido: 'pendiente',
          total: res.total,
          simulado: res.simulado,
        });
        this.iniciarSondeoQr(res.id_pago);
      },
      error: (err) => {
        this.procesandoVenta.set(false);
        this.error.set(err?.error?.detail?.toString() ?? 'No se pudo generar el cobro QR');
      },
    });
  }

  private iniciarSondeoQr(idPago: number, modo: 'qr' | 'tarjeta' = 'qr'): void {
    this.cancelarSondeoQr();
    this.modoSondeo = modo;
    this.intervaloQr.push(setInterval(() => this.sondearCobro(idPago), INTERVALO_SONDEO_MS));
  }

  private cancelarSondeoQr(): void {
    this.modoSondeo = 'qr';
    while (this.intervaloQr.length) {
      clearInterval(this.intervaloQr.pop());
    }
  }

  private sondearCobro(idPago: number): void {
    if (this.modoSondeo === 'tarjeta') {
      this.sondearCobroTarjeta(idPago);
      return;
    }
    this.sondearCobroQr(idPago);
  }

  private sondearCobroQr(idPago: number): void {
    this.ventasServ.estadoCobroQr(idPago).subscribe({
      next: (estado) => {
        this.estadoCobroQr.set(estado);
        if (estado.estado === 'aprobado') {
          this.cancelarSondeoQr();
          this.finalizarVenta(estado.id_pedido);
        } else if (estado.estado === 'rechazado') {
          this.cancelarSondeoQr();
          this.cobroFallido.set(true);
          this.error.set(
            estado.motivo === 'vencido'
              ? 'El cobro QR venció sin recibir el pago. Genera uno nuevo.'
              : 'La pasarela rechazó el pago QR.',
          );
        }
      },
      error: () => {
        // Un fallo puntual de sondeo no debe cortar el cobro: el siguiente
        // intento sigue encolado por el intervalo.
      },
    });
  }

  /**
   * Confirma el cobro como si el cliente hubiera pagado. Solo existe para
   * los cobros que la pasarela marco como simulados, por lo que sirve para
   * demostrar el flujo sin credenciales reales.
   */
  simularPagoQr(): void {
    const cobro = this.cobroQr();
    if (!cobro) return;
    this.procesandoVenta.set(true);

    this.ventasServ.simularPagoQr(cobro.id_pago).subscribe({
      next: () => {
        this.sondearCobroQr(cobro.id_pago);
        this.snackbar.open('Pago del cliente recibido', 'OK', { duration: 3000 });
      },
      error: (err) => {
        this.procesandoVenta.set(false);
        this.error.set(err?.error?.detail?.toString() ?? 'No se pudo confirmar el pago');
      },
    });
  }

  /**
   * Abre un cobro con tarjeta y lo deja pendiente, igual que el QR.
   *
   * A diferencia del efectivo, acá no se aprueba nada al instante: el inventario
   * queda reservado y el pedido sigue pendiente hasta que la pasarela confirme
   * que el dinero entró. Débito y crédito recorren exactamente el mismo camino.
   */
  private iniciarCobroTarjeta(): void {
    this.cancelarSondeoQr();
    this.cobroFallido.set(false);
    this.procesandoVenta.set(true);
    this.ticketSnapshot = [...this.ticket()];

    const tipo = this.tipoPago() === 'tarjeta_debito' ? 'tarjeta_debito' : 'tarjeta_credito';
    this.tipoPagoCobro = tipo;

    this.ventasServ.crearCobroTarjeta({
      sucursal_id: this.sucursalSel(),
      tipo_pago: tipo,
      items: this.itemsParaPayload(),
    }).subscribe({
      next: (res) => {
        this.procesandoVenta.set(false);
        this.cobroTarjeta.set(res);
        this.estadoCobroQr.set({
          id_pago: res.id_pago,
          id_pedido: res.id_pedido,
          estado: res.estado,
          motivo: null,
          transaccion_id: res.transaccion_id,
          estado_pedido: 'pendiente',
          total: res.total,
          simulado: res.simulado,
        });

        if (res.checkout_url) {
          // Con pasarela real se le abre la pagina de pago al cliente y el POS se
          // queda preguntando cada 2,5 s si el dinero entró.
          this.abrirPasarela(res.checkout_url);
          this.iniciarSondeoQr(res.id_pago, 'tarjeta');
        }
        // Sin pasarela no hay nada que sondear: el cobro queda esperando a que el
        // cajero comunique la tarjeta con los botones de demostracion. Preguntar
        // con el cuerpo vacio aprobaria el cobro solo, que es justo lo que no
        // puede pasar.
      },
      error: (err) => {
        this.procesandoVenta.set(false);
        this.error.set(err?.error?.detail?.toString() ?? 'No se pudo iniciar el cobro con tarjeta');
      },
    });
  }

  /** Abre la pagina de la pasarela en una pestana aparte.
   *
   *  Se usa una pestana nueva y no la actual para que el cajero no pierda el
   *  ticket ni deje de ver el sondeo mientras el cliente paga. */
  abrirPasarela(url: string): void {
    const ventana = window.open(url, '_blank', 'noopener');
    if (!ventana) {
      this.error.set('El navegador bloqueó la ventana de pago. Permití los pop-ups para cobrar con tarjeta.');
    } else {
      this.snackbar.open('Pagina de pago abierta en otra pestana', 'OK', { duration: 3000 });
    }
  }

  private sondearCobroTarjeta(idPago: number): void {
    // Sin tarjeta: aca la pasarela real es la que responde si el pago entro.
    this.ventasServ.verificarCobroTarjeta(idPago).subscribe({
      next: (res) => this.aplicarResultadoTarjeta(res),
      error: () => {
        // Un fallo puntual no corta el cobro: sigue el siguiente intento.
      },
    });
  }

  /** Botones de demostracion: comunican que tarjeta uso el cliente y dejan que
   *  el servidor decida. No se manda el resultado, se manda la tarjeta. */
  resolverPagoTarjetaSimulado(aprobado: boolean): void {
    const cobro = this.cobroTarjeta();
    if (!cobro) return;
    this.procesandoVenta.set(true);
    this.ventasServ
      .verificarCobroTarjeta(cobro.id_pago, {
        numero_tarjeta: aprobado ? TARJETA_APROBADA : TARJETA_RECHAZADA,
      })
      .subscribe({
        next: (res) => this.aplicarResultadoTarjeta(res),
        error: (err) => {
          this.procesandoVenta.set(false);
          this.error.set(err?.error?.detail?.toString() ?? 'No se pudo verificar el pago');
        },
      });
  }

  private aplicarResultadoTarjeta(res: CobroTarjetaVerificacion): void {
    this.estadoCobroQr.update((prev) => (prev ? { ...prev, estado: res.estado } : prev));
    if (res.estado === 'aprobado') {
      this.cancelarSondeoQr();
      this.finalizarVenta(this.cobroTarjeta()?.id_pedido ?? 0, this.tipoPagoCobro);
    } else if (res.estado === 'rechazado') {
      this.cancelarSondeoQr();
      this.procesandoVenta.set(false);
      this.cobroFallido.set(true);
      this.error.set(res.motivo ?? 'La pasarela rechazó el pago con tarjeta.');
    }
  }

  private finalizarVenta(idPedido: number, tipoPago: string = 'qr'): void {
    this.procesandoVenta.set(false);
    this.cobroQr.set(null);
    this.cobroTarjeta.set(null);
    const venta = this.ticketSnapshot;
    this.comprobante.set({
      id_pedido: idPedido,
      total: this.estadoCobroQr()?.total ?? this.totalTicket(),
      estado: 'pagado',
      tipo_pago: tipoPago,
      fecha_pedido: new Date().toISOString(),
      sucursal_nombre: this.sucursalNombre(),
      cajero_nombre: this.usuario()?.nombre,
      items: venta.map((i) => ({
        variante_id: i.variante_id,
        cantidad: i.cantidad,
        precio_unitario: i.precio,
        subtotal: i.precio * i.cantidad,
        producto_nombre: i.producto_nombre,
        sku: i.sku,
        talla: i.talla,
        color: i.color,
      })),
    });
    this.limpiarTicket();
    const como = tipoPago === 'qr' ? 'Pago QR' : 'Pago con tarjeta';
    this.snackbar.open(`¡${como} confirmado! Venta registrada`, 'OK', { duration: 4000 });
  }

  onImagenError(event: Event): void {
    const img = event.target as HTMLImageElement;
    img.src = 'assets/placeholder.svg';
  }
}
