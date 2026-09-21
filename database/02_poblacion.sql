-- ============================================================
-- SCRIPT 2: POBLACIÓN DE DATOS - FASHIONSTORE (Bolivia)
-- Sistemas II - Sucursal principal: Santa Cruz de la Sierra
-- Población realista: productos agotados, stock bajo, ventas,
-- reservas en distintos estados, pagos y movimientos.
-- ============================================================

\c fashionstore;

-- ============================================================
-- DESHABILITAR TRIGGERS QUE MODIFICAN INVENTARIO DURANTE LA CARGA
-- (Se insertan valores finales coherentes; los movimientos se
--  registran manualmente al final).
-- ============================================================
ALTER TABLE reservas           DISABLE TRIGGER ALL;
ALTER TABLE reserva_items      DISABLE TRIGGER ALL;
ALTER TABLE pedidos            DISABLE TRIGGER ALL;
ALTER TABLE pedido_items       DISABLE TRIGGER ALL;
ALTER TABLE producto_variantes DISABLE TRIGGER ALL;

-- ============================================================
-- CIUDADES (6 ciudades de Bolivia)
-- ============================================================
INSERT INTO ciudades (nombre) VALUES
('Santa Cruz de la Sierra'),
('La Paz'),
('Cochabamba'),
('Tarija'),
('Sucre'),
('El Alto');

-- ============================================================
-- SUCURSALES (7 sucursales, principal en Santa Cruz)
-- ============================================================
INSERT INTO sucursales (ciudad_id, nombre, direccion, telefono, horario_apertura, horario_cierre, activo) VALUES
(1, 'FashionStore Santa Cruz - Centro', 'Av. Monseñor Rivero Nro. 250', '(591) 3-333-4455', '09:00:00', '21:00:00', TRUE),
(1, 'FashionStore Santa Cruz - Ventura', 'Av. San Martin Nro. 1500', '(591) 3-344-2211', '10:00:00', '22:00:00', TRUE),
(2, 'FashionStore La Paz - El Prado', 'Av. Mariscal Santa Cruz Nro. 800', '(591) 2-211-3344', '09:30:00', '20:30:00', TRUE),
(3, 'FashionStore Cochabamba - Recoleta', 'Av. Heroinas Nro. 340', '(591) 4-455-6677', '09:00:00', '20:00:00', TRUE),
(4, 'FashionStore Tarija - Centro', 'Calle La Madrid Nro. 120', '(591) 4-666-8899', '10:00:00', '20:00:00', TRUE),
(5, 'FashionStore Sucre - Plaza', 'Calle España Nro. 45', '(591) 4-645-2211', '09:00:00', '19:00:00', TRUE),
(6, 'FashionStore El Alto - 16 de Julio', 'Av. 16 de Julio Nro. 500', '(591) 2-283-4455', '10:00:00', '21:00:00', TRUE);

-- ============================================================
-- USUARIOS (1 admin, 4 encargados, 4 cajeros, 10 clientes)
-- ============================================================
INSERT INTO usuarios (nombre, email, telefono, contrasena, rol, sucursal_id, activo) VALUES
('Administrador General', 'admin@fashionstore.bo', '(591) 700-000-001', 'admin123', 'admin', NULL, TRUE),
('Juan Perez', 'juan.perez@fashionstore.bo', '(591) 700-000-002', 'encargado123', 'encargado', 1, TRUE),
('Maria Lopez', 'maria.lopez@fashionstore.bo', '(591) 700-000-003', 'encargado123', 'encargado', 3, TRUE),
('Carlos Rojas', 'carlos.rojas@fashionstore.bo', '(591) 700-000-004', 'cajero123', 'cajero', 1, TRUE),
('Ana Gutierrez', 'ana.gutierrez@fashionstore.bo', '(591) 700-000-005', 'cajero123', 'cajero', 2, TRUE),
('Laura Vargas', 'laura.vargas@gmail.com', '(591) 711-111-001', 'cliente123', 'cliente', NULL, TRUE),
('Pedro Siles', 'pedro.siles@gmail.com', '(591) 711-111-002', 'cliente123', 'cliente', NULL, TRUE),
('Sofia Mendoza', 'sofia.mendoza@gmail.com', '(591) 711-111-003', 'cliente123', 'cliente', NULL, TRUE),
('Diego Roca', 'diego.roca@gmail.com', '(591) 711-111-004', 'cliente123', 'cliente', NULL, TRUE),
('Nestor Suarez', 'nestor.suarez@gmail.com', '(591) 711-111-005', 'cliente123', 'cliente', NULL, TRUE),
('Camila Delgado', 'camila.delgado@gmail.com', '(591) 711-111-006', 'cliente123', 'cliente', NULL, TRUE),
('Rodrigo Quispe', 'rodrigo.quispe@gmail.com', '(591) 711-111-007', 'cliente123', 'cliente', NULL, TRUE),
('Valentina Choque', 'valentina.choque@gmail.com', '(591) 711-111-008', 'cliente123', 'cliente', NULL, TRUE),
('Miguel Campos', 'miguel.campos@gmail.com', '(591) 711-111-009', 'cliente123', 'cliente', NULL, TRUE),
('Fernanda Ortiz', 'fernanda.ortiz@gmail.com', '(591) 711-111-010', 'cliente123', 'cliente', NULL, TRUE),
('Encargada Tarija', 'encargada.tarija@fashionstore.bo', '(591) 700-000-006', 'encargado123', 'encargado', 5, TRUE),
('Cajero El Alto', 'cajero.elalto@fashionstore.bo', '(591) 700-000-007', 'cajero123', 'cajero', 7, TRUE),
('Cajera Cochabamba', 'cajera.cochabamba@fashionstore.bo', '(591) 700-000-008', 'cajero123', 'cajero', 4, TRUE),
('Encargado Cochabamba', 'encargado.cocha@fashionstore.bo', '(591) 700-000-009', 'encargado123', 'encargado', 4, TRUE);

