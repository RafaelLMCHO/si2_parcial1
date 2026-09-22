import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatSnackBar, MatSnackBarModule } from '@angular/material/snack-bar';
import { MatTableModule } from '@angular/material/table';
import { MatTooltipModule } from '@angular/material/tooltip';

import { Proveedor } from '../models/catalogo';
import { CatalogoService } from '../services/catalogo.service';
import { NavbarComponent } from '../shared/navbar';

@Component({
  selector: 'app-proveedores-admin',
  templateUrl: './proveedores-admin.html',
  styleUrl: './proveedores-admin.scss',
  standalone: true,
  imports: [
    CommonModule,
    ReactiveFormsModule,
    MatButtonModule,
    MatCardModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatSnackBarModule,
    MatTableModule,
    MatTooltipModule,
    NavbarComponent,
  ],
})
export class ProveedoresAdminComponent implements OnInit {
  private fb = inject(FormBuilder);
  private servicio = inject(CatalogoService);
  private snackbar = inject(MatSnackBar);

  readonly proveedores = signal<Proveedor[]>([]);
  readonly editando = signal<Proveedor | null>(null);
  readonly modoFormulario = signal<'nuevo' | 'editar' | null>(null);
  readonly cargando = signal(false);
  readonly error = signal<string | null>(null);
  readonly columnas = ['nombre', 'contacto', 'telefono', 'email', 'direccion', 'acciones'];

  form = this.fb.group({
    nombre: ['', [Validators.required, Validators.minLength(2)]],
    contacto: [''],
    telefono: [''],
    email: ['', [Validators.email]],
    direccion: [''],
  });

  ngOnInit(): void {
    this.recargar();
  }

  recargar(): void {
    this.servicio.listarProveedores().subscribe({
      next: (datos) => this.proveedores.set(datos),
      error: (err) => this.error.set(this.mensajeError(err)),
    });
  }

  abrirNuevo(): void {
    this.editando.set(null);
    this.modoFormulario.set('nuevo');
    this.error.set(null);
    this.form.reset();
  }

  abrirEdicion(proveedor: Proveedor): void {
    this.editando.set(proveedor);
    this.modoFormulario.set('editar');
    this.error.set(null);
    this.form.reset({
      nombre: proveedor.nombre,
      contacto: proveedor.contacto ?? '',
      telefono: proveedor.telefono ?? '',
      email: proveedor.email ?? '',
      direccion: proveedor.direccion ?? '',
    });
  }

  cancelar(): void {
    this.modoFormulario.set(null);
    this.editando.set(null);
    this.error.set(null);
  }

  guardar(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }
    this.cargando.set(true);
    this.error.set(null);
    const datos = {
      nombre: this.form.value.nombre!.trim(),
      contacto: this.form.value.contacto?.trim() || null,
      telefono: this.form.value.telefono?.trim() || null,
      email: this.form.value.email?.trim() || null,
      direccion: this.form.value.direccion?.trim() || null,
    };
    const actual = this.editando();
    const operacion = actual
      ? this.servicio.actualizarProveedor(actual.id_proveedor, datos)
      : this.servicio.crearProveedor(datos);
    operacion.subscribe({
      next: () => {
        this.cargando.set(false);
        this.snackbar.open(
          actual ? 'Proveedor actualizado correctamente' : 'Proveedor creado correctamente',
          'Cerrar',
          { duration: 4000 },
        );
        this.cancelar();
        this.recargar();
      },
      error: (err) => {
        this.cargando.set(false);
        this.error.set(this.mensajeError(err));
      },
    });
  }

  eliminar(proveedor: Proveedor): void {
    if (!confirm(`¿Desactivar el proveedor "${proveedor.nombre}"?`)) return;
    this.cargando.set(true);
    this.error.set(null);
    this.servicio.eliminarProveedor(proveedor.id_proveedor).subscribe({
      next: () => {
        this.cargando.set(false);
        this.snackbar.open('Proveedor desactivado correctamente', 'Cerrar', { duration: 4000 });
        this.recargar();
      },
      error: (err) => {
        this.cargando.set(false);
        this.error.set(this.mensajeError(err));
      },
    });
  }

  private mensajeError(err: unknown): string {
    const detail = (err as { error?: { detail?: unknown } })?.error?.detail;
    if (typeof detail === 'string') return detail;
    if (Array.isArray(detail)) return detail.map((e) => (e as { msg?: string }).msg).filter(Boolean).join('; ');
    return 'No se pudo completar la operación.';
  }
}