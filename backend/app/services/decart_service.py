"""Integración con Decart (vestidor virtual / virtual try-on, CU-07).

Replica el patrón real/simulado de Stripe: si la clave del proveedor es real
(válida y no placeholder), se conecta a la API de Decart; en caso contrario
opera en modo simulado devolviendo respuestas simuladas sin llamar a la API.

Flujo soportado (CU-07):
  - Realtime: este servicio crea un token de cliente efímero (`ek_...`) contra
    `POST /v1/client/tokens` usando la API key permanente, y lo devuelve al
    frontend. El navegador se conecta con ese token al modelo
    `lucy-vton-latest` por WebRTC (cámara en vivo). La clave permanente nunca
    sale del backend.
  - Foto→foto: `procesar_try_on_foto` llama a la Process API
    (`POST /v1/generate/lucy-image-2`) con la foto del cliente y la foto de la
    prenda como `reference_image`. Devuelve la imagen editada en bytes con
    tarifa plana por generación ($0.01 480p / $0.02 720p), sin facturar por
    tiempo.

Documentación Decart: https://docs.platform.decart.ai
"""
import logging
import random
from datetime import datetime, timedelta, timezone

import httpx

from app.core.config import get_settings

logger = logging.getLogger(__name__)

# Motivos de clave inválida ya reportados, para no repetir el warning en cada
# intento de abrir el probador.
_CLAVES_avisadas: set[str] = set()

# Origenes desde los que se puede usar el token. El navegador los manda en el
# header `Origin` de la conexión WebRTC y Decart los valida al abrirla. La lista
# sale de `DECART_ORIGENES_PERMITIDOS` para no quedar desfasada con el CORS.
def _origenes_permitidos() -> list[str]:
    crudo = get_settings().DECART_ORIGENES_PERMITIDOS or ""
    return [o.strip() for o in crudo.split(",") if o.strip()]

# Tope de duración de una sesión realtime. Es el freno de costo: el modelo se
# factura por segundo de generación activa ($0.02/s en lucy-vton-3.5), así que
# sin este límite un modal que el usuario deja abierto sigue consumiendo.
_MAX_SESION_SEGUNDOS = 120


def decart_operativa() -> bool:
    """True si hay una clave real de Decart configurada (no placeholder).

    Una clave real de Decart comienza con `dct_` y nunca contiene la cadena
    `placeholder`.
    """
    clave = (get_settings().DECART_API_KEY or "").strip()
    if not clave:
        return False
    return _motivo_clave_invalida() is None


def _motivo_clave_invalida() -> str | None:
    """Por qué la clave no sirve, o None si es válida.

    Existe para el caso de una clave pegada con un error tonto (quedó el
    espacio, se cortó, es la de otro proyecto). Sin esto el sistema la trata
    como "sin clave" y en pantalla dice que falta configurarla, cuando en
    realidad hay algo mal pegado en el .env.
    """
    clave = (get_settings().DECART_API_KEY or "").strip()
    if not clave:
        # Sin nada configurado: es el caso legitimo de "no hay clave", no una
        # clave mal pegada. No es un error que haya que reportar.
        return None
    if "placeholder" in clave:
        return "DECART_API_KEY sigue siendo el valor placeholder, no una clave real"
    if not clave.startswith("dct_"):
        return f"DECART_API_KEY no empieza con 'dct_' (empieza con '{clave[:6]}...')"
    if len(clave) <= 25:
        return f"DECART_API_KEY es demasiado corta ({len(clave)} caracteres)"
    return None


def _base_url() -> str:
    return (get_settings().DECART_BASE_URL or "https://api.decart.ai").rstrip("/")


def _headers() -> dict:
    return {
        "x-api-key": get_settings().DECART_API_KEY,
        "Content-Type": "application/json",
    }


def _token_simulado(ttl_segundos: int) -> dict:
    """Token de mentira para poder probar la UI sin una clave configurada."""
    return {
        "api_key": "ek_simulado_" + _rand(24),
        "expires_at": (
            datetime.now(timezone.utc) + timedelta(seconds=ttl_segundos)
        ).isoformat(),
        "modelo": get_settings().DECART_VION_MODELO,
        "max_sesion_segundos": _MAX_SESION_SEGUNDOS,
        "simulado": True,
    }


class DecartNoDisponibleError(Exception):
    """Hay clave configurada pero Decart no devolvió un token utilizable.

    Se distingue a propósito del caso "no hay clave": si una clave mal pegada
    cayera en modo simulado, en pantalla se vería exactamente lo mismo que
    cuando simplemente falta configurarla, y no habría forma de saber cuál de
    las dos cosas pasó. Acá se propaga el motivo real de Decart.
    """