-- ============================================================
-- CATEGORÍAS
-- ============================================================
INSERT INTO categorias (nombre, descripcion) VALUES
('Camisetas', 'Prendas superiores de algodon y poliester'),
('Pantalones', 'Jeans, chinos y casuales'),
('Vestidos', 'Vestidos para diversas ocasiones'),
('Abrigos', 'Prendas de abrigo para invierno'),
('Chaquetas', 'Chaquetas y blazers'),
('Faldas', 'Faldas de distintas longitudes'),
('Accesorios', 'Bufandas, gorras, cinturones');

-- ============================================================
-- COLORES
-- ============================================================
INSERT INTO colores (nombre, codigo_hex) VALUES
('Negro', '#000000'),
('Blanco', '#FFFFFF'),
('Rojo', '#FF0000'),
('Azul', '#0000FF'),
('Verde', '#008000'),
('Gris', '#808080'),
('Beige', '#F5F5DC'),
('Marron', '#A52A2A');

-- ============================================================
-- TALLAS
-- ============================================================
INSERT INTO tallas (nombre) VALUES
('XS'),
('S'),
('M'),
('L'),
('XL'),
('XXL');

-- ============================================================
-- TEMPORADAS
-- ============================================================
INSERT INTO temporadas (nombre, fecha_inicio, fecha_fin) VALUES
('Primavera - Verano 2026', '2026-09-01', '2027-02-28'),
('Otoño - Invierno 2026', '2026-03-01', '2026-08-31'),
('Temporada Escolar 2026', '2026-01-01', '2026-02-28'),
('Nueva Coleccion 2026', '2026-07-01', '2026-12-31');

-- ============================================================
-- COLECCIONES
-- ============================================================
INSERT INTO colecciones (temporada_id, nombre, descripcion, es_promocional) VALUES
(1, 'Coleccion Primavera 2026', 'Nueva linea de moda primavera', FALSE),
(2, 'Coleccion Invierno 2026', 'Prendas de abrigo para el invierno boliviano', FALSE),
(3, 'Promo Escolar 2026', 'Descuentos especiales para la vuelta a clases', TRUE),
(4, 'Coleccion Limitada Invierno', 'Lanzamiento de edicion limitada', FALSE);

-- ============================================================
-- PROVEEDORES (5 proveedores)
-- ============================================================
INSERT INTO proveedores (nombre, contacto, telefono, email, direccion) VALUES
('ModaBol Textiles', 'Ing. Roberto Suarez', '(591) 3-345-1122', 'ventas@modabol.com', 'Zona Industrial, Santa Cruz'),
('WearSud Moda', 'Sra. Carmen Flores', '(591) 2-222-3344', 'contacto@wearsud.com', 'Av. Baldivia, La Paz'),
('Textiles Andinos', 'Sr. Efrain Mamani', '(591) 2-284-5566', 'info@textilesandinos.bo', 'Ciudad El Alto, La Paz'),
('Bolivia Fashion Group', 'Srta. Cecilia Rios', '(591) 3-366-7788', 'ventas@boliviafashion.bo', 'Centro, Santa Cruz'),
('Importa Ropa Internacional', 'Sr. Paolo Vargas', '(591) 4-455-0011', 'importa@ropa.com', 'Zona Central, Cochabamba');

-- ============================================================
-- PRODUCTOS (18 productos realistas)
-- ============================================================
INSERT INTO productos (nombre, descripcion, precio, categoria_id, temporada_id, coleccion_id, proveedor_id, imagen_url, modelo_3d_url, activo) VALUES
('Camiseta Basica', 'Camiseta de algodon 100%', 49.50, 1, 1, 1, 1, '/static/productos/producto_1.svg', '/static/models/prenda_casual.glb', TRUE),
('Pantalon Jeans', 'Jeans clasico de corte recto', 149.00, 2, 1, 1, 1, '/static/productos/producto_2.svg', '/static/models/prenda_casual.glb', TRUE),
('Vestido Floral', 'Vestido ligero con estampado floral', 199.50, 3, 1, 1, 2, '/static/productos/producto_3.svg', '/static/models/prenda_elegante.glb', TRUE),
('Abrigo Invierno', 'Abrigo de lana para el frio', 349.00, 4, 2, 2, 2, '/static/productos/producto_4.svg', '/static/models/prenda_deportiva.glb', TRUE),
('Chompa Escolar', 'Chompa de uniforme escolar', 89.00, 1, 3, 3, 1, '/static/productos/producto_5.svg', '/static/models/prenda_casual.glb', TRUE),
('Chaqueta de Cuero', 'Chaqueta de cuero clasica', 450.00, 5, 4, 4, 4, '/static/productos/producto_6.svg', NULL, TRUE),
('Falda Plisada', 'Falda plisada elegante', 129.00, 6, 1, 1, 2, '/static/productos/producto_7.svg', NULL, TRUE),
('Bufanda de Lana', 'Bufanda tejida de lana', 45.00, 7, 2, 2, 3, '/static/productos/producto_8.svg', NULL, TRUE),
('Camisa Formal', 'Camisa formal de vestir', 119.00, 1, 1, 1, 1, '/static/productos/producto_9.svg', NULL, TRUE),
('Pantalon Chino', 'Pantalon chino comodo y casual', 139.00, 2, 1, 1, 4, '/static/productos/producto_10.svg', NULL, TRUE),
('Vestido de Noche', 'Vestido largo de noche', 289.00, 3, 4, 4, 5, '/static/productos/producto_11.svg', NULL, TRUE),
('Sweater Oversize', 'Sueter de punto oversize', 159.00, 4, 2, 2, 3, '/static/productos/producto_12.svg', '/static/models/prenda_deportiva.glb', TRUE),
('Gorra Deportiva', 'Gorra deportiva con logo', 39.00, 7, 1, 1, 4, '/static/productos/producto_13.svg', '/static/models/prenda_casual.glb', TRUE),
('Blazer Mujer', 'Blazer sastre para mujer', 259.00, 5, 4, 4, 5, '/static/productos/producto_14.svg', NULL, TRUE),
('Falda Jeans', 'Falda de mezclilla', 119.00, 6, 1, 1, 1, '/static/productos/producto_15.svg', NULL, TRUE),
('Cinturon de Cuero', 'Cinturon de cuero genuino', 69.00, 7, 1, 1, 4, '/static/productos/producto_16.svg', NULL, TRUE),
('Campera Jeans', 'Campera de jeans con forro interior', 199.00, 5, 2, 2, 1, '/static/productos/producto_17.svg', '/static/models/prenda_elegante.glb', TRUE),
('Polo Deportivo', 'Polo deportivo de cuello', 119.00, 1, 1, 1, 5, '/static/productos/producto_18.svg', NULL, TRUE);

