"""Servicio de la pasarela de pago QR (Libelula / Todotix).

Espejo de `app.services.stripe_service`: cuando no hay credenciales reales el
servicio opera en modo simulado, pero el contrato de respuesta es identico en
ambos modos. El cliente (web y movil) nunca necesita saber cual de los dos esta
activo; solo lee el campo `simulado` para etiquetar la interfaz.

Modos:
    - "libelula": POST /rest/deuda/registrar en la pasarela. La deuda queda
      pendiente y Libelula notifica el pago con un GET a `callback_url`.
    - "simulado": se genera el codigo QR localmente. Ningun dinero se mueve;
      sirve para demostracion y para desarrollo sin credenciales.
"""

import base64
import io
import logging
import secrets
import uuid
from datetime import datetime, timedelta, timezone

import httpx
import qrcode

from app.core.config import get_settings

settings = get_settings()

logger = logging.getLogger(__name__)

TIMEOUT_HTTP = 20.0
PROVEEDOR_SIMULADO = "SIMULADO"
PROVEEDOR_LIBELULA = "LIBELULA"


class ErrorConfiguracionPasarela(RuntimeError):
    """La pasarela esta mal configurada o rechazo la operacion.

    Es deliberadamente distinta de un fallo de red. Un timeout se resuelve
    degradando a modo simulado, pero un appkey invalido, un ambiente
    equivocado o un parametro rechazado NO se resuelven asi: degradar en
    silencio haria que el cajero muestre un QR que parece real, el cliente
    pague, y la deuda nunca exista para el sistema. Ese fallo tiene que verse.
    """

# Bolivia es UTC-4 todo el ano. La pasarela registra y consulta sus fechas en
# hora local, asi que la ventana de conciliacion se translate a esa zona antes
# de formatearla.
ZONA_PASARELA = timezone(timedelta(hours=-4))


def qr_operativa() -> bool:
    """True solo si hay una pasarela QR real configurada.

    Se evalua unicamente la configuracion: no se hace una llamada de red para
    no agregar latencia a cada cobro. Si la pasarela esta caida durante el cobro,
    `crear_cobro_qr` degrada a modo simulado y lo deja registrado en el log.
    """
    if (settings.QR_PROVEEDOR or "").strip().lower() != "libelula":
        return False
    if not settings.QR_APPKEY or settings.QR_APPKEY.strip() == "":
        return False
    return True


def proveedor_actual() -> str:
    """Identificador del proveedor que se guarda en pagos.proveedor_pago."""
    return PROVEEDOR_LIBELULA if qr_operativa() else PROVEEDOR_SIMULADO


def proveedor_del_cobro(cobro: dict) -> str:
    """Proveedor REAL del cobro recien creado, segun lo que paso de verdad.

    No sirve `proveedor_actual()`: si la pasarela esta configurada pero no
    responde, `crear_cobro_qr` degrada a modo simulado. Guardar 'LIBELULA' en ese
    caso haria que la conciliacion fuera a buscar en la pasarela una deuda que
    nunca se registro, y el pago se quedaria pendiente para siempre.
    """
    return PROVEEDOR_SIMULADO if cobro.get("simulado") else PROVEEDOR_LIBELULA


def _exito_libelula(cuerpo: dict) -> bool:
    """True si Libelula acepto la operacion.

    Ojo con esto: Libelula responde `'error': 0` cuando la operacion fue
    EXITOSA. El `0` es un exito, no un fallo, y el campo llega como entero. La
    clave se asume en error cuando no viene, para no dar por bueno un cobro que
    la pasarela respondio con una forma inesperada.
    """
    crudo = cuerpo.get("error", 1)
    if isinstance(crudo, str):
        return crudo.strip().lower() in ("0", "false", "falso")
    return not crudo


def _qr_a_data_uri(contenido: str) -> str:
    """Codifica un texto en un PNG QR y lo devuelve como data URI.

    Se usa un data URI y no una URL para que el frontend pueda asignarlo
    directamente a un `src` sin una segunda peticion HTTP.
    """
    imagen = qrcode.make(contenido, box_size=8, border=2)
    buffer = io.BytesIO()
    imagen.save(buffer, format="PNG")
    codificado = base64.b64encode(buffer.getvalue()).decode("ascii")
    return f"data:image/png;base64,{codificado}"


