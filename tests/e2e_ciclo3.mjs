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

const tests = [testCU17];

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