-- ============================================================
-- PRODUCTO_VARIANTES (46 variantes)
-- ============================================================
INSERT INTO producto_variantes (producto_id, color_id, talla_id, sku, precio_extra) VALUES
-- Camiseta Basica (1)
(1, 1, 2, 'CAM-NEG-S', 0.00), (1, 1, 3, 'CAM-NEG-M', 0.00), (1, 1, 4, 'CAM-NEG-L', 0.00),
(1, 2, 3, 'CAM-BLA-M', 0.00), (1, 2, 4, 'CAM-BLA-L', 0.00), (1, 3, 3, 'CAM-ROJ-M', 5.00),
-- Pantalon Jeans (2)
(2, 4, 3, 'PAN-AZU-M', 0.00), (2, 4, 4, 'PAN-AZU-L', 0.00), (2, 1, 4, 'PAN-NEG-L', 0.00),
(2, 5, 3, 'PAN-VER-M', 0.00), (2, 4, 2, 'PAN-AZU-S', 0.00),
-- Vestido Floral (3)
(3, 3, 3, 'VES-ROJ-M', 0.00), (3, 2, 4, 'VES-BLA-L', 0.00), (3, 4, 3, 'VES-AZU-M', 10.00),
-- Abrigo Invierno (4)
(4, 1, 4, 'ABR-NEG-L', 0.00), (4, 1, 5, 'ABR-NEG-XL', 0.00), (4, 5, 4, 'ABR-VER-L', 0.00),
-- Chompa Escolar (5)
(5, 4, 2, 'CHO-AZU-XS', 0.00), (5, 4, 3, 'CHO-AZU-M', 0.00), (5, 1, 3, 'CHO-NEG-M', 0.00),
(5, 1, 4, 'CHO-NEG-L', 0.00),
-- Chaqueta de Cuero (6)
(6, 1, 3, 'CHQ-NEG-M', 0.00), (6, 1, 4, 'CHQ-NEG-L', 0.00),
-- Falda Plisada (7)
(7, 1, 3, 'FPL-NEG-M', 0.00), (7, 6, 3, 'FPL-GRI-M', 0.00), (7, 2, 3, 'FPL-BLA-M', 0.00),
-- Bufanda de Lana (8)
(8, 3, 5, 'BUF-ROJ-U', 0.00), (8, 6, 5, 'BUF-GRI-U', 0.00),
-- Camisa Formal (9)
(9, 2, 3, 'CMF-BLA-M', 0.00), (9, 4, 3, 'CMF-AZU-M', 0.00), (9, 2, 4, 'CMF-BLA-L', 0.00),
-- Pantalon Chino (10)
(10, 7, 3, 'PCH-BEI-M', 0.00), (10, 1, 3, 'PCH-NEG-M', 0.00),
-- Vestido de Noche (11)
(11, 1, 3, 'VDN-NEG-M', 0.00), (11, 1, 4, 'VDN-NEG-L', 0.00),
-- Sweater Oversize (12)
(12, 6, 3, 'SWE-GRI-M', 0.00), (12, 8, 3, 'SWE-MAR-M', 0.00), (12, 2, 3, 'SWE-BLA-M', 0.00),
-- Gorra Deportiva (13)
(13, 1, 5, 'GOR-NEG-U', 0.00), (13, 4, 5, 'GOR-AZU-U', 0.00),
-- Blazer Mujer (14)
(14, 1, 3, 'BLA-NEG-M', 0.00), (14, 7, 3, 'BLA-BEI-M', 0.00),
-- Falda Jeans (15)
(15, 4, 3, 'FJE-AZU-M', 0.00),
-- Campera Jeans (17)
(17, 4, 3, 'CPJ-AZU-M', 0.00), (17, 4, 4, 'CPJ-AZU-L', 0.00),
-- Polo Deportivo (18)
(18, 4, 3, 'POL-AZU-M', 0.00), (18, 2, 3, 'POL-BLA-M', 0.00);

-- ============================================================
-- INVENTARIO (72+ registros con situaciones realistas: agotados,
-- stock bajo, disponibles y proximos a ingresar) en 7 sucursales
-- ============================================================

