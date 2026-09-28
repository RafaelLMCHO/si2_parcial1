-- ============================================================
-- SCRIPT 6: PROMPT DEL VESTIDOR VIRTUAL (CU-07)
-- Sistemas II - Plataforma Inteligente de Comercio Electronico
-- Base de datos: PostgreSQL
--
-- Problema que corrige:
-- El probador con camara (Decart realtime, modelo lucy-vton-latest)
-- necesita que cada producto tenga escrito como describir la prenda.
-- El modelo no interpreta la imagen por si sola: recibe un texto con el
-- patron "Substitute the current top with ..." o "Add ... to the
-- person's head", con color, material, textura, patron y ajuste.
--
-- Sin esta columna el endpoint /virtual/token funciona pero ningun
-- producto puede vestirse.
--
-- Convencion del prompt (segun la guia de Decart para VTON 3.5):
--   - "Substitute the current top with ..." reemplaza una prenda existente.
--   - "Add ... to the person's head" agrega algo que no se esta usando.
--   - Entre 20 y 30 palabras, con detalle concreto.
--   - Ej.: "Substitute the current top with a bright red hoodie with an
--          oversized casual fit"
--
-- Se deja NULL cuando el producto todavia no tiene prompt: el boton
-- "Probar con camara" no se muestra en ese caso.
-- ============================================================

ALTER TABLE productos
    ADD COLUMN IF NOT EXISTS prompt_vestidor TEXT NULL;

COMMENT ON COLUMN productos.prompt_vestidor IS
    'Prompt en ingles para el probador virtual con camara (Decart lucy-vton-latest). NULL = producto sin probador.';
