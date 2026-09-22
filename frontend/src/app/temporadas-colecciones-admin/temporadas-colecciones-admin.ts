import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { AbstractControl, FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MatCardModule } from '@angular/material/card';
import { MatCheckboxModule } from '@angular/material/checkbox';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';
import { MatSnackBar, MatSnackBarModule } from '@angular/material/snack-bar';
import { MatTableModule } from '@angular/material/table';
import { MatTooltipModule } from '@angular/material/tooltip';

import { Coleccion, Temporada } from '../models/catalogo';
import { CatalogoService } from '../services/catalogo.service';
import { NavbarComponent } from '../shared/navbar';

@Component({
  selector: 'app-temporadas-colecciones-admin',
  templateUrl: './temporadas-colecciones-admin.html',
  styleUrl: './temporadas-colecciones-admin.scss',
  standalone: true,
  imports: [
    CommonModule,
    ReactiveFormsModule,
    MatButtonModule,
    MatCardModule,
    MatCheckboxModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatSelectModule,
    MatSnackBarModule,
    MatTableModule,
    MatTooltipModule,
    NavbarComponent,
  ],
})
export class TemporadasColeccionesAdminComponent implements OnInit {
  private fb = inject(FormBuilder);
  private servicio = inject(CatalogoService);
  private snackbar = inject(MatSnackBar);

  readonly temporadas = signal<Temporada[]>([]);
  readonly colecciones = signal<Coleccion[]>([]);

  readonly tempEditando = signal<Temporada | null>(null);
  readonly tempModo = signal<'nuevo' | 'editar' | null>(null);
  readonly colEditando = signal<Coleccion | null>(null);
  readonly colModo = signal<'nuevo' | 'editar' | null>(null);

  readonly cargando = signal(false);
  readonly errorTemp = signal<string | null>(null);
  readonly errorCol = signal<string | null>(null);

  readonly colTemp = ['nombre', 'inicio', 'fin', 'acciones'];
  readonly colCol = ['nombre', 'temporada', 'promocional', 'acciones'];

  temporadaForm = this.fb.group(
    {
      nombre: ['', [Validators.required, Validators.minLength(2)]],
      fecha_inicio: ['', Validators.required],
      fecha_fin: ['', Validators.required],
    },
    { validators: fechasValidas },
  );

  coleccionForm = this.fb.group({
    temporada_id: [null as number | null, Validators.required],
    nombre: ['', [Validators.required, Validators.minLength(2)]],
    descripcion: [''],
    es_promocional: [false],
  });

  ngOnInit(): void {
    this.recargar();
  }

  recargar(): void {
    this.servicio.listarTemporadas().subscribe({
      next: (datos) => this.temporadas.set(datos),
      error: (err) => this.errorTemp.set(this.mensajeError(err)),
    });
    this.servicio.listarColecciones().subscribe({
      next: (datos) => this.colecciones.set(datos),
      error: (err) => this.errorCol.set(this.mensajeError(err)),
    });
  }

  abrirNuevaTemporada(): void {
    this.tempEditando.set(null);
    this.tempModo.set('nuevo');
    this.errorTemp.set(null);
    this.temporadaForm.reset();
  }

  abrirEdicionTemporada(temporada: Temporada): void {
    this.tempEditando.set(temporada);
    this.tempModo.set('editar');
    this.errorTemp.set(null);
    this.temporadaForm.reset({
      nombre: temporada.nombre,
      fecha_inicio: temporada.fecha_inicio,
      fecha_fin: temporada.fecha_fin,
    });
  }

  cancelarTemporada(): void {
    this.tempModo.set(null);
    this.tempEditando.set(null);
    this.errorTemp.set(null);
  }

  guardarTemporada(): void {
    if (this.temporadaForm.invalid) {
      this.temporadaForm.markAllAsTouched();
      return;
    }
    this.cargando.set(true);
    this.errorTemp.set(null);
    const datos = {
      nombre: this.temporadaForm.value.nombre!.trim(),
      fecha_inicio: this.temporadaForm.value.fecha_inicio!,
      fecha_fin: this.temporadaForm.value.fecha_fin!,
    };
    const actual = this.tempEditando();
    const operacion = actual
      ? this.servicio.actualizarTemporada(actual.id_temporada, datos)
      : this.servicio.crearTemporada(datos);
    operacion.subscribe({
      next: () => {
        this.cargando.set(false);
        this.snackbar.open(
          actual ? 'Temporada actualizada correctamente' : 'Temporada creada correctamente',
          'Cerrar',
          { duration: 4000 },
        );
        this.cancelarTemporada();
        this.recargar();
      },
      error: (err) => {
        this.cargando.set(false);
        this.errorTemp.set(this.mensajeError(err));
      },
    });
  }

