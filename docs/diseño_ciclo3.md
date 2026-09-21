# Diseño del Ciclo #3 — FashionStore

Documento de diseño de los casos de uso del CICLO #3 implementados uno a uno.
Cada CU incluye: ficha, clases (INTERFAZ / CONTROL / ENTIDAD), endpoints, datos,
UI (web y móvil) y criterios de aceptación.

| CU  | Nombre                              | Plataforma |
|-----|-------------------------------------|------------|
| CU-17 | Recibir recomendaciones de IA     | Web + Móvil |
| CU-16 | Generar reportes y dashboards     | Web + Móvil |
| CU-07 | Utilizar vestidor virtual (RA)    | Web + Móvil (pendiente) |

---

## CU-17 — Recibir recomendaciones de IA

- **Actor:** Cliente (autenticado).
- **Plataforma:** Web (Angular) y Móvil (Flutter).
- **Requerimiento funcional:** RF25.
- **Descripción:** El cliente abre la sección "Recomendados para ti" y el sistema
  sugiere prendas del catálogo activo, priorizando sus preferencias de compra
  (categorías de su historial), la temporada vigente, sus tallas/colores preferidos
  y la disponibilidad en su sucursal de origen.

### Flujo principal
1. El cliente autenticado abre la sección "Recomendados para ti".
2. El sistema solicita recomendaciones al asistente de IA (`GET /ia/recomendaciones`).
3. El backend obtiene la temporada vigente y las preferencias del historial
   (categorías, tallas, colores) según los pedidos del cliente.
4. El backend arma el ranking: categorías preferidas → resto de la temporada →
   destacados; filtra por stock disponible en la sucursal del cliente.
5. El sistema devuelve la lista de productos y las muestra como carrusel.
6. El cliente puede tocar/hacer clic en una prenda y ver su detalle.

### Flujos alternativos
- **Sin historial:** se recomiendan destacados de la temporada vigente.
- **Sin stock en sucursal:** se recomienda con stock local; si el cliente no tiene
  sucursal asignada se omite el filtro de disponibilidad.
- **Error/fallo del servicio:** se oculta la sección y se muestra el catálogo normal.

### Clases del diseño (patrón ciclo 1)
- **INTERFAZ «boundary»** — `app/schemas/comercio.py`: `ProductoOut`,
  `ProductoVarianteOut`, `CategoriaOut`, `TemporadaOut`, `ProveedorOut`,
  `ColeccionOut`.
- **CONTROL «control»** — `app/api/v1/endpoints/ia.py`: `recomendar()`,
  `recomendar_por_sucursal()`; apoyo `app/api/v1/endpoints/bitacora.py: registrar()`;
  autenticación `app/core/dependencies.py: get_current_user`.
- **ENTIDAD «entity»** — `app/models/catalogo.py`: `Producto`, `ProductoVariante`,
  `Temporada`, `Categoria`; `app/models/ventas.py`: `Pedido`, `PedidoItem`;
  `app/models/inventario.py`: `Inventario`; `app/models/usuario.py`: `Usuario`.

### Endpoints
| Método | Ruta | Acceso | Descripción |
|--------|------|--------|-------------|
| GET | `/api/v1/ia/recomendaciones?limit=` | Cliente (JWT) | Recomienda según historial, temporada y stock de la sucursal del cliente. |
| GET | `/api/v1/ia/recomendaciones/disponibles?sucursal_id=&limit=` | Público | Productos con stock en una sucursal (soporte). |

Respuesta de ambos: `list[ProductoOut]` (con variantes, categoría, temporada,
proveedor, `imagen_url` y `modelo_3d_url`).

### Datos que usa el recomendador
- Historial: `Pedido` (usuario_id) → `PedidoItem` (variante_id) → `ProductoVariante`
  (producto_id, talla_id, color_id) → `Producto` (categoria_id).
- Temporada vigente: `Temporada` con `fecha_inicio <= hoy <= fecha_fin`.
- Disponibilidad: `Inventario` (sucursal_id = `Usuario.sucursal_id`,
  `cantidad_disponible > 0`).

### UI — Web (Angular)
- Sección "Recomendados para ti" en el catálogo (`app/catalogo`): carrusel
  horizontal de tarjetas de producto reutilizando el modelo `Producto`
  (`app/models/catalogo.ts`) y el estado `recomendados` (signal).
- Nuevo servicio `app/services/ia.service.ts` con `recomendar()` y `disponibles()`.
- Si la sección no carga, se omite silenciosamente.

