import { Component, computed, inject, signal } from '@angular/core';
import { CommonModule, CurrencyPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { lastValueFrom } from 'rxjs';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatSelectModule } from '@angular/material/select';
import { MatInputModule } from '@angular/material/input';
import { MatSnackBar, MatSnackBarModule } from '@angular/material/snack-bar';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';

import { AuthService } from '../core/auth.service';
import { SucursalService } from '../services/sucursal.service';
import { CatalogoService } from '../services/catalogo.service';
import { ReportesService, ReporteFiltros } from '../services/reportes.service';
import { Categoria, Temporada } from '../models/catalogo';
import {
  MasVendidoRow,
  ReservasReporte,
  ResumenReporte,
  RotacionRow,
  StockCriticoRow,
  TendenciaRow,
  VentaSucursalRow,
} from '../models/reportes';
import { NavbarComponent } from '../shared/navbar';
import { FsChartComponent } from '../charts/fs-chart';

const PALETA = [
  '#4f46e5', '#7c3aed', '#db2777', '#ea580c', '#f59e0b',
  '#16a34a', '#0891b2', '#2563eb', '#9333ea', '#e11d48',
];

@Component({
  selector: 'app-reportes',
  templateUrl: './reportes.html',
  styleUrl: './reportes.scss',
  standalone: true,
  imports: [
    CommonModule,
    FormsModule,
    CurrencyPipe,
    MatCardModule,
    MatButtonModule,
    MatIconModule,
    MatFormFieldModule,
    MatSelectModule,
    MatInputModule,
    MatSnackBarModule,
    MatProgressSpinnerModule,
    NavbarComponent,
    FsChartComponent,
  ],
})
export class ReportesComponent {
  private reportes = inject(ReportesService);
  private catalogo = inject(CatalogoService);
  private sucursalesServ = inject(SucursalService);
  private auth = inject(AuthService);
  private snackbar = inject(MatSnackBar);

  readonly usuario = this.auth.usuario;
  readonly sucursales = this.sucursalesServ.sucursales;
  readonly esEncargado = computed(() => this.usuario()?.rol === 'encargado');

  readonly categorias = signal<Categoria[]>([]);
  readonly temporadas = signal<Temporada[]>([]);

  fechaDesde = signal('');
  fechaHasta = signal('');
  sucursalId = signal<number | null>(null);
  categoriaId = signal<number | null>(null);
  temporadaId = signal<number | null>(null);

  readonly cargando = signal(false);
  readonly generado = signal(false);
  readonly error = signal<string | null>(null);

  readonly resumen = signal<ResumenReporte | null>(null);
  readonly ventasSucursal = signal<VentaSucursalRow[]>([]);
  readonly masVendidos = signal<MasVendidoRow[]>([]);
  readonly rotacion = signal<RotacionRow[]>([]);
  readonly stockCritico = signal<StockCriticoRow[]>([]);
  readonly reservas = signal<ReservasReporte | null>(null);
  readonly tendencias = signal<TendenciaRow[]>([]);

  constructor() {
    this.catalogo.listarCategorias().subscribe({ next: (l) => this.categorias.set(l) });
    this.catalogo.listarTemporadas().subscribe({ next: (l) => this.temporadas.set(l) });
    if (this.esEncargado() && this.usuario()?.sucursal_id) {
      this.sucursalId.set(this.usuario()!.sucursal_id!);
    }
  }

  private filtros(): ReporteFiltros {
    return {
      fecha_desde: this.fechaDesde() || null,
      fecha_hasta: this.fechaHasta() || null,
      sucursal_id: this.sucursalId(),
      categoria_id: this.categoriaId(),
      temporada_id: this.temporadaId(),
    };
  }

  async generar(): Promise<void> {
    const desde = this.fechaDesde();
    const hasta = this.fechaHasta();
    if (desde && hasta && desde > hasta) {
      this.error.set('La fecha de inicio no puede ser mayor que la fecha de fin');
      return;
    }
    this.error.set(null);
    this.cargando.set(true);
    try {
      const f = this.filtros();
      const [resumen, ventasSucursal, masVendidos, rotacion, stockCritico, reservas, tendencias] =
        await Promise.all([
          lastValueFrom(this.reportes.resumen(f)),
          lastValueFrom(this.reportes.ventasPorSucursal(f)),
          lastValueFrom(this.reportes.masVendidos(f)),
          lastValueFrom(this.reportes.rotacionInvetario(f)),
          lastValueFrom(this.reportes.stockCritico(f)),
          lastValueFrom(this.reportes.reservas(f)),
          lastValueFrom(this.reportes.tendencias(f)),
        ]);
      this.resumen.set(resumen);
      this.ventasSucursal.set(ventasSucursal);
      this.masVendidos.set(masVendidos);
      this.rotacion.set(rotacion);
      this.stockCritico.set(stockCritico);
      this.reservas.set(reservas);
      this.tendencias.set(tendencias);
      this.generado.set(true);
    } catch (err: unknown) {
      const detail = (err as { error?: { detail?: unknown } })?.error?.detail?.toString();
      this.error.set(detail ?? 'Error al generar el reporte, intente de nuevo');
    } finally {
      this.cargando.set(false);
    }
  }

