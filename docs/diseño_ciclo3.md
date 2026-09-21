# Diseño del Ciclo #3 — FashionStore

Documento de diseño de los casos de uso del CICLO #3 implementados uno a uno.
Cada CU incluye: ficha, clases (INTERFAZ / CONTROL / ENTIDAD), endpoints, datos,
UI (web y móvil) y criterios de aceptación.

| CU  | Nombre                              | Plataforma |
|-----|-------------------------------------|------------|
| CU-17 | Recibir recomendaciones de IA     | Web + Móvil |
| CU-16 | Generar reportes y dashboards     | Web + Móvil (pendiente) |
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

*(Última actualización: implementación de CU-17. CU-16 y CU-07 se agregarán a este documento al implementarse.)*