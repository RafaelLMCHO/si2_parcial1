import { Component, inject, OnInit, signal } from '@angular/core';
import { CommonModule, CurrencyPipe, DatePipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatChipsModule } from '@angular/material/chips';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatDividerModule } from '@angular/material/divider';

import { PedidoHistorial } from '../models/ventas';
import { VentasService } from '../services/ventas.service';
import { NavbarComponent } from '../shared/navbar';

@Component({
  selector: 'app-mis-compras',
  templateUrl: './mis-compras.html',
  styleUrl: './mis-compras.scss',
  standalone: true,
  imports: [
    CommonModule,
    CurrencyPipe,
    DatePipe,
    RouterLink,
    MatCardModule,
    MatButtonModule,
    MatIconModule,
    MatChipsModule,
    MatProgressSpinnerModule,
    MatDividerModule,
    NavbarComponent,
  ],
})
export class MisComprasComponent implements OnInit {
  private ventasServ = inject(VentasService);

  readonly pedidos = signal<PedidoHistorial[]>([]);
  readonly cargando = signal(true);
  readonly error = signal<string | null>(null);

  ngOnInit(): void {
    this.cargar();
  }

  cargar(): void {
    this.cargando.set(true);
    this.error.set(null);
    this.ventasServ.obtenerHistorial().subscribe({
      next: (data) => {
        this.pedidos.set(data);
        this.cargando.set(false);
      },
      error: (err) => {
        this.cargando.set(false);
        const detail = err?.error?.detail?.toString() ?? 'Error al cargar el historial de compras';
        this.error.set(detail);
      },
    });
  }

  onImagenError(event: Event): void {
    const img = event.target as HTMLImageElement;
    img.src = 'assets/placeholder.svg';
  }
}