  readonly sinDatos = computed(() => {
    const r = this.resumen();
    return (
      this.generado() &&
      !this.cargando() &&
      (r
        ? r.ventas_total === 0 &&
          r.total_pedidos === 0 &&
          r.stock_critico === 0 &&
          r.reservas_activas === 0
        : true)
    );
  });

  // ---- Datos para gráficos ----
  readonly ventasSucursalChart = computed(() => ({
    labels: this.ventasSucursal().map((v) => v.sucursal.replace('FashionStore ', '')),
    datasets: [
      {
        label: 'Ventas (Bs)',
        data: this.ventasSucursal().map((v) => v.total),
        backgroundColor: PALETA.slice(0, Math.max(1, this.ventasSucursal().length)),
      },
    ],
  }));

  readonly masVendidosChart = computed(() => ({
    labels: this.masVendidos().map((v) => v.producto),
    datasets: [
      {
        label: 'Unidades',
        data: this.masVendidos().map((v) => v.unidades),
        backgroundColor: PALETA.slice(0, Math.max(1, this.masVendidos().length)),
      },
    ],
  }));

  readonly reservasEstadoChart = computed(() => {
    const porEstado = this.reservas()?.por_estado ?? [];
    return {
      labels: porEstado.map((r) => r.estado),
      datasets: [
        {
          label: 'Reservas',
          data: porEstado.map((r) => r.total),
          backgroundColor: PALETA.slice(0, Math.max(1, porEstado.length)),
        },
      ],
    };
  });

  readonly rotacionChart = computed(() => {
    const top = this.rotacion().slice(0, 5);
    return {
      labels: top.map((r) => r.producto),
      datasets: [
        {
          label: 'Rotación',
          data: top.map((r) => r.rotacion),
          backgroundColor: PALETA.slice(0, Math.max(1, top.length)),
        },
      ],
    };
  });

  readonly tendenciasChart = computed(() => ({
    labels: this.tendencias().map((t) => t.temporada),
    datasets: [
      {
        label: 'Monto vendido (Bs)',
        data: this.tendencias().map((t) => t.monto),
        backgroundColor: PALETA.slice(0, Math.max(1, this.tendencias().length)),
      },
    ],
  }));

  // ---- Exportaciones (CU-16: CSV) ----
  exportarCSV(): void {
    const partes: string[] = [];
    partes.push('FashionStore - Reporte generado');
    const r = this.resumen();
    if (r) {
      partes.push('');
      partes.push('RESUMEN EJECUTIVO');
      partes.push(`Ventas totales (Bs),${r.ventas_total.toFixed(2)}`);
      partes.push(`Pedidos,${r.total_pedidos}`);
      partes.push(`Productos activos,${r.total_productos}`);
      partes.push(`Stock critico,${r.stock_critico}`);
      partes.push(`Reservas activas,${r.reservas_activas}`);
    }
    const csv = [
      'Ventas por sucursal',
      ...this.ventasSucursal().map((v) => `${v.sucursal},${v.total.toFixed(2)}`),
      '',
      'Productos mas vendidos',
      'Producto,Categoria,Unidades,Monto',
      ...this.masVendidos().map(
        (v) => `${v.producto},${v.categoria},${v.unidades},${v.monto.toFixed(2)}`,
      ),
      '',
      'Rotacion de inventario',
      'Producto,Unidades vendidas,Stock actual,Rotacion',
      ...this.rotacion().map((v) => `${v.producto},${v.unidades_vendidas},${v.stock_actual},${v.rotacion}`),
      '',
      'Stock critico',
      'Producto,Talla,Color,SKU,Sucursal,Stock minimo,Disponible,Faltante',
      ...this.stockCritico().map(
        (v) =>
          `${v.producto},${v.talla},${v.color},${v.sku},${v.sucursal},${v.stock_minimo},${v.disponible},${v.faltante}`,
      ),
    ].join('\n');
    partes.push('', csv);

    const blob = new Blob(['\uFEFF' + partes.join('\n')], {
      type: 'text/csv;charset=utf-8',
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `reporte_fashionstore_${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  imprimir(): void {
    window.print();
  }
}