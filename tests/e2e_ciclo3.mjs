/**
 * Test E2E - Casos de Uso del CICLO #3 (FashionStore)
 * CU17, CU16, CU07
 *
 * Uso:
 *   node tests/e2e_ciclo3.mjs
 *   API_URL=http://localhost/api/v1 node tests/e2e_ciclo3.mjs
 *
 * Requiere el stack levantado (docker compose up -d).
 */

const BASE = process.env.API_URL || 'http://localhost/api/v1';

const CREDS = {
  admin: { email: 'admin@fashionstore.bo', contrasena: 'admin123' },
  encargado: { email: 'juan.perez@fashionstore.bo', contrasena: 'encargado123' },
  cajero: { email: 'carlos.rojas@fashionstore.bo', contrasena: 'cajero123' },
  cliente: { email: 'laura.vargas@gmail.com', contrasena: 'cliente123' },
};

const results = [];
let ctx = {};

function tag(ok) {
  if (ok === true) return 'PASS';
  if (ok === 'partial') return 'WARN';
  return 'FAIL';
}

function record(cu, name, ok, detail = '') {
  results.push({ cu, name, ok, detail });
  const t = tag(ok);
  const mark = t === 'PASS' ? '\x1b[32mPASS\x1b[0m' : t === 'WARN' ? '\x1b[33mWARN\x1b[0m' : '\x1b[31mFAIL\x1b[0m';
  console.log(`  [${mark}] ${name}${detail ? ' :: ' + detail : ''}`);
}

function cuHeader(cu, title) {
  console.log(`\n\x1b[1m\x1b[34mCU${cu} - ${title}\x1b[0m`);
}

async function req(method, path, { token, body } = {}) {
  const headers = {};
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (token) headers.Authorization = `Bearer ${token}`;
  let res;
  try {
    res = await fetch(BASE + path, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  } catch (e) {
    return { status: 0, json: null, error: String(e) };
  }
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = text;
  }
  return { status: res.status, json };
}

async function login(role) {
  const { status, json } = await req('POST', '/auth/login', { body: CREDS[role] });
  if (status !== 200 || !json?.access_token) {
    throw new Error(`login ${role} falló (status ${status}): ${JSON.stringify(json)}`);
  }
  return { token: json.access_token, usuario: json.usuario };
}

async function testCU17() {
  cuHeader('17', 'Recibir recomendaciones de IA (RF25)');

  const cliente = await login('cliente');

  // 1) Sin token -> 401
  const anon = await req('GET', '/ia/recomendaciones');
  record('17', 'GET /ia/recomendaciones sin token -> 401', anon.status === 401, `status=${anon.status}`);

  // 2) Cliente autenticado -> 200 con ProductoOut[]
  const rec = await req('GET', '/ia/recomendaciones?limit=6', { token: cliente.token });
  const okRec = rec.status === 200 && Array.isArray(rec.json);
  record('17', 'GET /ia/recomendaciones (cliente) -> 200 list[producto]', okRec, `status=${rec.status} items=${Array.isArray(rec.json) ? rec.json.length : '-'}`);
  if (okRec && rec.json.length > 0) {
    const p = rec.json[0];
    const shape = typeof p.id_producto === 'number' && typeof p.nombre === 'string' && typeof p.precio === 'number';
    const activos = rec.json.every((x) => x.activo === true);
    record('17', 'Shape ProductoOut + productos activos', shape && activos, `activo=${activos} shape=${shape}`);
    const conVariantes = Array.isArray(p.variantes);
    record('17', 'Respuesta incluye variantes', conVariantes);
  }

  // 3) Recomendaciones por sucursal -> 200, solo con stock
  const disp = await req('GET', '/ia/recomendaciones/disponibles?sucursal_id=1&limit=6');
  const okDisp = disp.status === 200 && Array.isArray(disp.json);
  record('17', 'GET /ia/recomendaciones/disponibles?sucursal_id=1 -> 200 list[producto]', okDisp, `status=${disp.status} items=${Array.isArray(disp.json) ? disp.json.length : '-'}`);

  // 4) Bitácora registrada (CU-23) por la consulta de recomendaciones
  const admin = await login('admin');
  const bit = await req('GET', `/bitacora?accion=CONSULTA_RECOMENDACIONES&limite=5`, { token: admin.token });
  const hayRegistro = bit.status === 200 && Array.isArray(bit.json) && bit.json.length > 0;
  record('17', 'CU-23 bitácora registra CONSULTA_RECOMENDACIONES', hayRegistro, `status=${bit.status} registros=${Array.isArray(bit.json) ? bit.json.length : '-'}`);
}