### UI — Móvil (Flutter)
- Sección "Recomendados para ti" sobre el grid de `catalogo_screen.dart`:
  lista horizontal de `_ProductoCard` reutilizada, navega a
  `producto_detalle_screen.dart`.
- Nuevo servicio `services/ia_service.dart` sobre `ApiClient` (token en
  SharedPreferences). Si falla, se oculta la sección.

### Criterios de aceptación
1. GET `/ia/recomendaciones` sin token → 401.
2. GET `/ia/recomendaciones` con cliente autenticado → 200 con `list[ProductoOut]`
   (solo productos activos), ordenado con prioridad de categorías del historial.
3. Respuesta incluye variantes y `modelo_3d_url`/`imagen_url` (shape igual al catálogo).
4. GET `/ia/recomendaciones/disponibles?sucursal_id=1` → 200, solo productos con stock.
5. Acciones de recomendación quedan registradas en bitácora (CU-23).
6. Web y móvil muestran la sección "Recomendados para ti"; el detalle es accesible.

### Verificación (implementada)
- `tests/e2e_ciclo3.mjs` → **6/6 PASS** contra el stack en Docker:
  - sin token → 401; cliente → 200 list[producto]; shape ProductoOut + activos;
    variantes incluidas; /disponibles?sucursal_id=1 → 200; bitácora registra
    `CONSULTA_RECOMENDACIONES` (CU-23).
- Web: build de producción OK en Docker; carrusel "Recomendados para ti" en
  `localhost:8080/catalogo` mostró 6 productos vía navegador headless, sin
  errores de consola ni requests fallidos.
- Móvil: `flutter analyze` sin issues.
- Fix transversal: la tabla `bitacoras` (CU-23) no existía en el schema; se agregó
  el DDL en `database/01_creacion_base_datos.sql` y se aplicó a la BD en ejecución.

---

## CU-16 — Generar reportes y dashboards

- **Actor:** Administrador, Encargado (autenticados).
- **Plataforma:** Web (Angular) y Móvil (Flutter).
- **Requerimientos funcionales:** RF26 a RF33.
- **Descripción:** El personal de gestión genera una vista consolidada del negocio
  (KPIs, ventas por sucursal, productos más vendidos, rotación de inventario, stock
  crítico, reservas y tendencias por temporada), con filtros compartidos
  (fecha, sucursal, categoría, temporada) y exportación CSV/PDF.

### Flujo principal
1. El administrador o encargado abre "Reportes y dashboards".
2. El sistema carga los filtros disponibles (categorías, temporadas, sucursales).
3. El usuario configura criterios (opcionales) y pulsa "Generar reporte".
4. El backend ejecuta en paralelo los informes y devuelve el resumen consolidado.
5. El sistema muestra KPIs, gráficos y tablas; el usuario puede exportar CSV o PDF.

### Flujos alternativos
- **Encargado:** solo ve la información de SU sucursal (el backend lo fuerza sin
  importar el filtro enviado).
- **Sin resultados:** se muestra "No hay información disponible…".
- **Error de autorización:** roles sin permiso (cajero, cliente) reciben 403.
- **Exportación:** CSV descargable (web) / compartible (móvil) y PDF vía
  `window.print()` (web).

### Clases del diseño (patrón ciclo 1)
- **INTERFAZ «boundary»** — `app/schemas/reportes.py`: `ResumenReporteOut`,
  `VentaSucursalRow`, `MasVendidoRow`, `RotacionRow`, `StockCriticoRow`,
  `ReservaEstadoRow`, `ReservaSucursalRow`, `ReservasReporteOut`, `TendenciaRow`.
- **CONTROL «control»** — `app/api/v1/endpoints/reportes.py`: `resumen()`,
  `ventas_por_sucursal()`, `mas_vendidos()`, `rotacion_inventario()`,
  `stock_critico()`, `reservas()`, `tendencias()`; apoyo
  `app/api/v1/endpoints/bitacora.py: registrar()` (GENERA_REPORTE);
  autenticación/rol `app/api/v1/dependencies.py: get_current_user` +
  `get_admin_or_encargado`.
- **ENTIDAD «entity»** — `app/models/inventario.py` (`Inventario`,
  `Sucursal`), `app/models/ventas.py` (`Pedido`, `Venta`, `PedidoItem`,
  `Reserva`), `app/models/catalogo.py` (`Producto`, `ProductoVariante`,
  `Categoria`, `Temporada`), `app/models/usuario.py` (`Usuario`).

