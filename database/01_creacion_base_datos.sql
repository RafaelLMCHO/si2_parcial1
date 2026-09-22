-- ============================================================
-- SCRIPT 1: CREACIÓN DE LA BASE DE DATOS - FASHIONSTORE
-- Sistemas II - Plataforma Inteligente de Comercio Electrónico
-- Base de datos: PostgreSQL
-- CICLO #1: Autenticación, Ubicación, Catálogo, Inventario, Reservas
-- ============================================================

-- Eliminar y crear la base de datos solo si NO estamos conectados a ella
-- (así funciona tanto al ejecutarlo contra la BD "postgres" como dentro
--  de docker-entrypoint-initdb.d, que ya se conecta a "fashionstore")
SELECT current_database() <> 'fashionstore' AS bd_diferente \gset
\if :bd_diferente
  DROP DATABASE IF EXISTS fashionstore;
  CREATE DATABASE fashionstore;
  \c fashionstore
\endif

-- ============================================================
-- 1. TIPOS ENUM
-- ============================================================

CREATE TYPE rol_usuario AS ENUM ('admin', 'encargado', 'cajero', 'cliente');

CREATE TYPE tipo_movimiento AS ENUM (
    'entrada',
    'salida',
    'reserva',
    'cancelacion_reserva',
    'venta',
    'devolucion',
    'ajuste'
);

CREATE TYPE estado_reserva AS ENUM (
    'pendiente',
    'preparada',
    'completada',
    'cancelada'
);

CREATE TYPE estado_pedido AS ENUM (
    'pendiente',
    'pagado',
    'enviado',
    'entregado',
    'cancelado'
);

CREATE TYPE metodo_compra AS ENUM (
    'digital',
    'presencial'
);

CREATE TYPE tipo_pago AS ENUM (
    'tarjeta_debito',
    'tarjeta_credito',
    'qr',
    'transferencia',
    'efectivo'
);

CREATE TYPE estado_pago AS ENUM (
    'pendiente',
    'aprobado',
    'rechazado',
    'reembolsado'
);

-- ============================================================
-- 2. TABLAS
-- ============================================================

-- ------------------------------------------------------------
-- MODULO 1: AUTENTICACIÓN Y USUARIOS
-- ------------------------------------------------------------

CREATE TABLE sucursales (
    id_sucursal       SERIAL PRIMARY KEY,
    ciudad_id         INTEGER        NOT NULL,
    nombre            VARCHAR(150)   NOT NULL,
    direccion         VARCHAR(255)   NOT NULL,
    telefono          VARCHAR(20)    NULL,
    horario_apertura  TIME           NOT NULL,
    horario_cierre    TIME           NOT NULL,
    activo            BOOLEAN        NOT NULL DEFAULT TRUE
);

CREATE TABLE usuarios (
    id_usuario      SERIAL PRIMARY KEY,
    nombre          VARCHAR(100)   NOT NULL,
    email           VARCHAR(150)   NOT NULL UNIQUE,
    telefono        VARCHAR(20)    NULL,
    contrasena      VARCHAR(255)   NOT NULL,
    rol             rol_usuario    NOT NULL,
    sucursal_id     INTEGER        NULL REFERENCES sucursales(id_sucursal),
    fecha_registro  TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    activo          BOOLEAN        NOT NULL DEFAULT TRUE
);

-- ------------------------------------------------------------
-- MODULO 2: UBICACIÓN (CIUDADES Y SUCURSALES)
-- ------------------------------------------------------------

CREATE TABLE ciudades (
    id_ciudad  SERIAL PRIMARY KEY,
    nombre     VARCHAR(100) NOT NULL UNIQUE
);

-- FK de sucursales -> ciudades
ALTER TABLE sucursales
    ADD CONSTRAINT fk_sucursal_ciudad
    FOREIGN KEY (ciudad_id) REFERENCES ciudades(id_ciudad);

-- ------------------------------------------------------------
-- MODULO 3: CATÁLOGO DE PRODUCTOS
-- ------------------------------------------------------------