-- SUCURSAL 1 (Santa Cruz Centro) - la principal, bien surtida
INSERT INTO inventario (variante_id, sucursal_id, cantidad_disponible, cantidad_reservada, cantidad_recibida, stock_minimo) VALUES
(1,1,15,0,0,5),(2,1,12,0,0,5),(3,1,20,0,0,5),(4,1,0,0,0,5),(5,1,8,0,0,5),(6,1,3,0,0,5),          -- Camisetas (4 agotada)
(7,1,25,0,0,5),(8,1,22,0,0,5),(9,1,0,0,12,5),(10,1,14,0,0,5),(11,1,5,0,0,5),                        -- Jeans (9 agotado, proximo a ingresar)
(12,1,8,0,0,3),(13,1,9,0,0,3),(14,1,6,0,0,3),                                                         -- Vestidos
(15,1,4,0,0,3),(16,1,5,0,0,3),(17,1,0,0,0,3),                                                         -- Abrigos (17 agotado)
(18,1,16,0,0,5),(19,1,15,0,0,5),(20,1,13,0,0,5),(21,1,11,0,0,5),                                      -- Chompas
(22,1,2,0,0,3),(23,1,0,0,20,3),                                                                       -- Chaquetas (23 agotado, proximo a ingresar)
(24,1,7,0,0,3),(25,1,6,0,0,3),(26,1,5,0,0,3),                                                         -- Faldas
(27,1,30,0,0,10),(28,1,25,0,0,10),                                                                    -- Bufandas
(29,1,10,0,0,5),(30,1,8,0,0,5),(31,1,9,0,0,5),                                                         -- Camisas
(32,1,11,0,0,5),(33,1,7,0,0,5),                                                                       -- Chinos
(34,1,4,0,0,3),(35,1,3,0,0,3),                                                                        -- Vestidos de noche
(36,1,3,0,0,3),(37,1,2,0,0,3),(38,1,0,0,8,3),                                                         -- Sweaters (38 agotado)
(39,1,0,0,0,5),(40,1,6,0,0,5),                                                                        -- Gorras (39 agotada)
(41,1,3,0,0,3),(42,1,2,0,0,3),                                                                        -- Blazers (42 stock bajo)
(43,1,0,0,5,3),                                                                                       -- Falda jeans (agotada, proxima a ingresar)
(44,1,5,0,0,3),(45,1,4,0,0,3),                                                                        -- Camperas
(46,1,12,0,0,5),(47,1,10,0,0,5);                                                                      -- Polos

-- SUCURSAL 2 (Santa Cruz Ventura)
INSERT INTO inventario (variante_id, sucursal_id, cantidad_disponible, cantidad_reservada, cantidad_recibida, stock_minimo) VALUES
(1,2,8,0,0,5),(2,2,6,0,0,5),(3,2,7,0,0,5),(4,2,4,0,0,5),(5,2,2,0,0,5),(6,2,1,0,0,5),
(7,2,12,0,0,5),(8,2,11,0,0,5),(9,2,5,0,0,5),(10,2,7,0,0,5),(11,2,3,0,0,5),
(12,2,3,0,0,3),(13,2,4,0,0,3),(14,2,2,0,0,3),
(15,2,2,0,0,3),(16,2,3,0,0,3),(17,2,0,0,0,3),
(18,2,8,0,0,5),(19,2,7,0,0,5),(20,2,6,0,0,5),(21,2,5,0,0,5),
(22,2,1,0,0,3),(23,2,1,0,0,3),
(24,2,4,0,0,3),(25,2,3,0,0,3),(26,2,3,0,0,3),
(27,2,20,0,0,10),(28,2,18,0,0,10),
(29,2,6,0,0,5),(30,2,5,0,0,5),(31,2,6,0,0,5),
(32,2,7,0,0,5),(33,2,5,0,0,5),
(34,2,2,0,0,3),(35,2,2,0,0,3),
(36,2,2,0,0,3),(37,2,1,0,0,3),(38,2,1,0,0,3),
(39,2,0,0,0,5),(40,2,4,0,0,5),
(41,2,2,0,0,3),(42,2,1,0,0,3),
(43,2,1,0,0,3),
(44,2,3,0,0,3),(45,2,3,0,0,3),
(46,2,8,0,0,5),(47,2,7,0,0,5);

-- SUCURSAL 3 (La Paz El Prado)
INSERT INTO inventario (variante_id, sucursal_id, cantidad_disponible, cantidad_reservada, cantidad_recibida, stock_minimo) VALUES
(1,3,12,0,0,5),(2,3,10,0,0,5),(3,3,11,0,0,5),(4,3,6,0,0,5),(5,3,4,0,0,5),(6,3,3,0,0,5),
(7,3,14,0,0,5),(8,3,13,0,0,5),(9,3,7,0,0,5),(10,3,6,0,0,5),
(12,3,5,0,0,3),(13,3,6,0,0,3),(14,3,4,0,0,3),
(15,3,2,0,0,3),(16,3,3,0,0,3),(17,3,1,0,0,3),
(18,3,9,0,0,5),(19,3,8,0,0,5),(20,3,8,0,0,5),(21,3,6,0,0,5),
(22,3,2,0,0,3),
(24,3,5,0,0,3),(25,3,4,0,0,3),(26,3,4,0,0,3),
(27,3,22,0,0,10),(28,3,20,0,0,10),
(29,3,8,0,0,5),(30,3,7,0,0,5),(31,3,7,0,0,5),
(32,3,8,0,0,5),(33,3,6,0,0,5),
(36,3,3,0,0,3),(37,3,2,0,0,3),(38,3,2,0,0,3),
(39,3,1,0,0,5),(40,3,5,0,0,5),
(43,3,2,0,0,3),
(46,3,9,0,0,5),(47,3,8,0,0,5);

-- SUCURSAL 4 (Cochabamba Recoleta)
INSERT INTO inventario (variante_id, sucursal_id, cantidad_disponible, cantidad_reservada, cantidad_recibida, stock_minimo) VALUES
(1,4,8,0,0,5),(2,4,6,0,0,5),(3,4,7,0,0,5),(4,4,3,0,0,5),(5,4,2,0,0,5),
(7,4,9,0,0,5),(8,4,8,0,0,5),(9,4,4,0,0,5),(10,4,5,0,0,5),
(12,4,3,0,0,3),(13,4,4,0,0,3),(14,4,3,0,0,3),
(15,4,2,0,0,3),(16,4,2,0,0,3),
(18,4,6,0,0,5),(19,4,5,0,0,5),(20,4,5,0,0,5),(21,4,4,0,0,5),
(24,4,3,0,0,3),(25,4,3,0,0,3),
(27,4,15,0,0,10),(28,4,13,0,0,10),
(29,4,5,0,0,5),(30,4,4,0,0,5),(31,4,5,0,0,5),
(32,4,5,0,0,5),(33,4,4,0,0,5),
(36,4,2,0,0,3),(38,4,1,0,0,3),
(40,4,3,0,0,5),
(46,4,6,0,0,5),(47,4,5,0,0,5);

