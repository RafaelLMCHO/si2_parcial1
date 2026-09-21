import { Component, OnInit, inject, signal } from '@angular/core';
import { ReactiveFormsModule, FormControl } from '@angular/forms';
import { Router } from '@angular/router';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { CurrencyPipe, CommonModule } from '@angular/common';
import { CatalogoService } from '../services/catalogo.service';
import { IaService } from '../services/ia.service';
import { Categoria, Producto } from '../models/catalogo';
import { NavbarComponent } from '../shared/navbar';

@Component({
  selector: 'app-catalogo',
  templateUrl: './catalogo.html',
  styleUrl: './catalogo.scss',
  standalone: true,
  imports: [
    CommonModule,
    ReactiveFormsModule,
    CurrencyPipe,
    MatCardModule,
    MatButtonModule,
    MatIconModule,
    MatFormFieldModule,
    MatInputModule,
    MatSelectModule,
    MatProgressSpinnerModule,
    NavbarComponent,
  ],
})
export class CatalogoComponent implements OnInit {
  private catalogo = inject(CatalogoService);
  private ia = inject(IaService);
  private router = inject(Router);

  readonly categorias = signal<Categoria[]>([]);
  readonly productos = signal<Producto[]>([]);
  readonly recomendados = signal<Producto[]>([]);
  readonly cargandoRecomendados = signal(false);
  readonly cargando = signal(true);
  readonly error = signal<string | null>(null);

  categoria = new FormControl<number | null>(null);
  busqueda = new FormControl<string>('');

  ngOnInit(): void {
    this.cargarCategorias();
    this.cargarRecomendados();
    this.cargarProductos();
  }

  cargarCategorias(): void {
    this.catalogo.listarCategorias().subscribe({
      next: (c) => this.categorias.set(c),
      error: () => {
        /* categorías opcionales */
      },
    });
  }

  cargarRecomendados(): void {
    this.cargandoRecomendados.set(true);
    this.ia.recomendar(6).subscribe({
      next: (p) => {
        this.recomendados.set(p);
        this.cargandoRecomendados.set(false);
      },
      error: () => {
        // La sección de recomendados es opcional: no bloquea el catálogo.
        this.cargandoRecomendados.set(false);
      },
    });
  }

  cargarProductos(): void {
    this.cargando.set(true);
    this.error.set(null);
    this.catalogo
      .listarProductos({
        categoria_id: this.categoria.value,
        q: this.busqueda.value || null,
      })
      .subscribe({
        next: (p) => {
          this.productos.set(p);
          this.cargando.set(false);
        },
        error: (err) => {
          this.cargando.set(false);
          this.error.set('No se pudo cargar el catálogo.');
          console.error(err);
        },
      });
  }

  onFiltroCategoria(): void {
    this.cargarProductos();
  }

  onBuscar(): void {
    this.cargarProductos();
  }

  verProducto(id: number): void {
    this.router.navigate(['/catalogo', id]);
  }

  onImagenError(event: Event): void {
    const img = event.target as HTMLImageElement;
    img.src = 'assets/placeholder.svg';
  }
}
