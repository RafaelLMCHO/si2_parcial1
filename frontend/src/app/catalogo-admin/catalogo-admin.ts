import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, Validators } from '@angular/forms';
import { MatCardModule } from '@angular/material/card';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatSelectModule } from '@angular/material/select';
import { MatTableModule } from '@angular/material/table';
import { MatSnackBar, MatSnackBarModule } from '@angular/material/snack-bar';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatTooltipModule } from '@angular/material/tooltip';
import { forkJoin } from 'rxjs';

import { AuthService } from '../core/auth.service';
import { CatalogoService } from '../services/catalogo.service';
import { NavbarComponent } from '../shared/navbar';
import {
  Categoria,
  Coleccion,
  Color,
  Producto,
  Proveedor,
  Talla,
  Temporada,
} from '../models/catalogo';

interface VariantePendiente {
  color_id: number;
  talla_id: number;
}

@Component({
  selector: 'app-catalogo-admin',
  templateUrl: './catalogo-admin.html',
  styleUrl: './catalogo-admin.scss',
  standalone: true,
  imports: [
    CommonModule,
    ReactiveFormsModule,
    MatCardModule,
    MatInputModule,
    MatButtonModule,
    MatIconModule,
    MatFormFieldModule,
    MatSelectModule,
    MatTableModule,
    MatSnackBarModule,
    MatProgressSpinnerModule,
    MatTooltipModule,
    NavbarComponent,
  ],
})
export class CatalogoAdminComponent implements OnInit {
  private fb = inject(FormBuilder);
  private autenticacion = inject(AuthService);
  private servicio = inject(CatalogoService);
  private snackbar = inject(MatSnackBar);

  readonly esGestor = computed(() => {
    const rol = this.autenticacion.usuario()?.rol;
    return rol === 'admin';
  });

  categorias = signal<Categoria[]>([]);
  colores = signal<Color[]>([]);
  tallas = signal<Talla[]>([]);
  proveedores = signal<Proveedor[]>([]);
  temporadas = signal<Temporada[]>([]);
  colecciones = signal<Coleccion[]>([]);
  productos = signal<Producto[]>([]);
  cargando = signal(false);
  error = signal<string | null>(null);
  editando = signal<Producto | null>(null);
  modoFormulario = signal<'nuevo' | 'editar' | null>(null);
  variantesPendientes = signal<VariantePendiente[]>([]);
  confirmandoBaja = signal<number | null>(null);
  subiendoImagen = signal(false);
  archivoImagen = signal<File | null>(null);
  imagenLocalUrl = signal<string | null>(null);

  readonly columnas = ['nombre', 'precio', 'categoria', 'estado', 'acciones'];

  previaImagen = computed(() => {
    const local = this.imagenLocalUrl();
    if (local) return local;
    const edit = this.editando();
    return edit?.imagen_url || this.form.value.imagen_url || 'assets/placeholder.svg';
  });

  form = this.fb.group({
    nombre: ['', [Validators.required, Validators.minLength(2)]],
    descripcion: [''],
    prompt_vestidor: [''],
    precio: [null as number | null, [Validators.required, Validators.min(0.01)]],
    categoria_id: [null as number | null, Validators.required],
    temporada_id: [null as number | null, Validators.required],
    coleccion_id: [null as number | null],
    proveedor_id: [null as number | null, Validators.required],
    imagen_url: [''],
    modelo_3d_url: [''],
  });

  varianteForm = this.fb.group({
    color_id: [null as number | null, Validators.required],
    talla_id: [null as number | null, Validators.required],
  });

  ngOnInit(): void {
    this.recargar();
    this.servicio.listarCategorias().subscribe({ next: (d) => this.categorias.set(d) });
    this.servicio.listarColores().subscribe({ next: (d) => this.colores.set(d) });
    this.servicio.listarTallas().subscribe({ next: (d) => this.tallas.set(d) });
    this.servicio.listarProveedores().subscribe({ next: (d) => this.proveedores.set(d) });
    this.servicio.listarTemporadas().subscribe({ next: (d) => this.temporadas.set(d) });
    this.servicio.listarColecciones().subscribe({ next: (d) => this.colecciones.set(d) });
  }

  recargar(): void {
    this.servicio.listarTodos().subscribe({
      next: (lista) => this.productos.set(lista),
      error: () => this.servicio.listarProductos().subscribe((l) => this.productos.set(l)),
    });
  }

  abrirNuevo(): void {
    this.error.set(null);
    this.confirmandoBaja.set(null);
    this.editando.set(null);
    this.modoFormulario.set('nuevo');
    this.variantesPendientes.set([]);
    this.archivoImagen.set(null);
    this.imagenLocalUrl.set(null);
    this.form.reset();
    this.varianteForm.reset();
  }

