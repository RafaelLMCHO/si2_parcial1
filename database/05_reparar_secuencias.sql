-- ============================================================
-- SCRIPT 5: REPARACIÓN DE SECUENCIAS DE ID SERIAL
-- Sistemas II - Plataforma Inteligente de Comercio Electrónico
-- Base de datos: PostgreSQL
--
-- Problema que corrige:
--   02_poblacion.sql inserta las filas con id explícito, por lo que las
--   secuencias de los id serial quedan en 1 mientras los id más altos ya son
--   14, 18, etc. El siguiente INSERT de la aplicación recibe un id que ya
--   existe y PostgreSQL aborta con:
--       duplicate key value violates unique constraint "pedidos_pkey"
--
--   Esto afecta a toda escritura de pedidos, pagos, items de pedido, reservas
--   y bitácora: el punto de venta, la compra digital y el registro de bitácora
--   fallan hasta que las secuencias están alineadas.
--
-- Cuándo ejecutarlo:
--   - Sobre una base ya poblada con 01 + 02 anteriores a esta corrección.
--   - Es idempotente y no modifica datos: solo mueve el puntero de las
--     secuencias al último id utilizado.
--
-- El script 02 ya incluye esta sincronización, de modo que una instalación
-- nueva no necesita este archivo.
-- ============================================================

SELECT setval(pg_get_serial_sequence('pedidos', 'id_pedido'),
              COALESCE((SELECT MAX(id_pedido) FROM pedidos), 1));
SELECT setval(pg_get_serial_sequence('pedido_items', 'id_pedido_item'),
              COALESCE((SELECT MAX(id_pedido_item) FROM pedido_items), 1));
SELECT setval(pg_get_serial_sequence('pagos', 'id_pago'),
              COALESCE((SELECT MAX(id_pago) FROM pagos), 1));
SELECT setval(pg_get_serial_sequence('reservas', 'id_reserva'),
              COALESCE((SELECT MAX(id_reserva) FROM reservas), 1));
SELECT setval(pg_get_serial_sequence('reserva_items', 'id_reserva_item'),
              COALESCE((SELECT MAX(id_reserva_item) FROM reserva_items), 1));
SELECT setval(pg_get_serial_sequence('movimientos_inventario', 'id_movimiento'),
              COALESCE((SELECT MAX(id_movimiento) FROM movimientos_inventario), 1));
SELECT setval(pg_get_serial_sequence('bitacoras', 'id_bitacora'),
              COALESCE((SELECT MAX(id_bitacora) FROM bitacoras), 1));

-- Verificación: cada secuencia debe quedar igual o por encima del id máximo.
SELECT 'pedidos' AS tabla, MAX(id_pedido) AS id_maximo,
       (SELECT last_value FROM pedidos_id_pedido_seq) AS secuencia
  FROM pedidos
UNION ALL
SELECT 'pedido_items', MAX(id_pedido_item), (SELECT last_value FROM pedido_items_id_pedido_item_seq)
  FROM pedido_items
UNION ALL
SELECT 'pagos', MAX(id_pago), (SELECT last_value FROM pagos_id_pago_seq) FROM pagos
UNION ALL
SELECT 'reservas', MAX(id_reserva), (SELECT last_value FROM reservas_id_reserva_seq) FROM reservas
UNION ALL
SELECT 'reserva_items', MAX(id_reserva_item), (SELECT last_value FROM reserva_items_id_reserva_item_seq)
  FROM reserva_items
UNION ALL
SELECT 'bitacoras', MAX(id_bitacora), (SELECT last_value FROM bitacoras_id_bitacora_seq) FROM bitacoras
ORDER BY tabla;