-- SUCURSAL 5 (Tarija Centro) - sucursal con stock bajo/agotado
INSERT INTO inventario (variante_id, sucursal_id, cantidad_disponible, cantidad_reservada, cantidad_recibida, stock_minimo) VALUES
(1,5,6,0,0,5),(2,5,5,0,0,5),(3,5,5,0,0,5),(4,5,2,0,0,5),(5,5,1,0,0,5),
(7,5,7,0,0,5),(8,5,6,0,0,5),(9,5,0,0,3,5),(10,5,4,0,0,5),
(12,5,2,0,0,3),(13,5,3,0,0,3),
(15,5,1,0,0,3),(16,5,2,0,0,3),
(18,5,4,0,0,5),(19,5,4,0,0,5),(20,5,3,0,0,5),(21,5,3,0,0,5),
(27,5,12,0,0,10),(28,5,11,0,0,10),
(29,5,4,0,0,5),(30,5,3,0,0,5),
(32,5,4,0,0,5),
(36,5,1,0,0,3),(38,5,1,0,0,3),
(46,5,5,0,0,5),(47,5,4,0,0,5);

-- SUCURSAL 6 (Sucre Plaza)
INSERT INTO inventario (variante_id, sucursal_id, cantidad_disponible, cantidad_reservada, cantidad_recibida, stock_minimo) VALUES
(1,6,5,0,0,5),(2,6,4,0,0,5),(3,6,4,0,0,5),(4,6,2,0,0,5),
(7,6,6,0,0,5),(8,6,5,0,0,5),(10,6,3,0,0,5),
(12,6,2,0,0,3),(13,6,2,0,0,3),
(18,6,3,0,0,5),(19,6,3,0,0,5),(20,6,2,0,0,5),
(27,6,10,0,0,10),(28,6,9,0,0,10),
(29,6,3,0,0,5),
(46,6,4,0,0,5);

-- SUCURSAL 7 (El Alto 16 de Julio)
INSERT INTO inventario (variante_id, sucursal_id, cantidad_disponible, cantidad_reservada, cantidad_recibida, stock_minimo) VALUES
(1,7,7,0,0,5),(2,7,5,0,0,5),(3,7,6,0,0,5),(4,7,3,0,0,5),
(7,7,6,0,0,5),(8,7,5,0,0,5),(10,7,3,0,0,5),
(18,7,5,0,0,5),(19,7,4,0,0,5),(20,7,4,0,0,5),(21,7,3,0,0,5),
(27,7,15,0,0,10),(28,7,13,0,0,10),
(44,7,3,0,0,3),(45,7,2,0,0,3),
(46,7,6,0,0,5),(47,7,5,0,0,5);

-- ============================================================
-- RESERVAS (10 reservas en distintos estados)
-- NOTA: Como los triggers están deshabilitados, los valores de
-- inventario ya reflejan el estado actual. Las cantidades reservadas
-- aquí registran las reservas vigentes.
-- ============================================================
-- Reserva 1: Laura - Santa Cruz Centro - pendiente
INSERT INTO reservas (usuario_id, sucursal_id, fecha_reserva, hora_atencion, estado, fecha_creacion) VALUES
(6, 1, '2026-09-05', '15:00:00', 'pendiente', '2026-09-01 10:00:00');
-- Reserva 2: Pedro - Santa Cruz Centro - preparada (listo para atender)
INSERT INTO reservas (usuario_id, sucursal_id, fecha_reserva, hora_atencion, estado, fecha_creacion) VALUES
(7, 1, '2026-09-04', '11:30:00', 'preparada', '2026-09-01 09:00:00');
-- Reserva 3: Sofia - La Paz El Prado - pendiente
INSERT INTO reservas (usuario_id, sucursal_id, fecha_reserva, hora_atencion, estado, fecha_creacion) VALUES
(8, 3, '2026-09-06', '10:00:00', 'pendiente', '2026-09-02 14:00:00');
-- Reserva 4: Diego - Santa Cruz Ventura - completada (historial)
INSERT INTO reservas (usuario_id, sucursal_id, fecha_reserva, hora_atencion, estado, fecha_creacion) VALUES
(9, 2, '2026-08-20', '16:00:00', 'completada', '2026-08-18 11:00:00');
-- Reserva 5: Nestor - Cochabamba - cancelada (cliente no asistio)
INSERT INTO reservas (usuario_id, sucursal_id, fecha_reserva, hora_atencion, estado, fecha_creacion) VALUES
(10, 4, '2026-08-25', '12:00:00', 'cancelada', '2026-08-24 09:30:00');
-- Reserva 6: Camila - La Paz - preparada
INSERT INTO reservas (usuario_id, sucursal_id, fecha_reserva, hora_atencion, estado, fecha_creacion) VALUES
(11, 3, '2026-09-07', '17:00:00', 'preparada', '2026-09-03 10:00:00');
-- Reserva 7: Rodrigo - Santa Cruz Centro - pendiente (multiprenda)
INSERT INTO reservas (usuario_id, sucursal_id, fecha_reserva, hora_atencion, estado, fecha_creacion) VALUES
(12, 1, '2026-09-08', '09:30:00', 'pendiente', '2026-09-03 15:00:00');
-- Reserva 8: Valentina - El Alto - completada
INSERT INTO reservas (usuario_id, sucursal_id, fecha_reserva, hora_atencion, estado, fecha_creacion) VALUES
(13, 7, '2026-08-22', '14:00:00', 'completada', '2026-08-20 12:00:00');
-- Reserva 9: Miguel - Tarija - pendiente
INSERT INTO reservas (usuario_id, sucursal_id, fecha_reserva, hora_atencion, estado, fecha_creacion) VALUES
(14, 5, '2026-09-10', '18:00:00', 'pendiente', '2026-09-04 08:00:00');
-- Reserva 10: Fernanda - Sucre - preparada
INSERT INTO reservas (usuario_id, sucursal_id, fecha_reserva, hora_atencion, estado, fecha_creacion) VALUES
(15, 6, '2026-09-09', '11:00:00', 'preparada', '2026-09-04 09:00:00');