def _expiracion() -> datetime:
    return datetime.now(timezone.utc) + timedelta(minutes=settings.QR_TIMEOUT_MINUTOS)


def _cobro_simulado(monto: float, descripcion: str, referencia: str | None) -> dict:
    """Cobro generado localmente. Mismo contrato, sin pasarela de por medio."""
    transaccion_id = f"TXN-SIM-{uuid.uuid4().hex[:20].upper()}"
    contenido = (
        f"FASHIONSTORE (cobro simulado)\n"
        f"Transaccion: {transaccion_id}\n"
        f"Concepto: {descripcion}\n"
        f"Monto: {settings.QR_MONEDA} {monto:.2f}\n"
    )
    if referencia:
        contenido += f"Referencia: {referencia}\n"
    return {
        "transaccion_id": transaccion_id,
        "identificador_deuda": transaccion_id,
        "qr_url": _qr_a_data_uri(contenido),
        "url_pago": None,
        "estado": "pendiente",
        "simulado": True,
        "expires_at": _expiracion(),
    }


def _lineas_detalle(monto: float, descripcion: str) -> list[dict]:
    """Detalle de la deuda en el formato de lineas que espera Libelula."""
    return [{"descripcion": descripcion, "cantidad": 1, "precio_unitario": monto}]


def _cobro_libelula(
    monto: float,
    descripcion: str,
    email_cliente: str,
    referencia: str | None,
) -> dict:
    """Registra la deuda en Libelula y devuelve el QR a mostrar.

    El contrato sigue el manual de integracion v2.7 de Libelula
    (`POST /rest/deuda/registrar`). Puntos que es facil pasar por alto:

        - el `appkey` se envia tal cual lo entrego Libelula (un UUID). No lleva
          firma MD5 ni hash: el ejemplo del manual lo muestra en claro.
        - la respuesta trae `'error': 0` cuando la operacion fue exitosa.
        - `url_pasarela_pagos` es la pagina de pago; `qr_simple_url` solo
          existe si la empresa tiene habilitado el canal "QR Simple".
        - `fecha_vencimiento` es de granularidad diaria (yyyy-MM-dd), asi que
          la pasarela no puede imponer una ventana de minutos.

    Esa ultima limitacion es la razon por la que `QR_TIMEOUT_MINUTOS` se
    aplica solo en este sistema: la pasarela seguiria aceptando el pago horas
    despues. El webhook detecta ese caso y lo marca como pago tardio.
    """
    transaccion_id = f"TXN-{uuid.uuid4().hex[:20].upper()}"
    if not settings.QR_CALLBACK_BASE:
        raise ErrorConfiguracionPasarela(
            "QR_CALLBACK_BASE vacio: la pasarela necesita una URL publica "
            "(ngrok o cloudflared) para poder notificar el pago"
        )
    # `url_retorno` NO es opcional en la practica. El manual dice que cuando no
    # se envia, la pasarela usa el `callback_url` como redireccion del cliente:
    # quien paga aterriza en el webhook y ve un JSON de error en vez de su
    # comprobante. Antes esto caia al webhook como valor por defecto; ahora se
    # exige configurarlo, porque es un error de configuracion y no algo que se
    # pueda deducir.
    if not (settings.QR_URL_RETORNO or "").strip():
        raise ErrorConfiguracionPasarela(
            "QR_URL_RETORNO vacio: es la pagina donde aterriza el CLIENTE tras "
            "pagar. Si se omite, Libelula redirige al callback_url y el cliente "
            "aterriza en el webhook. Configuralo con la ruta del punto de venta, "
            "por ejemplo http://localhost:4200/ventas/punto-venta"
        )
    base = settings.QR_CALLBACK_BASE.rstrip("/")

    payload = {
        "appkey": settings.QR_APPKEY.strip(),
        "identificador_deuda": transaccion_id,
        "email_cliente": email_cliente,
        # Granularidad diaria: la pasarela no admite fecha y hora.
        "fecha_vencimiento": _expiracion().strftime("%Y-%m-%d"),
        "descripcion": descripcion,
        "callback_url": f"{base}/api/v1/pagos/webhook/qr",
        # `url_retorno` es donde aterriza el CLIENTE tras pagar, asi que no puede
        # ser el webhook (terminaria viendo un JSON de error). Se valida arriba
        # y se envia tal cual.
        "url_retorno": settings.QR_URL_RETORNO.strip(),
        "nombre_cliente": email_cliente.split("@")[0],
        "apellido_cliente": settings.QR_CLIENTE_APELLIDO,
        "ci": settings.QR_CLIENTE_CI,
        "razon_social": settings.QR_RAZON_SOCIAL,
        "nit": settings.QR_NIT,
        "emite_factura": settings.QR_EMITE_FACTURA,
        "moneda": settings.QR_MONEDA,
        "valor_envio": "0",
        "descripcion_envio": "-",
        "lineas_detalle_deuda": _lineas_detalle(monto, descripcion),
    }

    with httpx.Client(timeout=TIMEOUT_HTTP) as cliente:
        respuesta = cliente.post(
            f"{settings.QR_BASE_URL.rstrip('/')}/rest/deuda/registrar",
            json=payload,
        )
        respuesta.raise_for_status()
        cuerpo = respuesta.json()

    if not _exito_libelula(cuerpo):
        # Un rechazo casi siempre es configuracion: appkey del ambiente
        # equivocado, appkey vencido, o un parametro que la pasarela no
        # acepto. Se propaga como error de configuracion (no se degrada en
        # silencio) e incluye el codigo para poder diagnosticarlo.
        logger.error("Libelula rechazo el cobro: %s", cuerpo)
        raise ErrorConfiguracionPasarela(
            f"Libelula rechazo el cobro (error={cuerpo.get('error')!r}): "
            f"{cuerpo.get('mensaje') or cuerpo}. Verifica que QR_APPKEY "
            f"corresponda a {'PRUEBAS' if ':10888' in settings.QR_BASE_URL else 'PRODUCCION'}"
        )

    # Libelula devuelve su propio `id_transaccion`; ese es el valor que
    # aparece tanto en la notificacion como en la conciliacion, asi que es el
    # que se guarda. El `identificador_deuda` propio se conserva aparte, en
    # `datos_gateway`, para poder rastrear el cobro de punta a punta.
    id_pasarela = cuerpo.get("id_transaccion") or transaccion_id

    # El manual documenta `url_pasarela_pagos` como la pagina de pago, y
    # `qr_simple_url` como un PNG ya generado que solo existe con el canal
    # "QR Simple" habilitado.
    url_pasarela = cuerpo.get("url_pasarela_pagos") or cuerpo.get("url")
    qr_pregenerado = cuerpo.get("qr_simple_url")

    if qr_pregenerado:
        qr_url = qr_pregenerado
    elif url_pasarela:
        # Sin canal QR Simple se genera el codigo aqui a partir de la pagina
        # de pago, para que el cliente siempre reciba algo escaneable.
        qr_url = _qr_a_data_uri(url_pasarela)
    else:
        raise ErrorConfiguracionPasarela(
            "Libelula acepto la deuda pero no devolvio ni url_pasarela_pagos ni "
            "qr_simple_url: no hay forma de mostrar el QR al cliente. Revisar si "
            "la cuenta tiene habilitado el canal de pago y el QR Simple."
        )

    return {
        "transaccion_id": id_pasarela,
        "identificador_deuda": transaccion_id,
        "qr_url": qr_url,
        "url_pago": url_pasarela,
        "estado": "pendiente",
        "simulado": False,
        "expires_at": _expiracion(),
    }