CREATE TABLE categorias (
    id_categoria  SERIAL PRIMARY KEY,
    nombre        VARCHAR(100) NOT NULL UNIQUE,
    descripcion   TEXT         NULL
);

CREATE TABLE colores (
    id_color    SERIAL PRIMARY KEY,
    nombre      VARCHAR(50)  NOT NULL UNIQUE,
    codigo_hex  VARCHAR(7)   NOT NULL
);

CREATE TABLE tallas (
    id_talla  SERIAL PRIMARY KEY,
    nombre    VARCHAR(10) NOT NULL UNIQUE
);

CREATE TABLE temporadas (
    id_temporada  SERIAL PRIMARY KEY,
    nombre        VARCHAR(100) NOT NULL UNIQUE,
    fecha_inicio  DATE         NOT NULL,
    fecha_fin     DATE         NOT NULL
);

CREATE TABLE colecciones (
    id_coleccion    SERIAL PRIMARY KEY,
    temporada_id    INTEGER      NOT NULL REFERENCES temporadas(id_temporada),
    nombre          VARCHAR(150) NOT NULL UNIQUE,
    descripcion     TEXT         NULL,
    es_promocional  BOOLEAN      NOT NULL DEFAULT FALSE
);

CREATE TABLE proveedores (
    id_proveedor  SERIAL PRIMARY KEY,
    nombre        VARCHAR(150) NOT NULL UNIQUE,
    contacto      VARCHAR(100) NULL,
    telefono      VARCHAR(20)  NULL,
    email         VARCHAR(150) NULL,
    direccion     VARCHAR(255) NULL
);

