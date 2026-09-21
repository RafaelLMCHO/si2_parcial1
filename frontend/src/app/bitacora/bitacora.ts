import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatTableModule } from '@angular/material/table';
import { MatTooltipModule } from '@angular/material/tooltip';

import { RegistroBitacora } from '../models/bitacora';
import { Usuario } from '../models/usuario';
import { BitacoraService } from '../services/bitacora.service';
import { UsuariosService } from '../services/usuarios.service';
import { NavbarComponent } from '../shared/navbar';

@Component({
  selector: 'app-bitacora',
  templateUrl: './bitacora.html',
  styleUrl: './bitacora.scss',
  standalone: true,
  imports: [
    CommonModule,
    FormsModule,
    MatButtonModule,
    MatIconModule,
    MatInputModule,
    MatSelectModule,
    MatProgressSpinnerModule,
    MatTableModule,
    MatTooltipModule,
    NavbarComponent,
  ],
})
export class BitacoraComponent implements OnInit {
  private bitacora = inject(BitacoraService);
  private usuariosSvc = inject(UsuariosService);

  readonly registros = signal<RegistroBitacora[]>([]);
  readonly usuarios = signal<Usuario[]>([]);
  readonly cargando = signal(false);
  readonly error = signal<string | null>(null);
  readonly total = signal(0);
  readonly pagina = signal(1);
  readonly columnas = ['fecha', 'usuario', 'accion', 'entidad', 'detalle', 'origen'];

  accion = '';
  usuarioId: number | null = null;
  entidad = '';
  fechaDesde = '';
  fechaHasta = '';

  ngOnInit(): void {
    this.usuariosSvc.listar().subscribe({ next: (u) => this.usuarios.set(u) });
    this.buscar();
  }

  buscar(): void {
    this.pagina.set(1);
    this.cargar();
  }

  limpiar(): void {
    this.accion = '';
    this.usuarioId = null;
    this.entidad = '';
    this.fechaDesde = '';
    this.fechaHasta = '';
    this.buscar();
  }

  cargarMas(): void {
    this.pagina.set(this.pagina() + 1);
    this.cargar(false);
  }

  cargar(reiniciar = true): void {
    const page = this.pagina();
    this.cargando.set(true);
    this.error.set(null);
    this.bitacora
      .listar(
        {
          usuario_id: this.usuarioId,
          accion: this.accion?.trim() || null,
          entidad: this.entidad?.trim() || null,
          fecha_desde: this.fechaDesde || null,
          fecha_hasta: this.fechaHasta || null,
        },
        page,
      )
      .subscribe({
        next: (resp) => {
          this.total.set(this.bitacora.tope(resp));
          this.registros.set(reiniciar ? resp.body ?? [] : [...this.registros(), ...(resp.body ?? [])]);
          this.cargando.set(false);
        },
        error: (err) => {
          this.cargando.set(false);
          this.error.set(this.mensajeError(err));
        },
      });
  }

  usuarioLabel(r: RegistroBitacora): string {
    return r.usuario_nombre ?? (r.usuario_id != null ? `#${r.usuario_id}` : 'Anónimo');
  }

  private mensajeError(err: unknown): string {
    const detail = (err as { error?: { detail?: unknown } })?.error?.detail;
    if (typeof detail === 'string') return detail;
    return 'No se pudo consultar la bitácora.';
  }
}