def crear_cobro_qr(
    monto: float,
    descripcion: str,
    email_cliente: str,
    referencia: str | None = None,
) -> dict:
    """Crea un cobro QR y devuelve el contrato unico de la pasarela.

    Hay dos fallos muy distintos y se tratan distinto a proposito:

        - La pasarela esta caida (timeout, 5xx, sin red): se degrada a modo
          simulado para que el punto de venta no quede inutilizable. El log
          deja constancia y el cobro se guarda como SIMULADO.

        - La pasarela esta mal configurada (appkey invalido, ambiente
          equivocado, `url_retorno` vacio, un parametro rechazado): NO se
          degrada, el error sube. Degradar en ese caso es peor que caerse,
          porque el cajero mostraria un QR creible, el cliente pagaria, y la
          deuda no existiria para el sistema: el pago se perderia sin que
          nadie se entere. Es preferible un error visible.
    """
    if not qr_operativa():
        return _cobro_simulado(monto, descripcion, referencia)

    try:
        return _cobro_libelula(monto, descripcion, email_cliente, referencia)
    except ErrorConfiguracionPasarela:
        # No se degrada: es el error que el operador tiene que ver.
        raise
    except Exception as exc:  # noqa: BLE001 - degradar a simulado es intencional
        logger.warning(
            "La pasarela QR no respondio (%s); se genera el cobro en modo simulado.",
            exc,
        )
        return _cobro_simulado(monto, descripcion, referencia)


