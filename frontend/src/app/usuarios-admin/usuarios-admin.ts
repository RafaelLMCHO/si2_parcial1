import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';
import { MatSnackBar, MatSnackBarModule } from '@angular/material/snack-bar';
import { MatTableModule } from '@angular/material/table';
import { MatTooltipModule } from '@angular/material/tooltip';

import { AuthService } from '../core/auth.service';
import { Usuario } from '../models/usuario';
import { SucursalService } from '../services/sucursal.service';
import { UsuariosService } from '../services/usuarios.service';
import { NavbarComponent } from '../shared/navbar';

@Component({
  selector: 'app-usuarios-admin',
  standalone: true,
  templateUrl: './usuarios-admin.html',
  styleUrl: './usuarios-admin.scss',
  imports: [CommonModule, ReactiveFormsModule, MatButtonModule, MatCardModule, MatFormFieldModule, MatIconModule, MatInputModule, MatSelectModule, MatSnackBarModule, MatTableModule, MatTooltipModule, NavbarComponent],
})
export class UsuariosAdminComponent implements OnInit {
  private fb = inject(FormBuilder);
  private servicio = inject(UsuariosService);
  private sucursalServicio = inject(SucursalService);
  private auth = inject(AuthService);
  private snackbar = inject(MatSnackBar);

  readonly usuarios = signal<Usuario[]>([]);
  readonly sucursales = this.sucursalServicio.sucursales;
  readonly editando = signal<Usuario | null>(null);
  readonly modoFormulario = signal<'nuevo' | 'editar' | null>(null);
  readonly cargando = signal(false);
  readonly error = signal<string | null>(null);
  readonly confirmandoBaja = signal<Usuario | null>(null);
  readonly columnas = ['nombre', 'email', 'rol', 'sucursal', 'estado', 'acciones'];
  readonly roles = ['admin', 'encargado', 'cajero', 'cliente'];
  readonly requiereSucursal = signal(false);

  form = this.fb.group({
    nombre: ['', [Validators.required, Validators.minLength(2)]],
    email: ['', [Validators.required, Validators.email]],
    telefono: [''],
    rol: ['cliente', Validators.required],
    sucursal_id: [null as number | null],
    contrasena: [''],
  });

  ngOnInit(): void {
    this.form.get('rol')!.valueChanges.subscribe((rol) =>
      this.requiereSucursal.set(['encargado', 'cajero'].includes(rol ?? '')),
    );
    this.recargar();
    this.sucursalServicio.cargar();
  }

  recargar(): void {
    this.servicio.listar().subscribe({
      next: (usuarios) => this.usuarios.set(usuarios),
      error: (err) => this.error.set(this.mensajeError(err)),
    });
  }

  abrirNuevo(): void {
    this.editando.set(null);
    this.modoFormulario.set('nuevo');
    this.error.set(null);
    this.form.reset({ rol: 'cliente', sucursal_id: null });
    this.form.controls.contrasena.setValidators([Validators.required, Validators.minLength(6)]);
    this.form.controls.contrasena.updateValueAndValidity();
  }

  abrirEdicion(usuario: Usuario): void {
    this.editando.set(usuario);
    this.modoFormulario.set('editar');
    this.error.set(null);
    this.form.reset({
      nombre: usuario.nombre,
      email: usuario.email,
      telefono: usuario.telefono ?? '',
      rol: usuario.rol,
      sucursal_id: usuario.sucursal_id ?? null,
      contrasena: '',
    });
    this.form.controls.contrasena.clearValidators();
    this.form.controls.contrasena.updateValueAndValidity();
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
    if (this.requiereSucursal() && !this.form.value.sucursal_id) {
      this.error.set('Selecciona una sucursal para el encargado o cajero.');
      return;
    }
    this.cargando.set(true);
    this.error.set(null);
    const datos = {
      nombre: this.form.value.nombre!.trim(),
      email: this.form.value.email!.trim(),
      telefono: this.form.value.telefono?.trim() || null,
      rol: this.form.value.rol!,
      sucursal_id: this.form.value.sucursal_id ?? null,
      contrasena: this.form.value.contrasena || undefined,
    };
    const actual = this.editando();
    const operacion = actual
      ? this.servicio.actualizar(actual.id_usuario, datos)
      : this.servicio.crear({ ...datos, contrasena: datos.contrasena! });
    operacion.subscribe({
      next: () => {
        this.cargando.set(false);
        this.snackbar.open(actual ? 'Usuario actualizado correctamente' : 'Usuario creado correctamente', 'Cerrar', { duration: 4000 });
        this.cancelar();
        this.recargar();
      },
      error: (err) => {
        this.cargando.set(false);
        this.error.set(this.mensajeError(err));
      },
    });
  }

  solicitarDesactivacion(usuario: Usuario): void {
    if (usuario.id_usuario === this.auth.usuario()?.id_usuario) {
      this.error.set('No puede desactivar su propia cuenta.');
      return;
    }
    this.error.set(null);
    this.servicio.actualizar(usuario.id_usuario, { activo: false }).subscribe({
      next: () => this.bajaExitosa(),
      error: (err) => {
        this.error.set(this.mensajeError(err));
        if ((err as { status?: number }).status === 409) this.confirmandoBaja.set(usuario);
      },
    });
  }

  confirmarDesactivacion(): void {
    const usuario = this.confirmandoBaja();
    if (!usuario) return;
    this.cargando.set(true);
    this.servicio.actualizar(usuario.id_usuario, { activo: false }, true).subscribe({
      next: () => {
        this.cargando.set(false);
        this.confirmandoBaja.set(null);
        this.bajaExitosa();
      },
      error: (err) => {
        this.cargando.set(false);
        this.error.set(this.mensajeError(err));
      },
    });
  }

  reactivar(usuario: Usuario): void {
    this.error.set(null);
    this.servicio.actualizar(usuario.id_usuario, { activo: true }).subscribe({
      next: () => {
        this.snackbar.open('Usuario activado correctamente', 'Cerrar', { duration: 4000 });
        this.recargar();
      },
      error: (err) => this.error.set(this.mensajeError(err)),
    });
  }

  nombreSucursal(id: number | null | undefined): string {
    return this.sucursalServicio.nombreDe(id);
  }

  private bajaExitosa(): void {
    this.confirmandoBaja.set(null);
    this.snackbar.open('Usuario desactivado correctamente', 'Cerrar', { duration: 4000 });
    this.recargar();
  }

  private mensajeError(err: unknown): string {
    const detail = (err as { error?: { detail?: unknown } })?.error?.detail;
    if (typeof detail === 'string') return detail;
    if (Array.isArray(detail)) return detail.map((e) => (e as { msg?: string }).msg).filter(Boolean).join('; ');
    return 'No se pudo completar la operación.';
  }
}