### Endpoints
| Método | Ruta | Acceso | Descripción |
|--------|------|--------|-------------|
| GET | `/api/v1/reportes/resumen` | Admin/Encargado | KPIs: ventas, pedidos, stock crítico, reservas activas + top productos. |
| GET | `/api/v1/reportes/ventas-por-sucursal` | Admin/Encargado | Total vendido por sucursal. |
| GET | `/api/v1/reportes/mas-vendidos?limit=` | Admin/Encargado | Productos con más unidades vendidas. |
| GET | `/api/v1/reportes/rotacion-inventario?limit=` | Admin/Encargado | Rotación = unidades vendidas / stock actual. |
| GET | `/api/v1/reportes/stock-critico` | Admin/Encargado | Variantes con disponible ≤ stock mínimo. |
| GET | `/api/v1/reportes/reservas` | Admin/Encargado | Reservas agrupadas por estado y por sucursal. |
| GET | `/api/v1/reportes/tendencias-temporada` | Admin/Encargado | Unidades y montos por temporada. |

Filtros comunes en todos: `fecha_desde`, `fecha_hasta` (YYYY-MM-DD),
`sucursal_id`, `categoria_id`, `temporada_id`. Un encargado queda restringido a su
`sucursal_id` en el backend.

### UI — Web (Angular)
- Ruta `/reportes` (guard `reportesGuard`: admin|encargado) → `app/reportes/`
  `ReportesComponent`: barra de filtros (fechas, sucursal, categoría, temporada),
  botones "Generar reporte", "CSV" (Blob + descarga) y "PDF" (`window.print()`),
  sección de KPIs, grid de gráficos (chart.js), tablas de stock crítico y rotación.
- Wrapper reutilizable `app/charts/fs-chart` sobre `chart.js` (sin dependencia de
  wrappers ng). Dependencia: `chart.js ^4.5.1`.
- Acceso desde el navbar ("Reportes") y quick-access del dashboard (admin/encargado).

### UI — Móvil (Flutter)
- Icono "Reportes" en la AppBar de `catalogo_screen.dart` solo para admin/encargado
  (rol persistido en SharedPreferences junto al token: `fashionstore_usuario`).
- `screens/reportes_screen.dart`: filtros (fechas vía `showDatePicker`,
  sucursal solo para admin, categoría y temporada), KPIs, 4 gráficos `fl_chart`
  (barras: ventas por sucursal, más vendidos, tendencias; torta: reservas por
  estado), listas de stock crítico y rotación, y exportación CSV con `share_plus`.
- Nuevas dependencias: `fl_chart`, `share_plus`. Servicio `services/reportes_service.dart`
  con los 7 endpoints; modelos en `models/reporte.dart`.

### Criterios de aceptación
1. Los 7 informes sin token → 401.
2. Roles sin permiso (cajero, cliente) → 403.
3. Admin: cada endpoint → 200 con el shape esperado (KPIs numéricos, listas
   tipadas, `stock_critico` con `disponible <= stock_minimo`).
4. Filtros combinados (`sucursal_id`, `categoria_id`, `temporada_id`,
   `fecha_desde/hasta`) aplican sin error.
5. Encargado: 200 y respuestas restringidas a su sucursal.
6. Parámetros inválidos (p. ej. `sucursal_id=9999`) → 400.
7. Cada generación registra bitácora `GENERA_REPORTE` (CU-23).
8. Web y móvil muestran KPIs, gráficos y tablas; exportan CSV; web imprime PDF.

### Verificación (implementada)
- Backend: smoke tests en vivo contra el stack en Docker (admin 7 endpoints OK,
  encargado filtrado a sucursal 1, 401 anónimo; `_valor_enum()` devuelve estados
  como `cancelada` en vez de `EstadoReserva.cancelada`).
- `tests/e2e_ciclo3.mjs` → **20/20 PASS** para CU-16:
  401 ×7, 403 cajero/cliente, resumen con KPIs reales (ventas 4662.50, 17 pedidos),
  shape de todos los informes, stock crítico (125) con `disponible <= mínimo`,
  filtros combinados, encargado restringido a sucursal 1, bitácora `GENERA_REPORTE`.
- Web: build de producción OK en Docker; QA headless en `/reportes`: KPIs
  `Bs.4,662.50 / 17 / 125 / 23`, 5 canvases de chart.js, tabla de 125 filas de
  stock crítico, 0 errores de consola y 0 requests fallidas.
- Móvil: `flutter analyze` **sin issues** (`fl_chart` + `share_plus`).

---

*(Última actualización: implementación de CU-17 y CU-16. CU-07 se agregará a este documento al implementarse.)*