-- ============================================================
-- RESERVA_ITEMS (detalle - las cantidades reservadas ya estan
-- reflejadas en el inventario de forma manual)
-- ============================================================
-- Reserva 1 (Laura): Camiseta M (2), Pantalon Azul M (7)
INSERT INTO reserva_items (reserva_id, variante_id, cantidad) VALUES (1,2,1),(1,7,2);
-- Reserva 2 (Pedro): Jeans Azul L (8), Abrigo Negro L (15)
INSERT INTO reserva_items (reserva_id, variante_id, cantidad) VALUES (2,8,1),(2,15,1);
-- Reserva 3 (Sofia): Vestido Rojo M (12), Chompa Azul M (19)
INSERT INTO reserva_items (reserva_id, variante_id, cantidad) VALUES (3,12,1),(3,19,1);
-- Reserva 4 (Diego): Chaqueta Negro M (22), Camisa Blanca M (29) - completada
INSERT INTO reserva_items (reserva_id, variante_id, cantidad) VALUES (4,22,1),(4,29,1),(4,13,1);
-- Reserva 5 (Nestor): Camiseta Blanca L (5) - cancelada
INSERT INTO reserva_items (reserva_id, variante_id, cantidad) VALUES (5,5,2);
-- Reserva 6 (Camila): Falda Negra M (24), Sweater Gris M (36) - preparada
INSERT INTO reserva_items (reserva_id, variante_id, cantidad) VALUES (6,24,1),(6,36,1);
-- Reserva 7 (Rodrigo): Polo Azul M (46), Pantalon Negro L (9) - pendiente
INSERT INTO reserva_items (reserva_id, variante_id, cantidad) VALUES (7,46,1),(7,9,1),(7,3,1);
-- Reserva 8 (Valentina): Chompa Azul M (19), Bufanda Roja (27) - completada
INSERT INTO reserva_items (reserva_id, variante_id, cantidad) VALUES (8,19,2),(8,27,1);
-- Reserva 9 (Miguel): Abrigo Verde L (17) - pendiente
INSERT INTO reserva_items (reserva_id, variante_id, cantidad) VALUES (9,17,1);
-- Reserva 10 (Fernanda): Blazer Negro M (41), Falda Plisada Negra (24) - preparada
INSERT INTO reserva_items (reserva_id, variante_id, cantidad) VALUES (10,41,1),(10,24,1);

-- ============================================================
-- PEDIDOS (14 ventas realistas: digitales y presenciales)
-- ============================================================
-- Pedidos digitales (web/movil) - con pasarela
INSERT INTO pedidos (usuario_id, sucursal_id, fecha_pedido, total, metodo_compra, estado, tipo_pago) VALUES
(6, 1, '2026-08-10 14:30:00', 447.00, 'digital', 'entregado', 'tarjeta_credito'),
(7, 1, '2026-08-12 10:15:00', 199.50, 'digital', 'entregado', 'tarjeta_debito'),
(8, 3, '2026-08-15 18:45:00', 598.00, 'digital', 'pagado', 'qr'),
(9, 2, '2026-08-18 09:00:00', 288.00, 'digital', 'enviado', 'transferencia'),
(10, 4, '2026-08-21 20:10:00', 89.00, 'digital', 'pagado', 'tarjeta_credito'),
(11, 3, '2026-08-24 11:30:00', 450.00, 'digital', 'entregado', 'qr'),
(12, 1, '2026-08-27 16:20:00', 159.00, 'digital', 'pagado', 'tarjeta_debito');

-- Pedidos presenciales (caja) - con pago en punto de venta
INSERT INTO pedidos (usuario_id, sucursal_id, fecha_pedido, total, metodo_compra, estado, tipo_pago) VALUES
(6, 1, '2026-08-28 12:00:00', 199.50, 'presencial', 'pagado', 'tarjeta_debito'),
(7, 1, '2026-08-29 13:10:00', 450.00, 'presencial', 'pagado', 'efectivo'),
(9, 2, '2026-08-30 15:30:00', 149.00, 'presencial', 'pagado', 'tarjeta_credito'),
(13, 7, '2026-08-31 11:00:00', 449.00, 'presencial', 'pagado', 'qr'),
(8, 3, '2026-08-12 17:00:00', 258.50, 'presencial', 'pagado', 'efectivo'),
(14, 5, '2026-09-01 10:30:00', 119.00, 'presencial', 'pagado', 'transferencia'),
(15, 6, '2026-09-02 09:00:00', 259.00, 'presencial', 'pagado', 'tarjeta_debito');

