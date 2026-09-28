-- ============================================================
-- SCRIPT 4: MIGRACIÓN - SOPORTE DE COBRO QR EN PAGOS
-- Sistemas II - Plataforma Inteligente de Comercio Electrónico
-- Base de datos: PostgreSQL
--
-- Objetivo:
--   Permitir que un cobro QR quede registrado como PENDIENTE mientras la
--   pasarela externa confirma el pago. El cobro se crea con
--   estado='pendiente' y la pasarela(notificación) lo mueve a 'aprobado',
--   'rechazado' o lo deja vencer. El enum estado_pago ya contempla
--   pendiente/aprobado/rechazado/reembolsado, por lo que no hace falta
--   modificar tipos ni columnas del modelo de pagos.
--
-- Se agrega una sola columna JSONB para persistir los datos que devuelve la
-- pasarela (URL del QR, URL de pago, si fue simulado y fecha de expiración).
-- La fila de la tabla pagos con estado='pendiente' actúa como registro de
-- seguimiento, por lo que no se requiere una tabla nueva.
--
-- El script es idempotente: se puede ejecutar varias veces sin error y es
-- válido tanto sobre una base recien creada (01) como sobre una ya desplegada.
-- ============================================================

-- Columna de datos de la pasarela en la tabla pagos.
ALTER TABLE pagos ADD COLUMN IF NOT EXISTS datos_gateway JSONB;

-- Índice parcial para localizar cobros QR pendientes por su transaction_id.
-- El endpoint de webhook resuelve el cobro por este valor, por lo que un
-- índice parcial lo vuelve una consulta O(log n) en lugar de un seq scan.
CREATE INDEX IF NOT EXISTS idx_pagos_gateway_pendiente
    ON pagos (proveedor_pago, transaccion_id)
    WHERE estado = 'pendiente';

-- Restricción de unicidad para la transaction_id reportada por la pasarela.
-- Es la garantía de idempotencia a nivel de base de datos: aunque el webhook
-- se reciba dos veces (o dos hilos lo procesen a la vez), el segundo INSERT
-- de la fila de cobro no puede duplicarse. La verificación en la capa de
-- aplicación (pagos.py) sigue siendo la primera línea de defensa.
CREATE UNIQUE INDEX IF NOT EXISTS uq_pagos_transaccion_gateway
    ON pagos (proveedor_pago, transaccion_id)
    WHERE transaccion_id IS NOT NULL
      AND transaccion_id <> '';

-- Verificación: la columna debe existir y el enum de estado no cambiar.
SELECT column_name, data_type
  FROM information_schema.columns
 WHERE table_name = 'pagos'
   AND column_name = 'datos_gateway';
