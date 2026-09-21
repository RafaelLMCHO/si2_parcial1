import { Component, computed, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatMenuModule } from '@angular/material/menu';
import { MatDividerModule } from '@angular/material/divider';
import { MatTooltipModule } from '@angular/material/tooltip';

import { AuthService } from '../core/auth.service';
import { SucursalService } from '../services/sucursal.service';

export interface NavItem {
  ruta: string;
  label: string;
  icon: string;
  roles?: string[];
}

export const NAV_ITEMS: NavItem[] = [
  { ruta: '/dashboard', label: 'Dashboard', icon: 'grid_view' },
  { ruta: '/catalogo', label: 'Catálogo', icon: 'storefront' },
  {
    ruta: '/carrito',
    label: 'Carrito de reservas',
    icon: 'shopping_cart',
    roles: ['cliente', 'admin'],
  },
{
    ruta: '/gestion/productos',
    label: 'Gestión de productos',
    icon: 'inventory',
    roles: ['admin'],
  },
  {
    ruta: '/gestion/usuarios',
    label: 'Gestión de usuarios',
    icon: 'manage_accounts',
    roles: ['admin'],
  },
  { ruta: '/sucursales', label: 'Sucursales', icon: 'store' },
  {
    ruta: '/reservas',
    label: 'Reservas',
    icon: 'calendar_month',
    roles: ['cliente', 'admin'],
  },
  {
    ruta: '/encargado/reservas/pendientes',
    label: 'Preparar Reservas',
    icon: 'inventory_2',
    roles: ['encargado'],
  },
  { ruta: '/ventas', label: 'Ventas / POS', icon: 'point_of_sale' },
  {
    ruta: '/reportes',
    label: 'Reportes',
    icon: 'insights',
    roles: ['admin', 'encargado'],
  },
];

const ROL_LABELS: Record<string, string> = {
  admin: 'Administrador General',
  encargado: 'Encargado de Sucursal',
  cajero: 'Cajero',
  cliente: 'Cliente',
};

@Component({
  selector: 'app-navbar',
  templateUrl: './navbar.html',
  styleUrl: './navbar.scss',
  standalone: true,
  imports: [
    CommonModule,
    RouterLink,
    RouterLinkActive,
    MatButtonModule,
    MatIconModule,
    MatMenuModule,
    MatDividerModule,
    MatTooltipModule,
  ],
})
export class NavbarComponent {
  protected auth = inject(AuthService);
  private sucursales = inject(SucursalService);

  readonly usuario = this.auth.usuario;
  readonly navItems = computed(() => {
    const rol = this.usuario()?.rol;
    return NAV_ITEMS.filter((item) => !item.roles || item.roles.includes(rol ?? ''));
  });

  readonly rolLabel = computed(
    () => ROL_LABELS[this.usuario()?.rol ?? ''] ?? this.usuario()?.rol ?? 'Usuario',
  );

  readonly sucursalNombre = computed(() =>
    this.sucursales.nombreDe(this.usuario()?.sucursal_id ?? null),
  );

  readonly iniciales = computed(() => {
    const partes = (this.usuario()?.nombre ?? '').trim().split(/\s+/).filter(Boolean);
    if (partes.length === 0) return 'FS';
    const iniciales = partes
      .slice(0, 2)
      .map((p) => p.charAt(0).toUpperCase())
      .join('');
    return iniciales || 'FS';
  });

  onLogout(): void {
    this.auth.logout();
  }
}