def verificar_firma(appkey_recibido: str) -> bool:
    """True si el token recibido coincide con el appkey configurado.

    La notificacion de Libelula NO trae firma: la plataforma llama por GET a
    `callback_url` anexando unicamente el identificador de la deuda. Por eso
    este token no puede ser la base de la seguridad, y el webhook no aprueba
    nada por su cuenta: usa la notificacion solo como aviso y luego confirma
    contra la pasarela. Ver `confirmar_pago`.
    """
    if not settings.QR_APPKEY or not appkey_recibido:
        return False
    return secrets.compare_digest(
        appkey_recibido.strip().lower(),
        settings.QR_APPKEY.strip().lower(),
    )


def consultar_pagos(desde: datetime, hasta: datetime) -> list[dict]:
    """Pagos registrados en la pasarela dentro de una ventana de tiempo.

    Es el unico mecanismo documentado para confirmar un pago. Libelula no ofrece
    consulta por transaccion, solo este listado por rango, asi que hay que
    filtrar el resultado en casa.

    Contrato (`POST /rest/deuda/consultar_pagos`):

        - entrada: `appkey`, `fecha_inicial`, `fecha_final` en
          `yyyy-MM-dd HH:mm:ss`.
        - respuesta: `{"error": 0, "mensaje": "N pagos encontrados.",
          "id_transaccion": null, "datos": [...]}`, donde cada elemento trae
          `id_transaccion`, `identificador`, `fecha_pago`, `monto_pagado`,
          `codigo_recaudacion` y `forma_pago`.

    La comparacion de fechas se hace en horario de Bolivia, que es donde esta
    la pasarela, aunque el servidor corra en UTC.
    """
    if not qr_operativa():
        return []

    ventana = {
        "appkey": settings.QR_APPKEY.strip(),
        "fecha_inicial": desde.astimezone(ZONA_PASARELA).strftime("%F %T"),
        "fecha_final": hasta.astimezone(ZONA_PASARELA).strftime("%F %T"),
    }
    try:
        with httpx.Client(timeout=TIMEOUT_HTTP) as cliente:
            respuesta = cliente.post(
                f"{settings.QR_BASE_URL.rstrip('/')}/rest/deuda/consultar_pagos",
                json=ventana,
            )
            respuesta.raise_for_status()
            cuerpo = respuesta.json()
    except Exception as exc:  # noqa: BLE001 - la conciliacion nunca debe tumbar la app
        logger.warning("No se pudo conciliar con Libelula: %s", exc)
        return []

    if not _exito_libelula(cuerpo):
        logger.warning("Libelula respondio con error a la conciliacion: %s", cuerpo.get("mensaje"))
        return []

    datos = cuerpo.get("datos")
    if not isinstance(datos, list):
        logger.warning("La conciliacion de Libelula vino sin lista de datos: %r", cuerpo)
        return []

    logger.info("Libelula devolvio %s pagos para la conciliacion", len(datos))
    return datos


def confirmar_pago(transaccion_id: str, desde: datetime, hasta: datetime) -> dict | None:
    """Busca un pago en la pasarela y devuelve el registro, o None si aun no esta.

    Es la pieza que hace segura la notificacion: el endpoint no se cree lo que le
    digan, va a preguntarle a Libelula. Un `None` significa "no hay evidencia de
    pago todavia", que no es lo mismo que "no se pago": la pasarela puede tardar
    en liquidar, asi que el cobro se deja pendiente en vez de rechazarse.
    """
    if not transaccion_id:
        return None

    objetivo = transaccion_id.strip()
    for registro in consultar_pagos(desde, hasta):
        if str(registro.get("id_transaccion") or "").strip() == objetivo:
            return registro

    logger.info("La pasarela todavia no registra el pago de %s", objetivo)
    return None
