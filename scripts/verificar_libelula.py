"""Verificacion de la integracion con Libelula (Fase B).

Este script comprueba, en orden, todo lo que puede fallar antes de que un
cliente intente pagar. Se ejecuta en dos niveles:

    1. Sin appkey comprueba lo que se puede: que la configuracion este completa,
       que la URL de callback sea publica y que el tunel este levantado. Esto
       se puede verificar hoy mismo.

    2. Con `--conectar` ademas habla con la pasarela de verdad: registra una
       deuda de Bs. 1 y consulta la conciliacion. Ahi es donde se confirma si el
       contrato asumido en `qr_service.py` (los nombres de campo de
       `consultar_pagos`, en particular) coincide con lo que responde Libelula.

Que un nivel pase NO garantiza el siguiente: la conciliacion solo se puede
verificar con un pago real, no con una deuda recien creada.

Uso:
    python scripts/verificar_libelula.py
    python scripts/verificar_libelula.py --conectar
    python scripts/verificar_libelula.py --conectar --monto 1.00
"""

import argparse
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "backend"))

# `Settings` resuelve `env_file=".env"` contra el directorio de trabajo. Este
# script se puede lanzar desde la raiz del repo, donde NO hay .env, y ahi
# pydantic se queda con los defaults de `config.py` en vez de leer la config
# real. Eso hacia que el diagnostico reportara 'produccion' cuando el backend
# real estaba configurado para pruebas. Hay que moverse antes de leer nada.
os.chdir(RAIZ / "backend")
ARCHIVO_ENV = Path(".env").resolve()

try:
    import httpx
except ImportError:
    print("Falta httpx. Instalalo con:  pip install -r backend/requirements.txt")
    sys.exit(2)

from app.core.config import get_settings  # noqa: E402
import app.services.qr_service as qs  # noqa: E402

VERDE, ROJO, AMARILLO, GRIS, FIN = "\033[32m", "\033[31m", "\033[33m", "\033[90m", "\033[0m"

problemas = []
avisos = []


def ok(msg):
    print(f"  [{VERDE}OK   {FIN}] {msg}")


def falla(msg, como_arreglarlo=None):
    problemas.append(msg)
    print(f"  [{ROJO}FALLA{FIN}] {msg}")
    if como_arreglarlo:
        print(f"          {GRIS}{como_arreglarlo}{FIN}")


def aviso(msg):
    avisos.append(msg)
    print(f"  [{AMARILLO}AVISO{FIN}] {msg}")


def titulo(texto):
    print(f"\n{texto}")
    print("-" * len(texto))


# ---------------------------------------------------------------------------
# 1. Configuracion
# ---------------------------------------------------------------------------
def revisar_configuracion(settings) -> bool:
    titulo("1. Configuracion")

    if (settings.QR_PROVEEDOR or "").strip().lower() == "libelula":
        ok(f"QR_PROVEEDOR={settings.QR_PROVEEDOR}")
    else:
        falla(
            f"QR_PROVEEDOR es '{settings.QR_PROVEEDOR}', no 'libelula'",
            "Los cobros siguen siendo simulados. Editalo en backend/.env",
        )

    appkey = (settings.QR_APPKEY or "").strip()
    if appkey:
        # El manual lo muestra como un UUID en claro. Se muestra solo la forma,
        # nunca el valor completo.
        forma = "UUID (formato del manual)" if appkey.count("-") == 4 else "texto libre"
        ok(f"QR_APPKEY presente, {forma}, {len(appkey)} caracteres")
    else:
        falla(
            "QR_APPKEY vacio",
            "Pedilo a libelula@todotix.com. Sin el, la pasarela no se activa.",
        )

    base = (settings.QR_BASE_URL or "").strip()
    if ":10888" in base:
        ok(f"QR_BASE_URL apunta a AMBIENTE DE PRUEBAS ({base})")
        aviso("Los pagos de prueba no son reales. Para cobrar de verdad, usa https://api.todotix.com")
    elif base.startswith("https://api.todotix.com"):
        ok(f"QR_BASE_URL apunta a PRODUCCION ({base})")
        aviso("Vas a cobrar dinero real. Prueba antes con el ambiente de pruebas.")
    else:
        aviso(f"QR_BASE_URL inesperado: {base}")

    if settings.QR_MONEDA.upper() == "BOB":
        ok(f"QR_MONEDA={settings.QR_MONEDA}")
    else:
        aviso(f"QR_MONEDA es '{settings.QR_MONEDA}'; el manual trabaja en bolivianos")

    if settings.QR_EMITE_FACTURA == "0":
        ok("QR_EMITE_FACTURA=0 (sin facturacion electronica, segun lo acordado)")
    else:
        aviso(f"QR_EMITE_FACTURA={settings.QR_EMITE_FACTURA}: revisa NIT y razon social")

    return bool(appkey)