  abrirEdicion(p: Producto): void {
    this.error.set(null);
    this.confirmandoBaja.set(null);
    this.editando.set(p);
    this.modoFormulario.set('editar');
    this.variantesPendientes.set([]);
    this.archivoImagen.set(null);
    this.imagenLocalUrl.set(null);
    this.form.patchValue({
      nombre: p.nombre,
      descripcion: p.descripcion ?? '',
      prompt_vestidor: p.prompt_vestidor ?? '',
      precio: Number(p.precio),
      categoria_id: p.categoria_id,
      temporada_id: p.temporada_id,
      coleccion_id: p.coleccion_id ?? null,
      proveedor_id: p.proveedor_id,
      imagen_url: p.imagen_url ?? '',
      modelo_3d_url: p.modelo_3d_url ?? '',
    });
    for (const v of ['categoria_id', 'temporada_id', 'proveedor_id', 'precio']) {
      this.form.get(v)?.markAsTouched();
    }
    this.varianteForm.reset();
  }

  cancelar(): void {
    this.editando.set(null);
    this.modoFormulario.set(null);
    this.variantesPendientes.set([]);
    this.error.set(null);
    this.confirmandoBaja.set(null);
    this.archivoImagen.set(null);
    this.imagenLocalUrl.set(null);
  }

  onArchivoSeleccionado(event: Event): void {
    const input = event.target as HTMLInputElement;
    const archivo = input.files?.[0] ?? null;
    input.value = '';
    if (!archivo) return;

    const permitidos = ['image/jpeg', 'image/png', 'image/webp'];
    if (!permitidos.includes(archivo.type)) {
      this.snackbar.open('Formato no permitido. Usa JPG, PNG o WebP.', 'Cerrar', { duration: 5000 });
      return;
    }
    if (archivo.size > 10 * 1024 * 1024) {
      this.snackbar.open('La imagen supera el límite de 10 MB.', 'Cerrar', { duration: 5000 });
      return;
    }

    this.archivoImagen.set(archivo);
    const lector = new FileReader();
    lector.onloadend = () => this.imagenLocalUrl.set(lector.result as string);
    lector.readAsDataURL(archivo);
  }

  subirImagen(): void {
    const editando = this.editando();
    const archivo = this.archivoImagen();
    if (!editando || !archivo || this.subiendoImagen()) return;

    this.subiendoImagen.set(true);
    this.servicio.subirImagen(editando.id_producto, archivo).subscribe({
      next: (p) => {
        this.subiendoImagen.set(false);
        this.form.patchValue({ imagen_url: p.imagen_url ?? '' });
        this.archivoImagen.set(null);
        this.imagenLocalUrl.set(null);
        this.snackbar.open('Imagen del producto actualizada correctamente', 'Cerrar', { duration: 4000 });
      },
      error: (err) => {
        this.subiendoImagen.set(false);
        const detail = err?.error?.detail?.toString() ?? 'Error al subir la imagen';
        this.snackbar.open(detail, 'Cerrar', { duration: 5000 });
      },
    });
  }

  previoError(event: Event): void {
    ((event.target as HTMLImageElement)).src = 'assets/placeholder.svg';
  }

  onGuardar(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }
    if (!this.editando() && this.variantesPendientes().length === 0) {
      this.error.set('Agrega al menos una variante de color y talla antes de guardar.');
      return;
    }
    this.cargando.set(true);
    this.error.set(null);

    const editando = this.editando();
    const datos = {
      nombre: this.form.value.nombre!.trim(),
      descripcion: this.form.value.descripcion?.trim() || null,
      prompt_vestidor: this.form.value.prompt_vestidor?.trim() || null,
      precio: this.form.value.precio!,
      categoria_id: this.form.value.categoria_id!,
      temporada_id: this.form.value.temporada_id!,
      coleccion_id: this.form.value.coleccion_id ?? null,
      proveedor_id: this.form.value.proveedor_id!,
      imagen_url: this.form.value.imagen_url?.trim() || null,
      modelo_3d_url: this.form.value.modelo_3d_url?.trim() || null,
    };

    if (editando) {
      this.guardarProducto(this.servicio.actualizarProducto(editando.id_producto, datos), true);
      return;
    }