def crear_token_realtime(ttl_segundos: int = 600) -> dict:
    """Crea un token efímero de cliente para el flujo realtime (cámara en vivo).

    Retorna:
      - Si hay clave real: {api_key, expires_at, modelo, max_sesion_segundos,
        simulado: False}
      - Si no hay clave: lo mismo pero con `simulado: True`, sin llamar a la API.

    El token viene firmado por Decart y el gateway lo valida sin consultar la
    clave, por eso el navegador puede usarlo directamente.

    Si hay clave pero Decart falla, levanta `DecartNoDisponibleError` con el
    motivo real en vez de caer a simulado: una clave mal configurada no puede
    terminar pareciéndose a "la plataforma no está configurada".
    """
    settings = get_settings()
    if not decart_operativa():
        # Si hay algo escrito pero no es una clave usable, se avisa una sola vez
        # por valor: el síntoma en pantalla sería idéntico al de "sin clave".
        motivo = _motivo_clave_invalida()
        if motivo:
            if motivo not in _CLAVES_avisadas:
                _CLAVES_avisadas.add(motivo)
                logger.warning("Probador con cámara deshabilitado: %s", motivo)
        return _token_simulado(ttl_segundos)

    url = f"{_base_url()}/v1/client/tokens"
    payload = {
        "expiresIn": ttl_segundos,
        # La API key permanente puede usarla cualquier modelo: se acota solo al
        # de try-on, que es el único que este flujo necesita.
        "allowedModels": [settings.DECART_VION_MODELO],
        "allowedOrigins": _origenes_permitidos(),
        "constraints": {"realtime": {"maxSessionDuration": _MAX_SESION_SEGUNDOS}},
    }
    try:
        r = httpx.post(url, headers=_headers(), json=payload, timeout=30)
        r.raise_for_status()
        data = r.json()
    except httpx.HTTPStatusError as exc:
        # La respuesta de Decart dice por qué (clave inválida, modelo sin acceso,
        # cuota). Se devuelve tal cual: es la única forma de diagnosticar.
        detalle = _cuerpo_de_error(exc.response)
        logger.error("Decart rechazo el token (%s): %s", exc.response.status_code, detalle)
        raise DecartNoDisponibleError(
            f"Decart respondió {exc.response.status_code}: {detalle}"
        ) from exc
    except Exception as exc:  # noqa: BLE001 - red caída, timeout, JSON inválido
        logger.error("No se pudo contactar a Decart: %s", exc)
        raise DecartNoDisponibleError(
            f"No se pudo contactar a Decart ({type(exc).__name__}: {exc})"
        ) from exc

    api_key = data.get("apiKey") or data.get("api_key")
    if not api_key:
        logger.error("Decart respondió 200 sin token: %s", data)
        raise DecartNoDisponibleError(
            "Decart respondió 200 pero sin token de cliente."
        )
    return {
        "api_key": api_key,
        "expires_at": data.get("expiresAt") or data.get("expires_at"),
        "modelo": settings.DECART_VION_MODELO,
        "max_sesion_segundos": _MAX_SESION_SEGUNDOS,
        "simulado": False,
    }


def procesar_try_on_foto(
    foto_bytes: bytes,
    prompt: str,
    prenda_bytes: bytes,
    resolution: str | None = None,
) -> bytes:
    """Genera la foto con la prenda puesta vía la Process API de Decart.

    Reemplaza al flujo realtime como la forma habitual de probar ropa: el
    cliente sube una foto (o la toma con la cámara) y el backend la manda a
    `POST /v1/generate/lucy-image-2` junto con la foto de la prenda como
    `reference_image`. La respuesta es directa (la imagen editada en bytes),
    sin sesiones largas que sigan facturando por segundo.

    Se levanta `DecartNoDisponibleError` tanto cuando falta la clave como
    cuando Decart rechaza la generación, para que el detalle real llegue a
    pantalla (500-placeholder, sin crédito, moderación, etc.).
    """
    settings = get_settings()
    if not decart_operativa():
        motivo = _motivo_clave_invalida()
        if motivo and motivo not in _CLAVES_avisadas:
            _CLAVES_avisadas.add(motivo)
            logger.warning("Probador con foto deshabilitado: %s", motivo)
        raise DecartNoDisponibleError(
            "El probador por foto está deshabilitado: falta configurar la clave "
            "de Decart (DECART_API_KEY) en el backend."
        )

    resolucion = (resolution or settings.DECART_PROCESS_RESOLUCION or "480p")
    url = f"{_base_url()}/v1/generate/lucy-image-2"
    # Multipart, por eso aquí no se manda el header Content-Type (httpx asigna
    # el boundary del form) y el prompt/resolución van en `data`.
    archivos = [
        ("data", ("foto.jpg", foto_bytes, "image/jpeg")),
        ("reference_image", ("prenda.jpg", prenda_bytes, "image/jpeg")),
    ]
    datos = {"prompt": prompt, "resolution": resolucion}
    try:
        r = httpx.post(
            url,
            headers={"x-api-key": settings.DECART_API_KEY},
            files=archivos,
            data=datos,
            timeout=120,
        )
        r.raise_for_status()
    except httpx.HTTPStatusError as exc:
        detalle = _cuerpo_de_error(exc.response)
        logger.error(
            "Decart rechazo la generacion foto (%s): %s",
            exc.response.status_code,
            detalle,
        )
        raise DecartNoDisponibleError(
            f"Decart respondió {exc.response.status_code}: {detalle}"
        ) from exc
    except Exception as exc:  # noqa: BLE001 - red caída, timeout, imagen rara
        logger.error("No se pudo contactar a Decart (foto): %s", exc)
        raise DecartNoDisponibleError(
            f"No se pudo contactar a Decart ({type(exc).__name__}: {exc})"
        ) from exc

    if not r.content:
        logger.error("Decart respondió 200 sin imagen.")
        raise DecartNoDisponibleError("Decart respondió sin imagen editada.")
    return r.content


def _cuerpo_de_error(respuesta: httpx.Response) -> str:
    """Extrae el mensaje de error de Decart, que viene en JSON o en texto."""
    try:
        data = respuesta.json()
    except Exception:  # noqa: BLE001 - el cuerpo no era JSON
        return (respuesta.text or "").strip() or "sin detalle"
    if isinstance(data, dict):
        for clave in ("error", "message", "detail", "error_description"):
            if data.get(clave):
                return str(data[clave])
    return str(data)


def _rand(n: int) -> str:
    return "".join(random.choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(n))