/**
 * CU16 - Generar reportes y dashboards (RF26 a RF33)
 */
async function testCU16() {
  cuHeader('16', 'Generar reportes y dashboards');

  const anonChecks = [
    ['resumen', '/reportes/resumen'],
    ['ventas-por-sucursal', '/reportes/ventas-por-sucursal'],
    ['mas-vendidos', '/reportes/mas-vendidos'],
    ['rotacion-inventario', '/reportes/rotacion-inventario'],
    ['stock-critico', '/reportes/stock-critico'],
    ['reservas', '/reportes/reservas'],
    ['tendencias-temporada', '/reportes/tendencias-temporada'],
  ];
  for (const [nombre, path] of anonChecks) {
    const anon = await req('GET', path);
    record('16', `GET ${path} sin token -> 401`, anon.status === 401, `status=${anon.status}`);
  }

  // Roles no permitidos -> 403
  const cajero = await login('cajero');
  const cliente = await login('cliente');
  const noPermitido = await req('GET', '/reportes/resumen', { token: cajero.token });
  const noPermitidoCli = await req('GET', '/reportes/resumen', { token: cliente.token });
  record('16', 'GET /reportes/resumen con rol cajero -> 403', noPermitido.status === 403, `status=${noPermitido.status}`);
  record('16', 'GET /reportes/resumen con rol cliente -> 403', noPermitidoCli.status === 403, `status=${noPermitidoCli.status}`);

  const admin = await login('admin');

  const resumen = await req('GET', '/reportes/resumen', { token: admin.token });
  const okResumen =
    resumen.status === 200 &&
    resumen.json !== null &&
    typeof resumen.json.ventas_total === 'number' &&
    typeof resumen.json.total_pedidos === 'number' &&
    typeof resumen.json.stock_critico === 'number' &&
    typeof resumen.json.reservas_activas === 'number' &&
    Array.isArray(resumen.json.top_productos);
  record('16', 'GET /reportes/resumen (admin) -> 200 con KPIs', okResumen, `status=${resumen.status} ventas=${resumen.json?.ventas_total} pedidos=${resumen.json?.total_pedidos}`);
  if (okResumen) {
    const top = resumen.json.top_productos[0];
    const shapeTop = !top || (typeof top.producto === 'string' && typeof top.unidades === 'number');
    record('16', 'resumen.top_productos con shape', shapeTop || resumen.json.top_productos.length === 0);
  }

  const ventas = await req('GET', '/reportes/ventas-por-sucursal', { token: admin.token });
  const okVentas = ventas.status === 200 && Array.isArray(ventas.json) && ventas.json.every((r) => typeof r.sucursal === 'string' && typeof r.total === 'number');
  record('16', 'GET /reportes/ventas-por-sucursal -> 200 list[sucursal,total]', okVentas, `status=${ventas.status} rows=${Array.isArray(ventas.json) ? ventas.json.length : '-'}`);

  const mas = await req('GET', '/reportes/mas-vendidos?limit=10', { token: admin.token });
  const okMas = mas.status === 200 && Array.isArray(mas.json) && mas.json.every((r) => typeof r.producto === 'string' && typeof r.unidades === 'number' && typeof r.monto === 'number');
  record('16', 'GET /reportes/mas-vendidos -> 200 list[producto,unidades,monto]', okMas, `status=${mas.status} items=${Array.isArray(mas.json) ? mas.json.length : '-'}`);

  const rot = await req('GET', '/reportes/rotacion-inventario?limit=10', { token: admin.token });
  const oksRot = rot.status === 200 && Array.isArray(rot.json) && rot.json.every((r) => typeof r.producto === 'string' && typeof r.unidades_vendidas === 'number' && typeof r.rotacion === 'number');
  record('16', 'GET /reportes/rotacion-inventario -> 200 list[producto,rotacion]', oksRot, `status=${rot.status} items=${Array.isArray(rot.json) ? rot.json.length : '-'}`);

  const critico = await req('GET', '/reportes/stock-critico', { token: admin.token });
  const okCritico =
    critico.status === 200 &&
    Array.isArray(critico.json) &&
    critico.json.every((r) => typeof r.producto === 'string' && typeof r.stock_minimo === 'number' && typeof r.disponible === 'number' && r.disponible <= r.stock_minimo);
  record('16', 'GET /reportes/stock-critico -> 200 con disponible <= stock_minimo', okCritico, `status=${critico.status} rows=${Array.isArray(critico.json) ? critico.json.length : '-'}`);

  const reservas = await req('GET', '/reportes/reservas', { token: admin.token });
  const okReservas =
    reservas.status === 200 &&
    reservas.json !== null &&
    Array.isArray(reservas.json.por_estado) &&
    Array.isArray(reservas.json.por_sucursal);
  record('16', 'GET /reportes/reservas -> 200 {por_estado, por_sucursal}', okReservas, `status=${reservas.status}`);

  const tendencias = await req('GET', '/reportes/tendencias-temporada', { token: admin.token });
  const okTendencias = tendencias.status === 200 && Array.isArray(tendencias.json) && tendencias.json.every((r) => typeof r.temporada === 'string' && typeof r.monto === 'number');
  record('16', 'GET /reportes/tendencias-temporada -> 200 list[temporada,monto]', okTendencias, `status=${tendencias.status} items=${Array.isArray(tendencias.json) ? tendencias.json.length : '-'}`);

  // Filtros combinados
  const filtrado = await req(
    'GET',
    '/reportes/ventas-por-sucursal?sucursal_id=1&categoria_id=1&temporada_id=1&fecha_desde=2024-01-01&fecha_hasta=2026-12-31',
    { token: admin.token },
  );
  record('16', 'GET /reportes/ventas-por-sucursal con filtros -> 200', filtrado.status === 200 && Array.isArray(filtrado.json), `status=${filtrado.status}`);

  // Encargado: acceso permitido pero restringido a SU sucursal
  const encargado = await login('encargado');
  const encResumen = await req('GET', '/reportes/resumen', { token: encargado.token });
  const encVentas = await req('GET', '/reportes/ventas-por-sucursal', { token: encargado.token });
  const soloSuSucursal =
    encVentas.status === 200 &&
    Array.isArray(encVentas.json) &&
    encVentas.json.length === 1 &&
    encVentas.json[0].sucursal_id === 1;
  record('16', 'GET /reportes/ventas-por-sucursal (encargado) -> solo sucursal asignada', encResumen.status === 200 && soloSuSucursal, `status=${encVentas.status} rows=${Array.isArray(encVentas.json) ? encVentas.json.length : '-'}`);

  // CU-23: bitácora registra GENERA_REPORTE
  const bit = await req('GET', '/bitacora?accion=GENERA_REPORTE&limite=5', { token: admin.token });
  record('16', 'CU-23 bitácora registra GENERA_REPORTE', bit.status === 200 && Array.isArray(bit.json) && bit.json.length > 0, `status=${bit.status} registros=${Array.isArray(bit.json) ? bit.json.length : '-'}`);
}