    this.servicio.crearProducto(datos).subscribe({
      next: (producto) => {
        const pendientes = this.variantesPendientes();
        if (!pendientes.length) {
          this.finalizarGuardado(producto, false);
          return;
        }
        forkJoin(
          pendientes.map((v) => this.servicio.crearVariante({
            producto_id: producto.id_producto,
            ...v,
            precio_extra: 0,
          })),
        ).subscribe({
          next: () => this.finalizarGuardado(producto, false),
          error: (err) => {
            this.cargando.set(false);
            this.error.set(`El producto fue creado, pero no se pudieron guardar sus variantes: ${this.mensajeError(err)}`);
          },
        });
      },
      error: (err) => {
        this.cargando.set(false);
        this.error.set(this.mensajeError(err));
      },
    });
  }

  agregarVariante(): void {
    if (this.varianteForm.invalid) {
      this.varianteForm.markAllAsTouched();
      return;
    }
    const datos = {
      color_id: this.varianteForm.value.color_id!,
      talla_id: this.varianteForm.value.talla_id!,
    };
    const p = this.editando();
    if (!p) {
      const existe = this.variantesPendientes().some(
        (v) => v.color_id === datos.color_id && v.talla_id === datos.talla_id,
      );
      if (existe) {
        this.error.set('La combinación de color y talla ya fue agregada.');
        return;
      }
      this.variantesPendientes.update((variantes) => [...variantes, datos]);
      this.varianteForm.reset();
      return;
    }
    this.cargando.set(true);
    this.error.set(null);

    this.servicio
      .crearVariante({
        producto_id: p.id_producto,
        ...datos,
        precio_extra: 0,
      })
      .subscribe({
        next: () => {
          this.cargando.set(false);
          this.varianteForm.controls.color_id.reset();
          this.varianteForm.controls.talla_id.reset();
          this.servicio.verProducto(p.id_producto).subscribe((np) => this.editando.set(np));
        },
        error: (err) => {
          this.cargando.set(false);
          this.error.set(this.mensajeError(err));
        },
      });
  }

  quitarVariante(id: number): void {
    this.cargando.set(true);
    this.servicio.eliminarVariante(id).subscribe({
      next: () => {
        this.cargando.set(false);
        const p = this.editando();
        if (p) this.servicio.verProducto(p.id_producto).subscribe((np) => this.editando.set(np));
      },
      error: (err) => {
        this.cargando.set(false);
        this.error.set(this.mensajeError(err));
      },
    });
  }

  quitarVariantePendiente(indice: number): void {
    this.variantesPendientes.update((variantes) => variantes.filter((_, i) => i !== indice));
  }

  desactivar(p: Producto): void {
    this.error.set(null);
    this.confirmandoBaja.set(null);
    this.servicio.desactivarProducto(p.id_producto, false).subscribe({
      next: () => {
        this.snackbar.open('Producto desactivado correctamente', 'Cerrar', { duration: 4000 });
        this.recargar();
      },
      error: (err) => {
        const mensaje = this.mensajeError(err);
        this.error.set(mensaje);
        this.confirmandoBaja.set(p.id_producto);
      },
    });
  }

  confirmarBaja(p: Producto): void {
    this.cargando.set(true);
    this.servicio.desactivarProducto(p.id_producto, true).subscribe({
      next: () => {
        this.cargando.set(false);
        this.confirmandoBaja.set(null);
        this.error.set(null);
        this.snackbar.open('Producto desactivado correctamente', 'Cerrar', { duration: 4000 });
        this.recargar();
      },
      error: (err) => {
        this.cargando.set(false);
        this.error.set(this.mensajeError(err));
      },
    });
  }

  productoEnConfirmacion(): Producto | null {
    const id = this.confirmandoBaja();
    if (id === null) return null;
    return this.productos().find((p) => p.id_producto === id) ?? null;
  }

  nombreCategoria(id: number | null | undefined): string {
    if (!id) return '—';
    return this.categorias().find((c) => c.id_categoria === id)?.nombre ?? `#${id}`;
  }

  nombreColor(id: number | null | undefined): string {
    if (!id) return '—';
    return this.colores().find((c) => c.id_color === id)?.nombre ?? `#${id}`;
  }

  nombreTalla(id: number | null | undefined): string {
    if (!id) return '—';
    return this.tallas().find((t) => t.id_talla === id)?.nombre ?? `#${id}`;
  }

  private guardarProducto(operacion: ReturnType<CatalogoService['actualizarProducto']>, esEdicion: boolean): void {
    operacion.subscribe({
      next: (producto) => this.finalizarGuardado(producto, esEdicion),
      error: (err) => {
        this.cargando.set(false);
        this.error.set(this.mensajeError(err));
      },
    });
  }

  private finalizarGuardado(producto: Producto, esEdicion: boolean): void {
    this.cargando.set(false);
    this.variantesPendientes.set([]);
    this.modoFormulario.set('editar');
    this.snackbar.open(
      esEdicion ? 'Producto actualizado correctamente' : 'Producto y variantes creados correctamente',
      'Cerrar',
      { duration: 4000 },
    );
    this.servicio.verProducto(producto.id_producto).subscribe((p) => this.editando.set(p));
    this.recargar();
  }

  private mensajeError(err: unknown): string {
    const detail = (err as { error?: { detail?: unknown } })?.error?.detail;
    if (typeof detail === 'string') return detail;
    if (Array.isArray(detail) && detail.length) {
      return detail
        .map((e) => (e as { msg?: string })?.msg)
        .filter(Boolean)
        .join('; ');
    }
    return 'No se pudo completar la operación.';
  }
}
