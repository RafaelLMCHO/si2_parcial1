"""Integraci��n con Decart (vestidor virtual / virtual try-on, CU-07).

Replica el patr��n real/simulado de Stripe: si la clave del proveedor es real
(v��lida y no placeholder), se conecta a la API de Decart; en caso contrario
opera en modo simulado devolviendo respuestas simuladas sin llamar a la API.

Flujos soportados (CU-07):
  - Realtime: token de cliente ef��mero (`ek_...`) de 10 minutos que el frontend
    usa para conectarse al modelo `lucy-vton-latest` (WebRTC, c��mara en vivo).
  - Batch: env��a una foto de la persona + imagen de la prenda a un job
    `lucy-vton-latest` y consulta su estado/resultado.

Documentaci��n Decart: https://docs.platform.decart.ai
"""
from datetime import datetime, timedelta, timezone
from typing import BinaryIO

import httpx

from app.core.config import get_settings

logger = logging.getLogger(__name__)

_MAX_TAM_ARCHIVO = 50 * 1024 * 1024  # 50 MB por archivo (video/foto)


def decart_operativa() -> bool:
    """True si hay una clave real de Decart configurada (no placeholder).

    Una clave real de Decart comienza con `dct_` y nunca contiene la cadena
    `placeholder`.
    """
    clave = (get_settings().DECART_API_KEY or "").strip()
    if not clave:
        return False
    if clave.startswith("dct_") and "placeholder" not in clave and len(clave) > 25:
        return True
    return False


def _base_url() -> str:
    return (get_settings().DECART_BASE_URL or "https://api.decart.ai").rstrip("/")


def _headers() -> dict:
    return {
        "X-API-KEY": get_settings().DECART_API_KEY,
        "Content-Type": "application/json",
    }


def crear_token_cliente(ttl_segundos: int = 600) -> dict:
    """Crea un token ef��mero de cliente para el flujo realtime (c��mara en vivo).

    Retorna:
      - Si hay clave real: {api_key: "ek_...", expires_at, simulado: False}
      - Modo simulado: {api_key: "ek_simulado_...", expires_at, simulado: True}
    """
    if not decart_operativa():
        return {
            "api_key": "ek_simulado_" + "".join(
                random.choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(24)
            ),
            "expires_at": (datetime.now(timezone.utc) + timedelta(seconds=ttl_segundos)).isoformat(),
            "simulado": True,
        }
    url = f"{_base_url()}/v1/client/tokens"
    payload = {
        "expires_in": ttl_segundos,
        "models": [settings.DECART_VTON_MODELO],
    }
    try:
        r = httpx.post(url, headers=_headers(), json=payload, timeout=30)
        r.raise_for_status()
        data = r.json()
        return {
            "api_key": data.get("api_key") or data.get("key"),
            "expires_at": data.get("expires_at"),
            "simulado": False,
        }
    except Exception as exc:  # noqa: BLE001 - cualquier error cae a simulado
        import random
        logger.warning("Decart realtime indispuesto, usando modo simulado: %s", exc)
        return {
            "api_key": "ek_simulado_" + "".join(
                random.choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(24)
            ),
            "expires_at": (datetime.now(timezone.utc) + timedelta(seconds=ttl_segundos)).isoformat(),
            "simulado": True,
        }


def lanzar_tryon_batch(
    archivo_persona: BinaryIO,
    archivo_prenda: BinaryIO,
    nombre_persona: str,
) -> dict:
    """Lanza un job batch de try-on (subir prenda + foto persona, CU-07).

    Retorna:
      - Real: {job_id, estado, simulado: False}
      - Simulado: {job_id: "job_simulado_...", estado, simulado: True}
    """
    if not decart_operativa():
        return {
            "job_id": "job_simulado_" + _rand(16),
            "estado": "completado",
            "simulado": True,
        }

    url = f"{_base_url()}/v1/jobs/{settings.DECART_VTON_MODELO}"
    headers_img = {"X-API-KEY": get_settings().DECART_API_KEY}
    try:
        persona_b = archivo_persona.read()
        prenda_b = archivo_prenda.read()
        if len(persona_b) > _MAX_TAM_ARCHIVO or len(prenda_b) > _MAX_TAM_ARCHIVO:
            raise ValueError("Archivo supera el l��mite de 50 MB")
        files = {
            "data": (nombre_persona or "persona.mp4", persona_b, "video/mp4"),
            "image": ("prenda.jpg", prenda_b, "image/jpeg"),
        }
        r = httpx.post(url, headers=headers_img, files=files, timeout=120)
        r.raise_for_status()
        data = r.json()
        return {
            "job_id": data.get("job_id"),
            "estado": data.get("status", "en_proceso"),
            "simulado": False,
        }
    except Exception as exc:  # noqa: BLE001
        logger.warning("Decart batch indispuesto, usando modo simulado: %s", exc)
        return {
            "job_id": "job_simulado_" + _rand(16),
            "estado": "completado",
            "simulado": True,
        }


def consultar_job(job_id: str) -> dict:
    """Consulta el estado de un job de try-on (real o simulado)."""
    if job_id.startswith("job_simulado_"):
        return {
            "job_id": job_id,
            "estado": "completado",
            "resultado_url": None,
            "simulado": True,
        }
    url = f"{_base_url()}/v1/jobs/{job_id}"
    headers_img = {"X-API-KEY": get_settings().DECART_API_KEY}
    try:
        r = httpx.get(url, headers=headers_img, timeout=30)
        r.raise_for_status()
        data = r.json()
        return {
            "job_id": job_id,
            "estado": data.get("status", "en_proceso"),
            "resultado_url": data.get("content") or data.get("resultado"),
            "simulado": False,
        }
    except Exception as exc:  # noqa: BLE001
        logger.warning("No se pudo consultar job Decart %s: %s", job_id, exc)
        return {"job_id": job_id, "estado": "desconocido", "resultado_url": None, "simulado": False}


def _rand(n: int) -> str:
    import random
    return "".join(random.choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(n))