# ---------------------------------------------------------------------------
# 2. Callback
# ---------------------------------------------------------------------------
def revisar_callback(settings) -> bool:
    titulo("2. URL de notificacion (callback)")

    base = (settings.QR_CALLBACK_BASE or "").strip().rstrip("/")
    if not base:
        falla(
            "QR_CALLBACK_BASE vacio",
            "Libelula necesita una URL publica para avisar el pago. Levanta un tunel:\n"
            "          cloudflared tunnel --url http://localhost:8000",
        )
        return False

    locales = ("localhost", "127.0.0.1", "0.0.0.0", "192.168.", "10.")
    if any(x in base for x in locales):
        falla(f"QR_CALLBACK_BASE es una direccion local ({base}); Libelula no puede alcanzarla",
              "Usa la URL publica que entrega el tunel")
        return False
    if not base.startswith("https://"):
        aviso(f"El callback no usa HTTPS ({base}). ngrok y cloudflared lo dan por defecto")
    else:
        ok(f"Callback publico: {base}")

    # Sonda de alcance: el endpoint sin referencia debe responder 400. Eso
    # prueba que el tunel llega a la app y que la ruta esta viva, sin tocar
    # ningun cobro ni llamar a la pasarela.
    url = f"{base}/api/v1/pagos/webhook/qr"
    try:
        r = httpx.get(url, timeout=15)
    except Exception as exc:  # noqa: BLE001
        falla(f"El callback no responde ({exc})",
              "El backend tiene que estar corriendo en el mismo puerto que apunta el tunel")
        return False

    if r.status_code == 400:
        ok(f"El tunel llega a la app y la ruta responde ({r.status_code} por falta de referencia)")
    elif r.status_code in (401, 403):
        aviso(f"El callback responde {r.status_code}: algo esta protegiendo la ruta")
    else:
        aviso(f"El callback responde {r.status_code}; se esperaba 400 en la sonda")

    if not (settings.QR_URL_RETORNO or "").strip():
        # No es un aviso: el backend se niega a registrar la deuda sin esto, y
        # con razon. Si no se manda, Libelula redirige al callback_url y el
        # cliente aterriza viendo un JSON de error.
        falla(
            "QR_URL_RETORNO vacio: el backend rechaza crear el cobro (503)",
            "Apuntalo a la pantalla del punto de venta, por ejemplo\n"
            "          http://localhost:4200/ventas/punto-venta",
        )
    else:
        ok(f"QR_URL_RETORNO={settings.QR_URL_RETORNO}")

    return True


def revisar_alcance(settings) -> bool:
    """Comprueba que el host de la pasarela responde de verdad.

    Sin esto, un ambiente caido se manifestaria como un timeout en
    `registrar`, que es dificil de distinguir de un problema del codigo.
    Se consulta la raiz con GET: si la ruta de produccion existe, un GET a
    `/rest/deuda/registrar` responde 405, y esa misma respuesta ya prueba
    que hay algo escuchando detras.
    """
    titulo("3. Alcance de la pasarela")
    base = (settings.QR_BASE_URL or "").strip().rstrip("/")
    url = f"{base}/rest/deuda/registrar"
    try:
        r = httpx.get(url, timeout=30.0)
    except Exception as exc:  # noqa: BLE001
        falla(
            f"La pasarela no responde en {url} ({type(exc).__name__})",
            "El ambiente puede estar caido. Verifica la URL vigente con Libelula:\n"
            "          el que documenta el manual v2.7 (puerto 10888) se compro caido,\n"
            "          asi que la URL vigente puede ser otra.",
        )
        return False

    if r.status_code == 405:
        ok("La ruta existe y solo acepta POST (405 en GET), que es lo esperado")
        return True
    if r.status_code >= 500:
        falla(f"La pasarela responde {r.status_code}: esta fallando del lado de ellos")
        return False
    ok(f"Hay algo escuchando en {base} (respondio {r.status_code})")
    return True


