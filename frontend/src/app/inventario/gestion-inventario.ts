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
import { MatTabsModule } from '@angular/material/tabs';
import { MatSlideToggleModule } from '@angular/material/slide-toggle';

import { AuthService } from '../core/auth.service';
import { InventarioGlobalOut, MovimientoOut } from '../models/inventario';
import { InventarioService } from '../services/inventario.service';
import { SucursalService } from '../services/sucursal.service';
import { CatalogoService } from '../services/catalogo.service';
import { Categoria } from '../models/catalogo';
import { NavbarComponent } from '../shared/navbar';

@Component({
  selector: 'app-gestion-inventario',
  templateUrl: './gestion-inventario.html',
  styleUrl: './gestion-inventario.scss',
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
    MatTabsModule,
    MatSlideToggleModule,
    NavbarComponent,
  ],
})
export class GestionInventarioComponent implements OnInit {
  private inventarioServ = inject(InventarioService);
  private sucursalesServ = inject(SucursalService);
  private catalogoServ = inject(CatalogoService);
  private auth = inject(AuthService);
  private snackbar = inject(MatSnackBar);

  readonly usuario = this.auth.usuario;
  readonly sucursales = this.sucursalesServ.sucursales;
  readonly categorias = signal<Categoria[]>([]);

  readonly inventario = signal<InventarioGlobalOut[]>([]);
  readonly movimientos = signal<MovimientoOut[]>([]);
  readonly cargando = signal(true);
  readonly cargandoMov = signal(false);
  readonly error = signal<string | null>(null);

  // Filtros
  readonly sucursalFiltro = signal<number | null>(null);
  readonly categoriaFiltro = signal<number | null>(null);
  readonly busqueda = signal('');
  readonly soloStockBajo = signal(false);

  // Formulario de Movimiento
  readonly itemSeleccionado = signal<InventarioGlobalOut | null>(null);
  readonly tipoMovimiento = signal<'entrada' | 'salida' | 'ajuste'>('entrada');
  readonly cantidadMov = signal<number>(1);
  readonly observacionMov = signal('');
  readonly guardandoMov = signal(false);

  // Formulario de Transferencia
  readonly sucursalOrigenId = signal<number | null>(null);
  readonly sucursalDestinoId = signal<number | null>(null);
  readonly varianteTransfId = signal<number | null>(null);
  readonly cantidadTransf = signal<number>(1);
  readonly observacionTransf = signal('');
  readonly guardandoTransf = signal(false);

  readonly esAdmin = computed(() => this.usuario()?.rol === 'admin');

  ngOnInit(): void {
    if (!this.esAdmin() && this.usuario()?.sucursal_id) {
      this.sucursalFiltro.set(this.usuario()!.sucursal_id!);
    }
    this.cargarCategorias();
    this.cargarInventario();
  }

  cargarCategorias(): void {
    this.catalogoServ.listarCategorias().subscribe({
      next: (list) => this.categorias.set(list),
    });
  }

  cargarInventario(): void {
    this.cargando.set(true);
    this.error.set(null);

    this.inventarioServ.obtenerInventarioGlobal({
      sucursal_id: this.sucursalFiltro(),
      categoria_id: this.categoriaFiltro(),
      q: this.busqueda(),
      stock_bajo_solo: this.soloStockBajo(),
    }).subscribe({
      next: (data) => {
        this.inventario.set(data);
        this.cargando.set(false);
      },
      error: (err) => {
        this.cargando.set(false);
        const detail = err?.error?.detail?.toString() ?? 'Error al cargar inventario';
        this.error.set(detail);
      },
    });
  }

  cargarHistorialMovimientos(): void {
    this.cargandoMov.set(true);
    this.inventarioServ.obtenerMovimientos(this.sucursalFiltro() ?? undefined).subscribe({
      next: (data) => {
        this.movimientos.set(data);
        this.cargandoMov.set(false);
      },
      error: () => this.cargandoMov.set(false),
    });
  }

  abrirMovimientoModal(item: InventarioGlobalOut, tipo: 'entrada' | 'salida' | 'ajuste'): void {
    this.itemSeleccionado.set(item);
    this.tipoMovimiento.set(tipo);
    this.cantidadMov.set(1);
    this.observacionMov.set('');
  }

  cerrarModal(): void {
    this.itemSeleccionado.set(null);
  }

  guardarMovimiento(): void {
    const item = this.itemSeleccionado();
    if (!item) return;

    if (this.cantidadMov() <= 0) {
      this.snackbar.open('La cantidad debe ser mayor a 0', 'Cerrar', { duration: 3000 });
      return;
    }

    this.guardandoMov.set(true);
    this.inventarioServ.crearMovimiento({
      variante_id: item.variante_id,
      sucursal_id: item.sucursal_id,
      tipo_movimiento: this.tipoMovimiento(),
      cantidad: this.cantidadMov(),
      observacion: this.observacionMov(),
    }).subscribe({
      next: () => {
        this.guardandoMov.set(false);
        this.cerrarModal();
        this.snackbar.open('¡Movimiento de inventario registrado con éxito!', 'OK', { duration: 4000 });
        this.cargarInventario();
      },
      error: (err) => {
        this.guardandoMov.set(false);
        const detail = err?.error?.detail?.toString() ?? 'Error al registrar movimiento';
        this.snackbar.open(detail, 'Cerrar', { duration: 5000 });
      },
    });
  }

  prepararTransferencia(item: InventarioGlobalOut): void {
    this.varianteTransfId.set(item.variante_id);
    this.sucursalOrigenId.set(item.sucursal_id);
    const otraSuc = this.sucursales().find((s) => s.id_sucursal !== item.sucursal_id);
    if (otraSuc) {
      this.sucursalDestinoId.set(otraSuc.id_sucursal);
    }
    this.cantidadTransf.set(1);
    this.observacionTransf.set('');
  }

  guardarTransferencia(): void {
    const varId = this.varianteTransfId();
    const origId = this.sucursalOrigenId();
    const destId = this.sucursalDestinoId();

    if (!varId || !origId || !destId) {
      this.snackbar.open('Selecciona la sucursal de origen, destino y variante', 'Cerrar', { duration: 3000 });
      return;
    }

    if (origId === destId) {
      this.snackbar.open('La sucursal de origen y destino deben ser distintas', 'Cerrar', { duration: 3000 });
      return;
    }

    this.guardandoTransf.set(true);
    this.inventarioServ.transferirStock({
      variante_id: varId,
      sucursal_origen_id: origId,
      sucursal_destino_id: destId,
      cantidad: this.cantidadTransf(),
      observacion: this.observacionTransf(),
    }).subscribe({
      next: (res) => {
        this.guardandoTransf.set(false);
        this.varianteTransfId.set(null);
        this.snackbar.open(res.mensaje, 'OK', { duration: 5000 });
        this.cargarInventario();
      },
      error: (err) => {
        this.guardandoTransf.set(false);
        const detail = err?.error?.detail?.toString() ?? 'Error al transferir stock';
        this.snackbar.open(detail, 'Cerrar', { duration: 5000 });
      },
    });
  }

  actualizarStockMin(item: InventarioGlobalOut, nuevoMin: number): void {
    if (nuevoMin < 0) return;
    this.inventarioServ.actualizarStockMinimo(item.id_inventario, nuevoMin).subscribe({
      next: () => {
        this.snackbar.open('Stock mínimo actualizado', undefined, { duration: 2000 });
        this.cargarInventario();
      },
    });
  }

  onImagenError(event: Event): void {
    const img = event.target as HTMLImageElement;
    img.src = 'assets/placeholder.svg';
  }
}