-- ============================================================
-- PEDIDO_ITEMS (detalle de pedidos)
-- ============================================================
-- Pedido 1 (digital Laura): Camiseta Basica L (3) x2, Pantalon Jeans L (8) x2
INSERT INTO pedido_items (pedido_id, variante_id, cantidad, precio_unitario, subtotal) VALUES
(1,3,2,49.50,99.00),(1,8,2,174.00,348.00);
-- Pedido 2 (digital Pedro): Vestido Floral M (12) x1
INSERT INTO pedido_items (pedido_id, variante_id, cantidad, precio_unitario, subtotal) VALUES
(2,12,1,199.50,199.50);
-- Pedido 3 (digital Sofia): Abrigo Verde L (17) x2
INSERT INTO pedido_items (pedido_id, variante_id, cantidad, precio_unitario, subtotal) VALUES
(3,17,2,299.00,598.00);
-- Pedido 4 (digital Diego): Chompa Negra L (21) x2, Polo Azul M (46) x1
INSERT INTO pedido_items (pedido_id, variante_id, cantidad, precio_unitario, subtotal) VALUES
(4,21,2,89.00,178.00),(4,46,1,110.00,110.00);
-- Pedido 5 (digital Nestor): Chompa Azul M (19) x1
INSERT INTO pedido_items (pedido_id, variante_id, cantidad, precio_unitario, subtotal) VALUES
(5,19,1,89.00,89.00);
-- Pedido 6 (digital Camila): Chaqueta Cuero L (23) x1
INSERT INTO pedido_items (pedido_id, variante_id, cantidad, precio_unitario, subtotal) VALUES
(6,23,1,450.00,450.00);
-- Pedido 7 (digital Rodrigo): Sweater Marron M (37) x1
INSERT INTO pedido_items (pedido_id, variante_id, cantidad, precio_unitario, subtotal) VALUES
(7,37,1,159.00,159.00);
-- Pedido 8 (presencial Laura suc1): Vestido Azul M (14) x1
INSERT INTO pedido_items (pedido_id, variante_id, cantidad, precio_unitario, subtotal) VALUES
(8,14,1,199.50,199.50);
-- Pedido 9 (presencial Pedro suc1): Chaqueta Cuero M (22) x1
INSERT INTO pedido_items (pedido_id, variante_id, cantidad, precio_unitario, subtotal) VALUES
(9,22,1,450.00,450.00);
-- Pedido 10 (presencial Diego suc2): Pantalon Jeans M (7) x1
INSERT INTO pedido_items (pedido_id, variante_id, cantidad, precio_unitario, subtotal) VALUES
(10,7,1,149.00,149.00);
-- Pedido 11 (presencial Valentina suc7): Chompa Azul M (19) x2, Bufanda Roja (27) x1
INSERT INTO pedido_items (pedido_id, variante_id, cantidad, precio_unitario, subtotal) VALUES
(11,19,2,89.00,178.00),(11,27,1,45.00,45.00);
-- Pedido 12 (presencial Sofia suc3): Camiseta Blanca L (5) x1, Falda Gris M (25) x1
INSERT INTO pedido_items (pedido_id, variante_id, cantidad, precio_unitario, subtotal) VALUES
(12,5,1,54.50,54.50),(12,25,1,204.00,204.00);
-- Pedido 13 (presencial Miguel suc5): Camisa Azul M (30) x1
INSERT INTO pedido_items (pedido_id, variante_id, cantidad, precio_unitario, subtotal) VALUES
(13,30,1,119.00,119.00);
-- Pedido 14 (presencial Fernanda suc6): Blazer Beige M (42) x1
INSERT INTO pedido_items (pedido_id, variante_id, cantidad, precio_unitario, subtotal) VALUES
(14,42,1,259.00,259.00);

-- ============================================================
-- PAGOS (14 pagos - pasarela para digitales, punto de venta para presenciales)
-- ============================================================
INSERT INTO pagos (pedido_id, monto, proveedor_pago, transaccion_id, estado, fecha_pago) VALUES
(1, 447.00, 'STRIPE', 'TXN-STRIPE-0001', 'aprobado', '2026-08-10 14:31:00'),
(2, 199.50, 'PAYPAL', 'TXN-PAYPAL-0002', 'aprobado', '2026-08-12 10:16:00'),
(3, 598.00, 'LIBELULA', 'TXN-LIBELULA-0003', 'aprobado', '2026-08-15 18:46:00'),
(4, 288.00, 'STRIPE', 'TXN-STRIPE-0004', 'aprobado', '2026-08-18 09:01:00'),
(5, 89.00, 'PAYPAL', 'TXN-PAYPAL-0005', 'aprobado', '2026-08-21 20:11:00'),
(6, 450.00, 'LIBELULA', 'TXN-LIBELULA-0006', 'aprobado', '2026-08-24 11:31:00'),
(7, 159.00, 'STRIPE', 'TXN-STRIPE-0007', 'aprobado', '2026-08-27 16:21:00'),
(8, 199.50, 'Punto de Venta', 'TXN-CAJA-1', 'aprobado', '2026-08-28 12:01:00'),
(9, 450.00, 'Punto de Venta', 'TXN-CAJA-2', 'aprobado', '2026-08-29 13:11:00'),
(10, 149.00, 'Punto de Venta', 'TXN-CAJA-3', 'aprobado', '2026-08-30 15:31:00'),
(11, 449.00, 'Punto de Venta', 'TXN-CAJA-4', 'aprobado', '2026-08-31 11:01:00'),
(12, 258.50, 'Punto de Venta', 'TXN-CAJA-5', 'aprobado', '2026-08-12 17:01:00'),
(13, 119.00, 'Punto de Venta', 'TXN-CAJA-6', 'aprobado', '2026-09-01 10:31:00'),
(14, 259.00, 'Punto de Venta', 'TXN-CAJA-7', 'aprobado', '2026-09-02 09:01:00');

