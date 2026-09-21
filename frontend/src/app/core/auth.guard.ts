import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from './auth.service';

export const authGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  if (auth.isAuthenticated() || auth.getToken()) {
    return true;
  }
  return router.createUrlTree(['/login']);
};

/** Limita las pantallas de administración a usuarios con rol administrador. */
export const adminGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  return auth.usuario()?.rol === 'admin'
    ? true
    : router.createUrlTree(['/dashboard']);
};

/** Preparación de reservas (CU-13): administradores y encargados. */
export const encargadoGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  const rol = auth.usuario()?.rol;
  return rol === 'admin' || rol === 'encargado'
    ? true
    : router.createUrlTree(['/dashboard']);
};

/** Reportes/dashboards (CU-16): solo administradores y encargados. */
export const reportesGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  const rol = auth.usuario()?.rol;
  return rol === 'admin' || rol === 'encargado'
    ? true
    : router.createUrlTree(['/dashboard']);
};

/**
 * En la ruta /reservas, redirige al encargado a su panel propio.
 * Clientes y admins acceden normalmente.
 */
export const reservasRoleGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  if (auth.usuario()?.rol === 'encargado') {
    return router.createUrlTree(['/encargado/reservas/pendientes']);
  }
  return true;
};
