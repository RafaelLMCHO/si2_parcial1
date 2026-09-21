/**
 * Carga imágenes de todos los productos en lote.
 *
 * Uso:
 *   node scripts/subir_imagenes_productos.mjs --folder <carpeta> [opciones]
 *
 * Opciones:
 *   --folder  ruta con las imágenes (obligatorio)
 *   --api     base de la API (defecto http://localhost:8000/api/v1)
 *   --email   admin (defecto admin@fashionstore.bo)
 *   --pass    contraseña (defecto admin123)
 *
 * Nombre de archivos aceptados (para asociar a cada producto):
 *   producto_<id>.<ext>   → ej. producto_7.png
 *   <id>.<ext>            → ej. 7.jpg
 *   <id>_<texto>.<ext>    → ej. 7_falda_plisada.webp
 *   <nombre_producto>.<ext> → ej. falda_plisada.jpg (sin tildes, espacios → _)
 *
 * También copia las imágenes a una subcarpeta "lista/" opcional? No: solo sube.
 * Sin archivo para un producto, ese producto queda sin cambio.
 */
import { readdirSync, readFileSync } from 'fs';
import { join, extname, basename } from 'path';

const NORMA = (s) =>
  s
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');

const PRODUCTOS = [
  [1, 'Camiseta Basica'],
  [2, 'Pantalon Jeans'],
  [3, 'Vestido Floral'],
  [4, 'Abrigo Invierno'],
  [5, 'Chompa Escolar'],
  [6, 'Chaqueta de Cuero'],
  [7, 'Falda Plisada'],
  [8, 'Bufanda de Lana'],
  [9, 'Camisa Formal'],
  [10, 'Pantalon Chino'],
  [11, 'Vestido de Noche'],
  [12, 'Sweater Oversize'],
  [13, 'Gorra Deportiva'],
  [14, 'Blazer Mujer'],
  [15, 'Falda Jeans'],
  [16, 'Cinturon de Cuero'],
  [17, 'Campera Jeans'],
  [18, 'Polo Deportivo'],
];

const MIME = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
};

function args() {
  const a = process.argv.slice(2);
  const get = (k, d) => {
    const i = a.indexOf(k);
    return i >= 0 && a[i + 1] ? a[i + 1] : d;
  };
  return {
    folder: get('--folder', null),
    api: get('--api', 'http://localhost:8000/api/v1').replace(/\/$/, ''),
    email: get('--email', 'admin@fashionstore.bo'),
    pass: get('--pass', 'admin123'),
  };
}

function elegirProducto(archivo) {
  const base = basename(archivo).toLowerCase();
  const ext = extname(base).slice(1).toLowerCase();
  if (!MIME[ext]) return null;
  const stem = basename(base, `.${ext}`);
  const m = stem.match(/^(?:producto_)?(\d+)/);
  if (m) return Number(m[1]);
  const porNombre = PRODUCTOS.find(([, n]) => NORMA(n) === NORMA(stem));
  return porNombre ? porNombre[0] : null;
}

async function main() {
  const cfg = args();
  if (!cfg.folder) {
    console.error('Falta --folder. Uso: node scripts/subir_imagenes_productos.mjs --folder <carpeta>');
    process.exit(1);
  }

  let archivos = [];
  try {
    archivos = readdirSync(cfg.folder).filter((f) => MIME[extname(f).slice(1).toLowerCase()]);
  } catch (e) {
    console.error(`No se pudo leer la carpeta: ${cfg.folder} (${e.message})`);
    process.exit(1);
  }

  console.log(`Carpeta: ${cfg.folder} · ${archivos.length} imagen(es) encontrada(s)`);

  const login = await fetch(`${cfg.api}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: cfg.email, contrasena: cfg.pass }),
  });
  if (!login.ok) {
    console.error('Login fallido. Revisa --email/--pass o que el backend esté arriba.');
    process.exit(1);
  }
  const token = (await login.json()).access_token;

  const resultados = { ok: [], sinUso: [], error: [] };
  for (const archivo of archivos) {
    const id = elegirProducto(archivo);
    const ruta = join(cfg.folder, archivo);
    if (!id) {
      resultados.sinUso.push(archivo);
      continue;
    }
    const buffer = readFileSync(ruta);
    const fd = new FormData();
    fd.append(
      'archivo',
      new Blob([buffer], { type: MIME[extname(archivo).slice(1).toLowerCase()] }),
      archivo,
    );
    const resp = await fetch(`${cfg.api}/catalogo/productos/${id}/imagen`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: fd,
    });
    if (resp.ok) {
      const p = await resp.json();
      resultados.ok.push(`producto ${id} (${archivo}) → ${p.imagen_url}`);
    } else {
      const detalle = await resp.text().catch(() => '');
      resultados.error.push(`producto ${id} (${archivo}) → HTTP ${resp.status}: ${detalle.slice(0, 120)}`);
    }
  }

  console.log('\n===== RESULTADO =====');
  resultados.ok.forEach((r) => console.log(`OK   ${r}`));
  resultados.error.forEach((r) => console.log(`FAIL ${r}`));
  resultados.sinUso.forEach((r) => console.log(`SKIP ${r} (no se asoció a ningún producto)`));
  console.log(`\n${resultados.ok.length} subidas · ${resultados.error.length} errores · ${resultados.sinUso.length} sin uso`);
  process.exit(resultados.error.length ? 1 : 0);
}

main();