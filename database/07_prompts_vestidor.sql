-- ============================================================
-- SCRIPT 7: PROMPTS DEL VESTIDOR VIRTUAL PARA EL CATALOGO (CU-07)
-- Sistemas II - Plataforma Inteligente de Comercio Electronico
-- Base de datos: PostgreSQL
--
-- Que problema corrige:
-- El boton "Probar con camara" del detalle de producto esta gateado por
-- `imagen_url AND prompt_vestidor`. La columna existia pero solo 7 de los 19
-- productos con imagen real la tenian cargada, asi que en 12 productos el
-- boton no aparecia: el endpoint /virtual/token funcionaba, pero no habia
-- forma de abrir el probador.
--
-- El modelo `lucy-vton-latest` NO interpreta la foto del producto por si
-- solo. Recibe la imagen de la prenda mas un texto que la describe. Sin el
-- texto no hay try-on.
--
-- Convencion del prompt (segun la guia oficial de Decart para VTON 3.5):
--   - Verbo: "Substitute" para reemplazar una prenda que la persona ya
--     trae puesta. Decart recomienda las frases "Substitute the upper body
--     garment / lower body garment / outfit / hat with <descripcion>".
--     La region debe nombrarse asi: tops, camisas, polos, sweaters,
--     camperas, abrigos, chaquetas y blazers son "upper body garment";
--     pantalones, jeans, chinos y faldas son "lower body garment";
--     vestidos completos (solo vestido) son "outfit" y la gorra es "hat".
--   - "Add <descripcion> to the outfit" para accesorios que se suman por
--     encima (bufanda, cinturon), indicando donde va.
--   - Para prendas con cierre o botones, indicar si van abiertas o cerradas;
--     si van abiertas, describir la capa base visible. No inventar detalles
--     ni logos que la imagen no muestre.
--   - Entre 20 y 30 palabras, con color, material, textura, patron y ajuste.
--
-- Este archivo es la unica fuente de verdad del prompt de cada prenda:
-- los UPDATE de abajo escriben el valor final en cada corrida (idempotente,
-- porque reescribir el mismo prompt sobre el mismo producto no cambia nada).
-- Solo se tocan los productos que tienen imagen: sin foto no hay prenda que
-- enviar al modelo, asi que un prompt solo no habilita nada.
-- ============================================================

-- ------------------------------------------------------------
-- Los 18 productos del catalogo, matcheados por nombre (unicos en
-- estos datos). Se reescriben en cada corrida para que este archivo sea
-- la unica fuente de verdad; los productos de prueba sin imagen no se
-- tocan, porque sin imagen no hay try-on posible.
--
-- Los 7 primeros ya estaban cargados en la base de desarrollo pero
-- nunca estuvieron en ningun .sql, asi que una instalacion limpia
-- arrancaba con 11 de 18. Van todos juntos, normalizados al patron
-- documentado de VTON 3.5 ("Substitute the upper/lower body garment").
-- ------------------------------------------------------------
UPDATE productos p
SET prompt_vestidor = v.prompt
FROM (VALUES
    ('Camiseta Basica',
     'Substitute the upper body garment with a plain white crew neck cotton t-shirt with a regular fit'),
    ('Pantalon Jeans',
     'Substitute the lower body garment with classic straight cut blue denim jeans with a mid rise, five pocket design and slight fading on the thighs'),
    ('Vestido Floral',
     'Substitute the outfit with a long floral summer dress with thin straps and a flowy skirt'),
    ('Abrigo Invierno',
     'Substitute the upper body garment with a long black wool winter coat with a wide collar'),
    ('Chompa Escolar',
     'Substitute the upper body garment with a navy blue school uniform sweatshirt with long sleeves, a ribbed hem and a small embroidered crest on the chest'),
    ('Chaqueta de Cuero',
     'Substitute the upper body garment with a classic black leather biker jacket with silver zippers, notched lapels and a fitted slim cut'),
    ('Falda Plisada',
     'Substitute the lower body garment with an elegant knee length pleated midi skirt in light beige with fine knife pleats and a high waist'),
    ('Bufanda de Lana',
     'Add a knitted wool scarf around the person''s neck in oatmeal beige with a chunky cable knit texture and fringed ends'),
    ('Camisa Formal',
     'Substitute the upper body garment with a crisp white formal dress shirt with thin pinstripes, a spread collar and a tailored slim fit'),
    ('Pantalon Chino',
     'Substitute the lower body garment with khaki beige chino trousers with a slim tapered leg, clean flat front and slim belt loops'),
    ('Vestido de Noche',
     'Substitute the outfit with a long black evening gown with a deep v neckline, side slit and a smooth satin fabric'),
    ('Sweater Oversize',
     'Substitute the upper body garment with an oversized cream cable knit sweater with dropped shoulders, a loose boxy fit and ribbed cuffs'),
    ('Gorra Deportiva',
     'Substitute the hat with a plain black baseball cap worn facing forward'),
    ('Blazer Mujer',
     'Substitute the upper body garment with a fitted dark navy women blazer worn over a white shirt'),
    ('Falda Jeans',
     'Substitute the lower body garment with a mid-wash blue denim midi skirt with a straight cut'),
    ('Cinturon de Cuero',
     'Add a genuine brown leather belt around the person''s waist with a matte brushed silver buckle and a simple rectangular shape'),
    ('Campera Jeans',
     'Substitute the upper body garment with a light wash denim trucker jacket with a button front chest pockets and a sherpa lined collar'),
    ('Polo Deportivo',
     'Substitute the upper body garment with a short sleeve polo shirt in solid navy blue')
) AS v(nombre, prompt)
WHERE p.nombre = v.nombre
  AND COALESCE(p.imagen_url, '') <> '';

-- ------------------------------------------------------------
-- El producto de pruebas E2E con foto subida (id 44) va aparte y
-- se matchea por imagen_url, no por nombre: se llama 'E2E Producto'
-- igual que otros 24 registros, asi que el nombre no lo
-- identifica. En una base recien creada este UPDATE no toca nada,
-- porque 02_poblacion.sql no lo inserta.
-- ------------------------------------------------------------
UPDATE productos
SET prompt_vestidor =
    'Substitute the upper body garment with a plain heather grey cotton t-shirt with a classic crew neck and a regular relaxed fit'
WHERE imagen_url = '/static/uploads/producto_44.jpg';

-- ------------------------------------------------------------
-- Cobertura final. Se espera 19 con probador sobre 19 con imagen
-- real; los productos de prueba sin foto siguen en 0 y no se
-- tocan, porque sin imagen no hay try-on posible.
-- ------------------------------------------------------------
SELECT
    count(*) FILTER (WHERE COALESCE(imagen_url, '') <> '')                    AS con_imagen,
    count(*) FILTER (
        WHERE COALESCE(imagen_url, '') <> ''
          AND COALESCE(prompt_vestidor, '') <> '')                           AS con_probador,
    count(*) FILTER (
        WHERE COALESCE(imagen_url, '') <> ''
          AND COALESCE(prompt_vestidor, '') = '')                             AS sin_prompt,
    count(*) FILTER (
        WHERE COALESCE(imagen_url, '') = ''
          AND COALESCE(prompt_vestidor, '') <> '')                           AS sin_imagen_con_prompt
FROM productos;