const tests = [testCU17, testCU16];

async function main() {
  try {
    for (const role of Object.keys(CREDS)) {
      ctx.tokens = ctx.tokens || {};
      ctx.tokens[role] = await login(role);
    }
  } catch (e) {
    console.error(`\x1b[31m${e.message}\x1b[0m`);
    process.exit(2);
  }

  for (const t of tests) {
    try {
      await t();
    } catch (e) {
      record('?', t.name, false, `excepción: ${e.message}`);
    }
  }

  const byCu = new Map();
  for (const r of results) {
    if (!byCu.has(r.cu)) byCu.set(r.cu, []);
    byCu.get(r.cu).push(r);
  }
  console.log('\n\x1b[1m================ RESUMEN POR CASO DE USO ================\x1b[0m');
  let fails = 0;
  let warns = 0;
  const order = [17, 16, 7];
  for (const cu of order) {
    const rs = byCu.get(String(cu)) || [];
    const f = rs.filter((r) => r.ok === false).length;
    const w = rs.filter((r) => r.ok === 'partial').length;
    const p = rs.filter((r) => r.ok === true).length;
    fails += f;
    warns += w;
    const status = f > 0 ? '\x1b[31mFAIL\x1b[0m' : w > 0 ? '\x1b[33mPARCIAL\x1b[0m' : '\x1b[32mOK\x1b[0m';
    console.log(`CU${String(cu).padStart(2)}: ${status}  (${p} ok, ${w} warn, ${f} fail)`);
  }

  const total = results.length;
  const pass = results.filter((r) => r.ok === true).length;
  console.log(`\n\x1b[1mTOTAL:\x1b[0m ${pass}/${total} verificaciones OK, ${warns} parciales, ${fails} fallidas`);
  process.exit(fails > 0 ? 1 : 0);
}

main();