  eliminarTemporada(temporada: Temporada): void {
    if (!confirm(`¿Eliminar la temporada "${temporada.nombre}"?`)) return;
    this.cargando.set(true);
    this.errorTemp.set(null);
    this.servicio.eliminarTemporada(temporada.id_temporada).subscribe({
      next: () => {
        this.cargando.set(false);
        this.snackbar.open('Temporada eliminada correctamente', 'Cerrar', { duration: 4000 });
        this.recargar();
      },
      error: (err) => {
        this.cargando.set(false);
        this.errorTemp.set(this.mensajeError(err));
      },
    });
  }

  abrirNuevaColeccion(): void {
    this.colEditando.set(null);
    this.colModo.set('nuevo');
    this.errorCol.set(null);
    this.coleccionForm.reset({ temporada_id: null, es_promocional: false });
  }

  abrirEdicionColeccion(coleccion: Coleccion): void {
    this.colEditando.set(coleccion);
    this.colModo.set('editar');
    this.errorCol.set(null);
    this.coleccionForm.reset({
      temporada_id: coleccion.temporada_id,
      nombre: coleccion.nombre,
      descripcion: coleccion.descripcion ?? '',
      es_promocional: coleccion.es_promocional,
    });
  }

  cancelarColeccion(): void {
    this.colModo.set(null);
    this.colEditando.set(null);
    this.errorCol.set(null);
  }

  guardarColeccion(): void {
    if (this.coleccionForm.invalid) {
      this.coleccionForm.markAllAsTouched();
      return;
    }
    this.cargando.set(true);
    this.errorCol.set(null);
    const datos = {
      temporada_id: this.coleccionForm.value.temporada_id!,
      nombre: this.coleccionForm.value.nombre!.trim(),
      descripcion: this.coleccionForm.value.descripcion?.trim() || null,
      es_promocional: this.coleccionForm.value.es_promocional ?? false,
    };
    const actual = this.colEditando();
    const operacion = actual
      ? this.servicio.actualizarColeccion(actual.id_coleccion, datos)
      : this.servicio.crearColeccion(datos);
    operacion.subscribe({
      next: () => {
        this.cargando.set(false);
        this.snackbar.open(
          actual ? 'Colección actualizada correctamente' : 'Colección creada correctamente',
          'Cerrar',
          { duration: 4000 },
        );
        this.cancelarColeccion();
        this.recargar();
      },
      error: (err) => {
        this.cargando.set(false);
        this.errorCol.set(this.mensajeError(err));
      },
    });
  }

  eliminarColeccion(coleccion: Coleccion): void {
    if (!confirm(`¿Eliminar la colección "${coleccion.nombre}"?`)) return;
    this.cargando.set(true);
    this.errorCol.set(null);
    this.servicio.eliminarColeccion(coleccion.id_coleccion).subscribe({
      next: () => {
        this.cargando.set(false);
        this.snackbar.open('Colección eliminada correctamente', 'Cerrar', { duration: 4000 });
        this.recargar();
      },
      error: (err) => {
        this.cargando.set(false);
        this.errorCol.set(this.mensajeError(err));
      },
    });
  }

  nombreTemporada(id: number): string {
    return this.temporadas().find((t) => t.id_temporada === id)?.nombre ?? '—';
  }

  private mensajeError(err: unknown): string {
    const detail = (err as { error?: { detail?: unknown } })?.error?.detail;
    if (typeof detail === 'string') return detail;
    if (Array.isArray(detail)) return detail.map((e) => (e as { msg?: string }).msg).filter(Boolean).join('; ');
    return 'No se pudo completar la operación.';
  }
}

function fechasValidas(grupo: AbstractControl): { fechas: true } | null {
  const inicio = grupo.get('fecha_inicio')?.value;
  const fin = grupo.get('fecha_fin')?.value;
  if (inicio && fin && inicio >= fin) return { fechas: true };
  return null;
}