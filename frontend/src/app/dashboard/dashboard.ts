import { Component, computed, inject } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { CommonModule } from '@angular/common';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';

import { AuthService } from '../core/auth.service';
import { SucursalService } from '../services/sucursal.service';
import { NavbarComponent } from '../shared/navbar';

interface RolInfo {
  icon: string;
  titulo: string;
  descripcion: string;
}

interface QuickItem {
  ruta: string;
  icon: string;
  titulo: string;
  desc: string;
  color: string;
}

@Component({
  selector: 'app-dashboard',
  templateUrl: './dashboard.html',
  styleUrl: './dashboard.scss',
  standalone: true,
  imports: [
    CommonModule,
    RouterLink,
    MatCardModule,
    MatButtonModule,
    MatIconModule,
    NavbarComponent,
  ],
})
export class DashboardComponent {
  private auth = inject(AuthService);
  private sucursales = inject(SucursalService);
  private router = inject(Router);

  readonly usuario = this.auth.usuario;

  readonly rolInfo: Record<string, RolInfo> = {
    admin: {
      icon: 'admin_panel_settings',
      titulo: 'Administrador General',
      descripcion: 'Acceso total: catálogo, inventario, reservas, ventas y reportes de la plataforma.',
    },
    encargado: {
      icon: 'assignment_ind',
      titulo: 'Encargado de Sucursal',
      descripcion: 'Gestiona inventario, reservas y ventas de tu sucursal.',
    },
    cajero: {
      icon: 'point_of_sale',
      titulo: 'Cajero',
      descripcion: 'Registra ventas presenciales en tu punto de venta.',
    },
    cliente: {
      icon: 'shopping_bag',
      titulo: 'Cliente',
      descripcion: 'Explora el catálogo, realiza pedidos y reserva tus prendas favoritas.',
    },
  };

  readonly info = computed(
    () => this.rolInfo[this.usuario()?.rol ?? 'cliente'] ?? this.rolInfo['cliente'],
  );

  readonly rolLabel = computed(() => 'Rol: ' + this.info().titulo);
  readonly sucursalNombre = computed(() =>
    this.sucursales.nombreDe(this.usuario()?.sucursal_id ?? null),
  );

  private readonly quickBase: QuickItem[] = [
    {
      ruta: '/catalogo',
      icon: 'storefront',
      titulo: 'Catálogo',
      desc: 'Explora la colección disponible en tienda.',
      color: 'q-blue',
    },
    {
      ruta: '/sucursales',
      icon: 'store',
      titulo: 'Sucursales',
      desc: 'Consulta ubicaciones, horarios y disponibilidad.',
      color: 'q-violet',
    },
    {
      ruta: '/reservas',
      icon: 'inventory_2',
      titulo: 'Reservas',
      desc: 'Gestiona tus reservas y el estado de cada prenda.',
      color: 'q-green',
    },
    {
      ruta: '/ventas',
      icon: 'point_of_sale',
      titulo: 'Ventas / POS',
      desc: 'Registra ventas en punto de venta y en línea.',
      color: 'q-amber',
    },
  ];

  readonly quick = computed(() => {
    const accesos = [...this.quickBase];
    if (this.usuario()?.rol === 'admin' || this.usuario()?.rol === 'encargado') {
      accesos.unshift({
        ruta: '/reportes',
        icon: 'insights',
        titulo: 'Reportes y dashboards',
        desc: 'KPIs de ventas, inventario, reservas y tendencias por temporada.',
        color: 'q-amber',
      });
    }
    if (this.usuario()?.rol === 'admin') {
      accesos.unshift({
        ruta: '/gestion/productos',
        icon: 'inventory',
        titulo: 'Gestión de productos',
        desc: 'Crea, edita y desactiva productos y sus variantes.',
        color: 'q-blue',
      });
    }
    return accesos;
  });

  ir(ruta: string): void {
    this.router.navigate([ruta]);
  }
}