CREATE TABLE productos (
    id_producto    SERIAL PRIMARY KEY,
    nombre         VARCHAR(150) NOT NULL,
    descripcion    TEXT         NULL,
    precio         NUMERIC(10,2) NOT NULL,
    categoria_id   INTEGER      NOT NULL REFERENCES categorias(id_categoria),
    temporada_id   INTEGER      NOT NULL REFERENCES temporadas(id_temporada),
    coleccion_id   INTEGER      NULL REFERENCES colecciones(id_coleccion),
    proveedor_id   INTEGER      NOT NULL REFERENCES proveedores(id_proveedor),
    imagen_url     VARCHAR(255) NULL,
    modelo_3d_url  VARCHAR(255) NULL,
    activo         BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE producto_variantes (
    id_variante    SERIAL PRIMARY KEY,
    producto_id    INTEGER       NOT NULL REFERENCES productos(id_producto),
    color_id       INTEGER       NOT NULL REFERENCES colores(id_color),
    talla_id       INTEGER       NOT NULL REFERENCES tallas(id_talla),
    sku            VARCHAR(50)   NOT NULL UNIQUE,
    precio_extra   NUMERIC(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT uq_variante UNIQUE (producto_id, color_id, talla_id)
);

-- ------------------------------------------------------------
-- MODULO 4: INVENTARIO Y EXISTENCIAS
-- ------------------------------------------------------------

CREATE TABLE inventario (
    id_inventario        SERIAL PRIMARY KEY,
    variante_id          INTEGER NOT NULL REFERENCES producto_variantes(id_variante),
    sucursal_id          INTEGER NOT NULL REFERENCES sucursales(id_sucursal),
    cantidad_disponible  INTEGER NOT NULL CHECK (cantidad_disponible >= 0),
    cantidad_reservada   INTEGER NOT NULL DEFAULT 0 CHECK (cantidad_reservada >= 0),
    cantidad_recibida    INTEGER NOT NULL DEFAULT 0,
    stock_minimo         INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT uq_inventario_variante_sucursal UNIQUE (variante_id, sucursal_id)
);

CREATE TABLE movimientos_inventario (
    id_movimiento     SERIAL PRIMARY KEY,
    variante_id       INTEGER          NOT NULL REFERENCES producto_variantes(id_variante),
    sucursal_id       INTEGER          NOT NULL REFERENCES sucursales(id_sucursal),
    tipo_movimiento   tipo_movimiento  NOT NULL,
    cantidad          INTEGER          NOT NULL,
    referencia_id     INTEGER          NULL,
    observacion       TEXT             NULL,
    fecha_movimiento  TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ------------------------------------------------------------
-- MODULO 5: RESERVAS
-- ------------------------------------------------------------

CREATE TABLE reservas (
    id_reserva      SERIAL PRIMARY KEY,
    usuario_id      INTEGER          NOT NULL REFERENCES usuarios(id_usuario),
    sucursal_id     INTEGER          NOT NULL REFERENCES sucursales(id_sucursal),
    fecha_reserva   DATE             NOT NULL,
    hora_atencion   TIME             NOT NULL,
    estado          estado_reserva   NOT NULL DEFAULT 'pendiente',
    fecha_creacion  TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE reserva_items (
    id_reserva_item  SERIAL PRIMARY KEY,
    reserva_id       INTEGER NOT NULL REFERENCES reservas(id_reserva),
    variante_id      INTEGER NOT NULL REFERENCES producto_variantes(id_variante),
    cantidad         INTEGER NOT NULL CHECK (cantidad >= 1)
);

-- ------------------------------------------------------------
-- MODULO 6: VENTAS Y PAGOS (Ciclo #2)
-- ------------------------------------------------------------

CREATE TABLE pedidos (
    id_pedido      SERIAL PRIMARY KEY,
    usuario_id     INTEGER        NOT NULL REFERENCES usuarios(id_usuario),
    sucursal_id    INTEGER        NULL REFERENCES sucursales(id_sucursal),
    fecha_pedido   TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total          NUMERIC(10,2)  NOT NULL,
    metodo_compra  metodo_compra  NOT NULL,
    estado         estado_pedido  NOT NULL DEFAULT 'pendiente',
    tipo_pago      tipo_pago      NULL
);

CREATE TABLE pedido_items (
    id_pedido_item   SERIAL PRIMARY KEY,
    pedido_id        INTEGER   NOT NULL REFERENCES pedidos(id_pedido),
    variante_id      INTEGER   NOT NULL REFERENCES producto_variantes(id_variante),
    cantidad         INTEGER   NOT NULL CHECK (cantidad >= 1),
    precio_unitario  NUMERIC(10,2) NOT NULL,
    subtotal         NUMERIC(10,2) NOT NULL
);

CREATE TABLE pagos (
    id_pago         SERIAL PRIMARY KEY,
    pedido_id       INTEGER        NOT NULL REFERENCES pedidos(id_pedido),
    monto           NUMERIC(10,2)  NOT NULL,
    proveedor_pago  VARCHAR(50)    NOT NULL,
    transaccion_id  VARCHAR(100)   NULL,
    estado          estado_pago    NOT NULL,
    fecha_pago      TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_pedidos_usuario    ON pedidos(usuario_id);
CREATE INDEX idx_pedidos_sucursal   ON pedidos(sucursal_id);
CREATE INDEX idx_pedidos_estado     ON pedidos(estado);
CREATE INDEX idx_items_pedido       ON pedido_items(pedido_id);
CREATE INDEX idx_pagos_pedido       ON pagos(pedido_id);

-- Carritos de compra digital esperando el retorno de la pasarela (Stripe Checkout).
CREATE TABLE checkout_pendiente (
    session_id  VARCHAR(255)   PRIMARY KEY,
    usuario_id  INTEGER        NOT NULL REFERENCES usuarios(id_usuario),
    sucursal_id INTEGER        NOT NULL,
    items       JSONB          NOT NULL,
    monto       NUMERIC(10,2)  NOT NULL,
    created_at  TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 3. ÍNDICES PARA BÚSQUEDA FRECUENTE (RNF02 - Rendimiento)
-- ============================================================

CREATE INDEX idx_productos_nombre     ON productos(nombre);
CREATE INDEX idx_productos_categoria  ON productos(categoria_id);
CREATE INDEX idx_productos_temporada  ON productos(temporada_id);
CREATE INDEX idx_productos_proveedor  ON productos(proveedor_id);
CREATE INDEX idx_variantes_producto   ON producto_variantes(producto_id);
CREATE INDEX idx_inventario_sucursal  ON inventario(sucursal_id);
CREATE INDEX idx_reservas_usuario     ON reservas(usuario_id);
CREATE INDEX idx_reservas_sucursal    ON reservas(sucursal_id);
CREATE INDEX idx_reservas_estado      ON reservas(estado);
CREATE INDEX idx_movimientos_variante ON movimientos_inventario(variante_id);
CREATE INDEX idx_items_reserva        ON reserva_items(reserva_id);
CREATE INDEX idx_usuarios_email       ON usuarios(email);
CREATE INDEX idx_usuarios_rol         ON usuarios(rol);

-- ============================================================
-- 4. TRIGGERS
-- ============================================================

-- ------------------------------------------------------------
-- 4.1 TRG_VALIDAR_STOCK_RESERVA
-- Valida que exista stock disponible antes de insertar un ítem de reserva.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validar_stock_reserva()
RETURNS TRIGGER AS $$
DECLARE
    v_sucursal_id    INTEGER;
    v_stock_disp     INTEGER;
BEGIN
    SELECT sucursal_id INTO v_sucursal_id
    FROM reservas WHERE id_reserva = NEW.reserva_id;

    SELECT cantidad_disponible INTO v_stock_disp
    FROM inventario
    WHERE variante_id = NEW.variante_id AND sucursal_id = v_sucursal_id;

    IF v_stock_disp IS NULL OR v_stock_disp < NEW.cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente para la variante % en la sucursal %',
            NEW.variante_id, v_sucursal_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_stock_reserva
    BEFORE INSERT ON reserva_items
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_stock_reserva();

-- ------------------------------------------------------------
-- 4.2 TRG_RESERVA_ITEM_INSERT (AFTER INSERT en reserva_items)
-- Reserva stock al insertar un ítem de reserva: aumenta cantidad_reservada,
-- disminuye cantidad_disponible y registra movimiento de inventario.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_reserva_item_insert()
RETURNS TRIGGER AS $$
DECLARE
    v_sucursal_id INTEGER;
BEGIN
    SELECT sucursal_id INTO v_sucursal_id
    FROM reservas WHERE id_reserva = NEW.reserva_id;

    UPDATE inventario
    SET cantidad_reservada  = cantidad_reservada + NEW.cantidad,
        cantidad_disponible = cantidad_disponible - NEW.cantidad
    WHERE variante_id = NEW.variante_id
      AND sucursal_id = v_sucursal_id;

    INSERT INTO movimientos_inventario
        (variante_id, sucursal_id, tipo_movimiento, cantidad, referencia_id, observacion)
    VALUES
        (NEW.variante_id, v_sucursal_id, 'reserva', NEW.cantidad,
         NEW.reserva_id, 'Reserva creada');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reserva_item_insert
    AFTER INSERT ON reserva_items
    FOR EACH ROW
    EXECUTE FUNCTION fn_reserva_item_insert();

-- ------------------------------------------------------------
-- 4.3 TRG_RESERVA_CANCELADA (AFTER UPDATE en reservas -> cancelada)
-- Libera stock reservado.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_reserva_cancelada()
RETURNS TRIGGER AS $$
DECLARE
    v_item RECORD;
BEGIN
    IF NEW.estado = 'cancelada' AND OLD.estado <> 'cancelada' THEN
        FOR v_item IN
            SELECT variante_id, cantidad
            FROM reserva_items
            WHERE reserva_id = NEW.id_reserva
        LOOP
            UPDATE inventario
            SET cantidad_reservada  = cantidad_reservada - v_item.cantidad,
                cantidad_disponible = cantidad_disponible + v_item.cantidad
            WHERE variante_id = v_item.variante_id
              AND sucursal_id = NEW.sucursal_id;

            INSERT INTO movimientos_inventario
                (variante_id, sucursal_id, tipo_movimiento, cantidad, referencia_id, observacion)
            VALUES
                (v_item.variante_id, NEW.sucursal_id, 'cancelacion_reserva',
                 -v_item.cantidad, NEW.id_reserva, 'Reserva cancelada');
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reserva_cancelada
    AFTER UPDATE ON reservas
    FOR EACH ROW
    EXECUTE FUNCTION fn_reserva_cancelada();

-- ------------------------------------------------------------
-- 4.4 TRG_VALIDAR_SKU
-- Valida unicidad del SKU con mensaje personalizado.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validar_sku()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM producto_variantes
        WHERE sku = NEW.sku AND id_variante <> NEW.id_variante
    ) THEN
        RAISE EXCEPTION 'El SKU % ya se encuentra registrado', NEW.sku;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_sku
    BEFORE INSERT OR UPDATE ON producto_variantes
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_sku();

-- ============================================================
-- 5. PROCEDIMIENTOS ALMACENADOS
-- ============================================================

-- ------------------------------------------------------------
-- 5.1 SP_CREAR_RESERVA
-- Crea una reserva de múltiples prendas en una sucursal.
-- Si falla la validación de stock de algún ítem, revierte toda la operación.
-- Parámetros: p_usuario_id, p_sucursal_id, p_fecha, p_hora,
--             p_variantes (JSON: [{"variante_id":1,"cantidad":2},...])
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_crear_reserva(
    p_usuario_id      INTEGER,
    p_sucursal_id     INTEGER,
    p_fecha_reserva   DATE,
    p_hora_atencion   TIME,
    p_variantes       JSONB,
    INOUT p_reserva_id INTEGER DEFAULT 0
)
LANGUAGE plpgsql AS $$
DECLARE
    v_item JSONB;
BEGIN
    INSERT INTO reservas (usuario_id, sucursal_id, fecha_reserva, hora_atencion, estado)
    VALUES (p_usuario_id, p_sucursal_id, p_fecha_reserva, p_hora_atencion, 'pendiente')
    RETURNING id_reserva INTO p_reserva_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_variantes)
    LOOP
        INSERT INTO reserva_items (reserva_id, variante_id, cantidad)
        VALUES (
            p_reserva_id,
            (v_item->>'variante_id')::INTEGER,
            (v_item->>'cantidad')::INTEGER
        );
    END LOOP;

    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
$$;

-- ------------------------------------------------------------
-- 5.2 SP_CANCELAR_RESERVA
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cancelar_reserva(
    p_reserva_id INTEGER
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE reservas SET estado = 'cancelada' WHERE id_reserva = p_reserva_id;
    COMMIT;
END;
$$;

-- ------------------------------------------------------------
-- 5.3 SP_PREPARAR_RESERVA (Encargado de sucursal)
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_preparar_reserva(
    p_reserva_id INTEGER
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE reservas
    SET estado = 'preparada'
    WHERE id_reserva = p_reserva_id AND estado = 'pendiente';
    COMMIT;
END;
$$;

-- ------------------------------------------------------------
-- 5.4 SP_COMPLETAR_RESERVA
-- Al completar, libera el stock que no se compró (aquí se asume compra total
-- del cliente; el resto se gestiona al registrar venta).
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_completar_reserva(
    p_reserva_id INTEGER
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE reservas
    SET estado = 'completada'
    WHERE id_reserva = p_reserva_id AND estado IN ('pendiente', 'preparada');
    COMMIT;
END;
$$;

-- ============================================================
-- 6. FUNCIÓN DE CONSULTA DE DISPONIBILIDAD (RF08)
-- ============================================================

CREATE OR REPLACE FUNCTION fn_consultar_disponibilidad(
    p_variante_id INTEGER,
    p_sucursal_id INTEGER DEFAULT NULL
)
RETURNS TABLE (
    variante_id     INTEGER,
    sucursal_id     INTEGER,
    nombre_sucursal VARCHAR(150),
    disponible      INTEGER,
    reservada       INTEGER,
    recibida        INTEGER,
    stock_minimo    INTEGER,
    estado          TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT i.variante_id,
           i.sucursal_id,
           s.nombre,
           i.cantidad_disponible,
           i.cantidad_reservada,
           i.cantidad_recibida,
           i.stock_minimo,
           CASE
               WHEN i.cantidad_disponible > 0 THEN 'Disponible'
               WHEN i.cantidad_reservada > 0 THEN 'Reservada'
               WHEN i.cantidad_recibida > 0 THEN 'Proxima a ingresar'
               ELSE 'Agotada'
           END
    FROM inventario i
    JOIN sucursales s ON s.id_sucursal = i.sucursal_id
    WHERE i.variante_id = p_variante_id
      AND (p_sucursal_id IS NULL OR i.sucursal_id = p_sucursal_id)
    ORDER BY i.sucursal_id;
END;
$$;

-- ============================================================
-- 7. TRIGGERS Y SP DE VENTAS (Ciclo #2)
-- ============================================================

-- ------------------------------------------------------------
-- 7.1 TRG_PEDIDO_PAGADO (AFTER UPDATE en pedidos -> 'pagado')
-- Descuenta stock al confirmar el pago de un pedido.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_pedido_pagado()
RETURNS TRIGGER AS $$
DECLARE
    v_item RECORD;
    v_sucursal INTEGER;
BEGIN
    IF NEW.estado = 'pagado' AND OLD.estado <> 'pagado' THEN
        v_sucursal := NEW.sucursal_id;

        FOR v_item IN
            SELECT variante_id, cantidad
            FROM pedido_items WHERE pedido_id = NEW.id_pedido
        LOOP
            UPDATE inventario
            SET cantidad_disponible = cantidad_disponible - v_item.cantidad
            WHERE variante_id = v_item.variante_id
              AND sucursal_id = v_sucursal;

            INSERT INTO movimientos_inventario
                (variante_id, sucursal_id, tipo_movimiento, cantidad, referencia_id, observacion)
            VALUES
                (v_item.variante_id, v_sucursal, 'venta', -v_item.cantidad,
                 NEW.id_pedido, 'Venta registrada');
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_pedido_pagado
    AFTER UPDATE ON pedidos
    FOR EACH ROW
    EXECUTE FUNCTION fn_pedido_pagado();

-- ------------------------------------------------------------
-- 7.2 SP_REGISTRAR_VENTA_PRESENCIAL (Cajero - punto de caja)
-- Registra una venta, sus ítems y descuenta inventario.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_venta_presencial(
    p_usuario_id     INTEGER,
    p_sucursal_id    INTEGER,
    p_tipo_pago      tipo_pago,
    p_items          JSONB,
    INOUT p_pedido_id INTEGER DEFAULT 0
)
LANGUAGE plpgsql AS $$
DECLARE
    v_item   JSONB;
    v_total  NUMERIC(10,2) := 0;
    v_precio NUMERIC(10,2);
    v_sub    NUMERIC(10,2);
BEGIN
    -- Validar stock disponible para cada ítem
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        SELECT cantidad_disponible FROM inventario
        WHERE variante_id = (v_item->>'variante_id')::INTEGER
          AND sucursal_id = p_sucursal_id
        INTO v_total;

        IF v_total IS NULL OR v_total < (v_item->>'cantidad')::INTEGER THEN
            RAISE EXCEPTION 'Stock insuficiente en caja para la variante %',
                (v_item->>'variante_id')::INTEGER;
        END IF;
    END LOOP;

    v_total := 0;
    -- Calcular total
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        SELECT pr.precio + pv.precio_extra
        INTO v_precio
        FROM producto_variantes pv
        JOIN productos pr ON pr.id_producto = pv.producto_id
        WHERE pv.id_variante = (v_item->>'variante_id')::INTEGER;

        v_sub := v_precio * (v_item->>'cantidad')::INTEGER;
        v_total := v_total + v_sub;
    END LOOP;

    INSERT INTO pedidos (usuario_id, sucursal_id, total, metodo_compra, estado, tipo_pago)
    VALUES (p_usuario_id, p_sucursal_id, v_total, 'presencial', 'pagado', p_tipo_pago)
    RETURNING id_pedido INTO p_pedido_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        SELECT pr.precio + pv.precio_extra
        INTO v_precio
        FROM producto_variantes pv
        JOIN productos pr ON pr.id_producto = pv.producto_id
        WHERE pv.id_variante = (v_item->>'variante_id')::INTEGER;

        v_sub := v_precio * (v_item->>'cantidad')::INTEGER;

        INSERT INTO pedido_items (pedido_id, variante_id, cantidad, precio_unitario, subtotal)
        VALUES (p_pedido_id, (v_item->>'variante_id')::INTEGER,
                (v_item->>'cantidad')::INTEGER, v_precio, v_sub);
    END LOOP;

    IF p_tipo_pago <> 'efectivo' THEN
        INSERT INTO pagos (pedido_id, monto, proveedor_pago, transaccion_id, estado)
        VALUES (p_pedido_id, v_total, 'Punto de Venta',
                'TXN-CAJA-' || p_pedido_id, 'aprobado');
    END IF;

    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
$$;

-- ------------------------------------------------------------
-- 7.3 SP_REGISTRAR_VENTA_DIGITAL (Web/Móvil + pasarela de pago)
-- Crea el pedido en estado pendiente, registra el pago aprobado y
-- activa el trigger que descuenta stock.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_venta_digital(
    p_usuario_id   INTEGER,
    p_items        JSONB,
    p_pasarela     VARCHAR(50),
    INOUT p_pedido_id INTEGER DEFAULT 0
)
LANGUAGE plpgsql AS $$
DECLARE
    v_item   JSONB;
    v_total  NUMERIC(10,2) := 0;
    v_precio NUMERIC(10,2);
    v_sub    NUMERIC(10,2);
    v_suc    INTEGER;
BEGIN
    v_total := 0;
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        SELECT pr.precio + pv.precio_extra
        INTO v_precio
        FROM producto_variantes pv
        JOIN productos pr ON pr.id_producto = pv.producto_id
        WHERE pv.id_variante = (v_item->>'variante_id')::INTEGER;
        v_total := v_total + (v_precio * (v_item->>'cantidad')::INTEGER);
    END LOOP;

    -- Usar una sucursal por defecto (1) para venta digital
    SELECT COALESCE(MIN(id_sucursal), 1) INTO v_suc FROM sucursales;

    INSERT INTO pedidos (usuario_id, sucursal_id, total, metodo_compra, estado, tipo_pago)
    VALUES (p_usuario_id, v_suc, v_total, 'digital', 'pendiente', NULL)
    RETURNING id_pedido INTO p_pedido_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        SELECT pr.precio + pv.precio_extra
        INTO v_precio
        FROM producto_variantes pv
        JOIN productos pr ON pr.id_producto = pv.producto_id
        WHERE pv.id_variante = (v_item->>'variante_id')::INTEGER;
        v_sub := v_precio * (v_item->>'cantidad')::INTEGER;

        INSERT INTO pedido_items (pedido_id, variante_id, cantidad, precio_unitario, subtotal)
        VALUES (p_pedido_id, (v_item->>'variante_id')::INTEGER,
                (v_item->>'cantidad')::INTEGER, v_precio, v_sub);
    END LOOP;

    -- Registrar pago aprobado y cambiar estado -> pagado (dispara descuento de stock)
    INSERT INTO pagos (pedido_id, monto, proveedor_pago, transaccion_id, estado)
    VALUES (p_pedido_id, v_total, p_pasarela,
            'TXN-' || upper(p_pasarela) || '-' || p_pedido_id, 'aprobado');

    UPDATE pedidos SET estado = 'pagado' WHERE id_pedido = p_pedido_id;

    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
$$;

-- ============================================================
-- 21. BITÁCORA (CU-23, transversal)
-- ============================================================

CREATE TABLE IF NOT EXISTS bitacoras (
    id_bitacora  SERIAL PRIMARY KEY,
    usuario_id   INTEGER REFERENCES usuarios(id_usuario) ON DELETE SET NULL,
    accion       VARCHAR(80)  NOT NULL,
    entidad      VARCHAR(60),
    entidad_id   INTEGER,
    detalle      TEXT,
    ip_origen    VARCHAR(45),
    fecha        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS ix_bitacoras_usuario_id ON bitacoras (usuario_id);
CREATE INDEX IF NOT EXISTS ix_bitacoras_accion ON bitacoras (accion);
CREATE INDEX IF NOT EXISTS ix_bitacoras_fecha ON bitacoras (fecha);