# ---------------------------------------------------------------------------
# 3. Contrato real de la API (requiere appkey)
# ---------------------------------------------------------------------------
def revisar_contrato(settings, monto: float) -> bool:
    titulo("4. Contrato real de la pasarela (POST /rest/deuda/registrar)")

    marca = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    descripcion = f"Prueba de integracion {marca}"

    try:
        # Se llama a la funcion interna a proposito: `crear_cobro_qr` degrada en
        # silencio a modo simulado si la pasarela falla, y aqui justamente se
        # quiere ver el fallo, no esconderlo.
        cobro = qs._cobro_libelula(monto, descripcion, "verificacion@fashionstore.bo", None)
    except Exception as exc:  # noqa: BLE001
        falla(f"La pasarela rechazo el alta de la deuda: {exc}",
              "Revisa que el appkey sea el del ambiente que indica QR_BASE_URL:\n"
              "          el appkey de pruebas solo funciona en toto dix:10888")
        return False

    ok(f"Deuda registrada por Bs. {monto:.2f}")

    txn = cobro.get("transaccion_id")
    if txn and txn != cobro.get("identificador_deuda"):
        ok("Libelula devolvio su propio id_transaccion (es el que usara la notificacion)")
    else:
        aviso("Libelula no devolvio id_transaccion; se usara la referencia propia")

    if cobro.get("url_pago"):
        ok("Vino url_pasarela_pagos (la pagina de pago)")
    else:
        aviso("No vino url_pasarela_pagos; se genero el QR localmente desde la pagina de pago")

    if cobro.get("qr_url", "").startswith("data:image/png;base64,"):
        ok("Hay un QR escaneable para mostrarle al cliente")

    # La conciliacion no debe encontrar todavia un pago que el cliente aun no hizo.
    titulo("5. Contrato de conciliar (POST /rest/deuda/consultar_pagos)")
    desde = datetime.now(timezone.utc) - timedelta(hours=1)
    hasta = datetime.now(timezone.utc) + timedelta(minutes=5)
    registros = qs.consultar_pagos(desde, hasta)
    if not isinstance(registros, list):
        falla(f"consultar_pagos devolvio {type(registros).__name__}, se esperaba una lista")
        return False
    ok(f"consultar_pagos responde una lista ({len(registros)} pagos en la ventana)")

    if registros:
        primero = registros[0]
        print(f"  {GRIS}Ejemplo de pago recibido:{FIN}")
        for clave in ("id_transaccion", "identificador", "monto_pagado",
                      "codigo_recaudacion", "fecha_pago", "forma_pago"):
            print(f"      {clave}: {primero.get(clave, f'<no viene: {clave}>')}")

        # Estas son las suposiciones del codigo. Si alguna falla, hay que corregir
        # `confirmar_pago` / `_monto_registrado` antes de cobrar a nadie.
        for clave in ("id_transaccion", "monto_pagado"):
            if clave not in primero:
                falla(f"El manual documenta '{clave}' pero no vino en la respuesta real",
                      "Ajusta confirmar_pago y _monto_registrado en qr_service.py")
    else:
        aviso(
            "La ventana no tiene pagos. Para verificar el cruce por id_transaccion y el\n"
            "          monto, hay que hacer un pago de verdad y volver a correr este script."
        )

    titulo("6. Que falta para cerrar la verificacion")
    print(f"""
  1. Paga los Bs. {monto:.2f} de la deuda recien creada (la pagina de pago esta en:
     {cobro.get('url_pago') or 'no se obtuvo url_pasarela_pagos'})

  2. Espera a que Libelula notifique a:
     {settings.QR_CALLBACK_BASE}/api/v1/pagos/webhook/qr?transaction_id={txn}

  3. Vuelve a correr:  python scripts/verificar_libelula.py --conectar
     Esta vez la conciliacion debe devolver el pago, y el cruce por
     id_transaccion y el monto quedan verificados de verdad.
""")
    return True


def main() -> int:
    p = argparse.ArgumentParser(description="Verifica la integracion con Libelula")
    p.add_argument("--conectar", action="store_true",
                   help="Habla con la pasarela: registra una deuda y consulta la conciliacion")
    p.add_argument("--monto", type=float, default=1.0,
                   help="Monto de la deuda de prueba (Bs. 1 es lo que recomienda la guia)")
    args = p.parse_args()

    settings = get_settings()
    # `qr_service` leo la configuracion al importarse, asi que se realinea con
    # la instancia que construyo `get_settings` (tests pueden alterarla).
    qs.settings = settings

    print("Verificacion de la integracion Libelula")
    print(f"{RAIZ.name}  |  {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    if ARCHIVO_ENV.exists():
        print(f"configuracion leida de: {ARCHIVO_ENV}")
    else:
        print(f"  [AVISO] No existe {ARCHIVO_ENV}: se usan los valores por defecto\n"
              f"          de config.py, que NO son los que ve el backend.")

    hay_appkey = revisar_configuracion(settings)
    hay_callback = revisar_callback(settings)
    hay_alcance = revisar_alcance(settings)

    if args.conectar and hay_appkey and hay_alcance:
        revisar_contrato(settings, args.monto)
    elif args.conectar and not hay_alcance:
        print(f"\n{ROJO}No se puede conectar: la pasarela no responde.{FIN}")
    elif args.conectar:
        print(f"\n{ROJO}No se puede conectar: falta el appkey.{FIN}")
    else:
        print(f"\n{GRIS}Se omite la conexion. Usa --conectar para hablar con la pasarela.{FIN}")

    print()
    if problemas:
        print(f"{ROJO}{len(problemas)} problema(s) que resuelven antes de cobrar a alguien:{FIN}")
        for p_ in problemas:
            print(f"  - {p_}")
    else:
        print(f"{VERDE}Sin bloqueos en la configuracion.{FIN}")
    if avisos:
        print(f"{AMARILLO}{len(avisos)} aviso(s).{FIN}")

    return 1 if problemas else 0


if __name__ == "__main__":
    sys.exit(main())