-- ============================================================
-- MOVIMIENTOS_INVENTARIO (historial consistente de entradas,
-- reservas, ventas y devoluciones)
-- ============================================================
-- Entradas de proveedores (stock inicial)
INSERT INTO movimientos_inventario (variante_id, sucursal_id, tipo_movimiento, cantidad, referencia_id, observacion) VALUES
(1,1,'entrada',30,NULL,'Recepcion inicial de stock'),
(2,1,'entrada',30,NULL,'Recepcion inicial de stock'),
(7,1,'entrada',40,NULL,'Recepcion inicial de stock'),
(8,1,'entrada',40,NULL,'Recepcion inicial de stock'),
(12,1,'entrada',15,NULL,'Recepcion inicial de stock'),
(3,2,'entrada',15,NULL,'Recepcion inicial de stock'),
(7,2,'entrada',20,NULL,'Recepcion inicial de stock'),
(1,3,'entrada',25,NULL,'Recepcion inicial de stock'),
(7,3,'entrada',30,NULL,'Recepcion inicial de stock'),
(12,4,'entrada',12,NULL,'Recepcion inicial de stock'),
(1,5,'entrada',15,NULL,'Recepcion inicial de stock'),
(18,1,'entrada',25,NULL,'Recepcion de chompas escolares'),
(27,1,'entrada',50,NULL,'Recepcion de bufandas de lana');

-- Reservas vigentes (se reflejan como reserva)
INSERT INTO movimientos_inventario (variante_id, sucursal_id, tipo_movimiento, cantidad, referencia_id, observacion) VALUES
(2,1,'reserva',1,1,'Reserva Laura Vargas'),
(7,1,'reserva',2,1,'Reserva Laura Vargas'),
(8,1,'reserva',1,2,'Reserva Pedro Siles'),
(15,1,'reserva',1,2,'Reserva Pedro Siles'),
(12,3,'reserva',1,3,'Reserva Sofia Mendoza'),
(19,3,'reserva',1,3,'Reserva Sofia Mendoza'),
(24,3,'reserva',1,6,'Reserva Camila Delgado'),
(36,3,'reserva',1,6,'Reserva Camila Delgado'),
(46,1,'reserva',1,7,'Reserva Rodrigo Quispe'),
(3,1,'reserva',1,7,'Reserva Rodrigo Quispe'),
(17,5,'reserva',1,9,'Reserva Miguel Campos'),
(41,6,'reserva',1,10,'Reserva Fernanda Ortiz'),
(24,6,'reserva',1,10,'Reserva Fernanda Ortiz');

-- Ventas (descuento de stock)
INSERT INTO movimientos_inventario (variante_id, sucursal_id, tipo_movimiento, cantidad, referencia_id, observacion) VALUES
(3,1,'venta',-2,1,'Venta digital Laura'),
(8,1,'venta',-2,1,'Venta digital Laura'),
(12,1,'venta',-1,2,'Venta digital Pedro'),
(17,3,'venta',-2,3,'Venta digital Sofia'),
(21,2,'venta',-2,4,'Venta digital Diego'),
(46,2,'venta',-1,4,'Venta digital Diego'),
(19,4,'venta',-1,5,'Venta digital Nestor'),
(23,3,'venta',-1,6,'Venta digital Camila'),
(37,1,'venta',-1,7,'Venta digital Rodrigo'),
(14,1,'venta',-1,8,'Venta presencial suc Centro'),
(22,1,'venta',-1,9,'Venta presencial suc Centro'),
(7,2,'venta',-1,10,'Venta presencial suc Ventura'),
(19,7,'venta',-2,11,'Venta presencial El Alto'),
(27,7,'venta',-1,11,'Venta presencial El Alto'),
(5,3,'venta',-1,12,'Venta presencial La Paz'),
(25,3,'venta',-1,12,'Venta presencial La Paz'),
(30,5,'venta',-1,13,'Venta presencial Tarija'),
(42,6,'venta',-1,14,'Venta presencial Sucre');

-- Devolución (ejemplo: Fernanda devolvió un polo)
INSERT INTO movimientos_inventario (variante_id, sucursal_id, tipo_movimiento, cantidad, referencia_id, observacion) VALUES
(46,6,'devolucion',1,NULL,'Devolucion de polo por cambio de talla');

-- ============================================================
-- RE-HABILITAR TRIGGERS
-- ============================================================
ALTER TABLE reservas           ENABLE TRIGGER ALL;
ALTER TABLE reserva_items      ENABLE TRIGGER ALL;
ALTER TABLE pedidos            ENABLE TRIGGER ALL;
ALTER TABLE pedido_items       ENABLE TRIGGER ALL;
ALTER TABLE producto_variantes ENABLE TRIGGER ALL;

-- ============================================================
-- VERIFICACIÓN RÁPIDA
-- ============================================================
\echo '============================================'
\echo ' POBLACIÓN COMPLETADA - RESUMEN DE REGISTROS'
\echo '============================================'
SELECT 'ciudades' AS tabla, COUNT(*) FROM ciudades
UNION ALL SELECT 'sucursales', COUNT(*) FROM sucursales
UNION ALL SELECT 'usuarios', COUNT(*) FROM usuarios
UNION ALL SELECT 'categorias', COUNT(*) FROM categorias
UNION ALL SELECT 'colores', COUNT(*) FROM colores
UNION ALL SELECT 'tallas', COUNT(*) FROM tallas
UNION ALL SELECT 'temporadas', COUNT(*) FROM temporadas
UNION ALL SELECT 'colecciones', COUNT(*) FROM colecciones
UNION ALL SELECT 'proveedores', COUNT(*) FROM proveedores
UNION ALL SELECT 'productos', COUNT(*) FROM productos
UNION ALL SELECT 'producto_variantes', COUNT(*) FROM producto_variantes
UNION ALL SELECT 'inventario', COUNT(*) FROM inventario
UNION ALL SELECT 'movimientos_inventario', COUNT(*) FROM movimientos_inventario
UNION ALL SELECT 'reservas', COUNT(*) FROM reservas
UNION ALL SELECT 'reserva_items', COUNT(*) FROM reserva_items
UNION ALL SELECT 'pedidos', COUNT(*) FROM pedidos
UNION ALL SELECT 'pedido_items', COUNT(*) FROM pedido_items
UNION ALL SELECT 'pagos', COUNT(*) FROM pagos
ORDER BY tabla;
