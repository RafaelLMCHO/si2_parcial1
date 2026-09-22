import { Routes } from '@angular/router';
import { LoginComponent } from './auth/login';
import { RegistroComponent } from './auth/registro';
import { DashboardComponent } from './dashboard/dashboard';
import { CatalogoComponent } from './catalogo/catalogo';
import { ProductoDetalleComponent } from './catalogo/producto-detalle';
import { ProntoComponent } from './pages/pronto';
import { PerfilComponent } from './perfil/perfil';
import { SucursalesComponent } from './sucursales/sucursales';
import { CatalogoAdminComponent } from './catalogo-admin/catalogo-admin';
import { UsuariosAdminComponent } from './usuarios-admin/usuarios-admin';
import { CarritoComponent } from './carrito/carrito';
import { MisReservasComponent } from './reservas/mis-reservas';
import { MisComprasComponent } from './compras/mis-compras';
import { PagoConfirmacionComponent } from './pago-confirmacion/pago-confirmacion';
import { PuntoVentaComponent } from './ventas/punto-venta';
import { GestionPagosComponent } from './pagos/gestion-pagos';
import { GestionInventarioComponent } from './inventario/gestion-inventario';
import { ProveedoresAdminComponent } from './proveedores-admin/proveedores-admin';
import { TemporadasColeccionesAdminComponent } from './temporadas-colecciones-admin/temporadas-colecciones-admin';
import { PrepararReservasComponent } from './encargado/reservas/preparar-reservas/preparar-reservas';
import { ReportesComponent } from './reportes/reportes';
import { BitacoraComponent } from './bitacora/bitacora';
import {
  adminGuard,
  authGuard,
  encargadoGuard,
  reportesGuard,
  reservasRoleGuard,
} from './core/auth.guard';

export const routes: Routes = [
  { path: '', pathMatch: 'full', redirectTo: 'dashboard' },
  { path: 'login', component: LoginComponent },
  { path: 'registro', component: RegistroComponent },
  {
    path: 'dashboard',
    component: DashboardComponent,
    canActivate: [authGuard],
  },
  {
    path: 'perfil',
    component: PerfilComponent,
    canActivate: [authGuard],
  },
  {
    path: 'catalogo',
    component: CatalogoComponent,
    canActivate: [authGuard],
  },
  {
    path: 'catalogo/:id',
    component: ProductoDetalleComponent,
    canActivate: [authGuard],
  },
  {
    path: 'carrito',
    component: CarritoComponent,
    canActivate: [authGuard],
  },
  {
    path: 'pago/confirmacion',
    component: PagoConfirmacionComponent,
    canActivate: [authGuard],
  },
  {
    path: 'gestion/productos',
    component: CatalogoAdminComponent,
    canActivate: [authGuard, adminGuard],
  },
  {
    path: 'gestion/usuarios',
    component: UsuariosAdminComponent,
    canActivate: [authGuard, adminGuard],
  },
  {
    path: 'gestion/proveedores',
    component: ProveedoresAdminComponent,
    canActivate: [authGuard, adminGuard],
  },
  {
    path: 'gestion/temporadas',
    component: TemporadasColeccionesAdminComponent,
    canActivate: [authGuard, adminGuard],
  },
  {
    path: 'gestion/pagos',
    component: GestionPagosComponent,
    canActivate: [authGuard],
  },
  {
    path: 'gestion/inventario',
    component: GestionInventarioComponent,
    canActivate: [authGuard],
  },
  {
    path: 'sucursales',
    component: SucursalesComponent,
    canActivate: [authGuard],
  },
  {
    path: 'reservas',
    component: MisReservasComponent,
    canActivate: [authGuard, reservasRoleGuard],
  },
  {
    path: 'compras',
    component: MisComprasComponent,
    canActivate: [authGuard],
  },
  {
    path: 'encargado/reservas/pendientes',
    component: PrepararReservasComponent,
    canActivate: [authGuard, encargadoGuard],
  },
  {
    path: 'ventas',
    component: PuntoVentaComponent,
    canActivate: [authGuard],
  },
  {
    path: 'reportes',
    component: ReportesComponent,
    canActivate: [authGuard, reportesGuard],
  },
  {
    path: 'gestion/bitacora',
    component: BitacoraComponent,
    canActivate: [authGuard, adminGuard],
  },
  { path: '**', redirectTo: 'dashboard' },
];
