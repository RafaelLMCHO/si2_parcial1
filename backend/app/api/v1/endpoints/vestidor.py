"""CU-07 · Vestidor virtual (probador de ropa con Decart).

Dos modalidades sobre la misma API de Decart:

  - `/virtual/prueba` (foto→foto): el cliente sube una foto (o la toma con la
    cámara) y el backend la procesa en la Process API (`lucy-image-2`) junto
    con la foto de la prenda del catálogo. Devuelve la imagen editada en bytes.
    Es el flujo habitual: cada generación se factura con tarifa plana
    ($0.01 en 480p / $0.02 en 720p), no por segundo.

  - `/virtual/token` (realtime): emite el token efímero para el flujo WebRTC
    con `lucy-vton-latest`. Se conserva por compatibilidad: el frontend actual
    usa el flujo por foto en ambas plataformas (web y móvil).
"""
from pathlib import Path

import httpx
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import Response
from sqlalchemy.orm import Session

from app.api.v1.endpoints.bitacora import registrar
from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.models import Producto, Usuario
from app.services import decart_service
from app.services.decart_service import DecartNoDisponibleError

router = APIRouter()

# Las imágenes de prenda viven en `backend/static/uploads/...` (mismo volumen
# que sirve `/static`). `imagen_url` guarda la ruta relativa, p. ej.
# `/static/uploads/producto_3.jpg`; aquí se resuelve contra el disco.
_UPLOADS_DIR = Path(__file__).resolve().parents[4] / "static" / "uploads"

# Tope de tamaño de la foto del cliente (JPEG/PNG ordinarios quedan muy por
# debajo; es un freno a abusos de memoria más que un control de calidad).
_MAX_FOTO_BYTES = 10 * 1024 * 1024
_TIPOS_FOTO_VALIDOS = {"image/jpeg", "image/png", "image/webp"}


def _media_type_de(imagen: bytes) -> str:
    """Detecta el tipo real de la imagen que devuelve la Process API.

    Decart puede responder JPEG, PNG o WebP. Los navegadores y Flutter
    decodifican la imagen por su magic, pero conviene que el header
    `Content-Type` coincida para que ningún cliente lo rechace.
    """
    if imagen[:4] == b"\x89PNG":
        return "image/png"
    if imagen[:3] == b"\xff\xd8\xff":
        return "image/jpeg"
    if imagen[:4] == b"RIFF" and imagen[8:12] == b"WEBP":
        return "image/webp"
    return "image/jpeg"


@router.post(
    "/virtual/prueba",
    summary="Probador por foto: pone la prenda del producto en la foto del cliente (CU-07)",
    response_class=Response,
    responses={200: {"content": {"image/jpeg": {}}}},
)
async def probar_con_foto(
    id_producto: int = Form(...),
    persona: UploadFile = File(...),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_current_user),
):
    """Recibe la foto del cliente y devuelve la misma foto con la prenda puesta.

    El prompt del modelo se arma con el `prompt_vestidor` del producto (que ya
    describe la prenda y su región: upper/lower body garment, outfit, hat) más
    la instrucción de respetar la foto de referencia, que es la imagen del
    catálogo.

    Errores:
      - 0 créditos o clave rechazada → 502 con el motivo real de Decart, para
        que la UI lo muestre tal cual (igual que en el flujo realtime).
      - Sin `DECART_API_KEY` → 501 (el cliente lo distingue para deshabilitar
        el botón con el mensaje correcto).
    """
    if persona.content_type not in _TIPOS_FOTO_VALIDOS:
        raise HTTPException(
            status_code=400,
            detail="La foto debe ser JPEG, PNG o WebP.",
        )

    foto_bytes = await persona.read()
    if not foto_bytes:
        raise HTTPException(status_code=400, detail="La foto viene vacía.")
    if len(foto_bytes) > _MAX_FOTO_BYTES:
        raise HTTPException(
            status_code=400,
            detail="La foto es demasiado grande (máximo 10 MB).",
        )

    producto = db.get(Producto, id_producto)
    if producto is None or not producto.activo:
        raise HTTPException(status_code=404, detail="Producto no encontrado.")
    if not producto.imagen_url or not producto.prompt_vestidor:
        raise HTTPException(
            status_code=400,
            detail=(
                "Este producto aún no está listo para el probador: "
                "le falta la imagen o la descripción."
            ),
        )

    # Obtener los bytes de la imagen de la prenda (soporta URLs remotas y rutas locales)
    prenda_bytes = None
    if producto.imagen_url.startswith(("http://", "https://")):
        try:
            async with httpx.AsyncClient(timeout=20.0, follow_redirects=True) as client:
                resp = await client.get(producto.imagen_url)
                resp.raise_for_status()
                prenda_bytes = resp.content
        except Exception as exc:
            raise HTTPException(
                status_code=500,
                detail=f"No se pudo descargar la imagen de la prenda ({exc}).",
            ) from exc
    else:
        nombre_archivo = Path(producto.imagen_url).name
        base_static = Path(__file__).resolve().parents[4] / "static"
        candidatos = [
            _UPLOADS_DIR / nombre_archivo,
            base_static / "productos" / nombre_archivo,
            base_static / producto.imagen_url.lstrip("/static/").lstrip("/"),
        ]
        for cand in candidatos:
            if cand.is_file():
                try:
                    prenda_bytes = cand.read_bytes()
                    break
                except OSError:
                    pass

        if prenda_bytes is None:
            raise HTTPException(
                status_code=500,
                detail=f"La imagen de la prenda no está disponible en el servidor ({nombre_archivo}).",
            )

    if prenda_bytes.startswith(b"<?xml") or prenda_bytes.startswith(b"<svg") or producto.imagen_url.lower().endswith(".svg"):
        raise HTTPException(
            status_code=400,
            detail="La imagen de la prenda está en formato vectorial SVG y no es compatible con el probador IA. Se requiere una imagen JPG o PNG.",
        )

    prompt = (
        f"{producto.prompt_vestidor}. Use the garment in the reference image "
        "and match its exact color, fabric and details."
    )
    try:
        imagen = decart_service.procesar_try_on_foto(
            foto_bytes=foto_bytes,
            prompt=prompt,
            prenda_bytes=prenda_bytes,
        )
    except DecartNoDisponibleError as exc:
        causa = str(exc)
        if causa.startswith("El probador por foto está deshabilitado"):
            raise HTTPException(status_code=501, detail=causa) from exc
        raise HTTPException(status_code=502, detail=causa) from exc

    registrar(
        db,
        usuario_id=usuario.id_usuario,
        accion="PRUEBA_VESTIDOR_FOTO",
        entidad="Producto",
        entidad_id=producto.id_producto,
        detalle=(
            f"Probador por foto ({producto.nombre}) para {usuario.email}."
        ),
    )
    return Response(content=imagen, media_type=_media_type_de(imagen))


@router.post(
    "/virtual/token",
    summary="Token efímero del vestidor virtual (CU-07, modo realtime)",
)
def token_virtual(
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_current_user),
):
    """Emite un token de cliente efímero (`ek_`, firmado por Decart) para
    conectar la cámara del cliente al modelo `lucy-vton-latest`.

    El frontend lo usa tal cual en `createDecartClient({ apiKey })`.

    Hay dos fallos distintos y se reportan distinto a propósito:
      - Sin `DECART_API_KEY` configurada devuelve un token simulado y la UI avisa.
      - Con clave configurada pero Decart rechazándola devuelve 502 con el motivo
        real (clave inválida, modelo sin acceso, cuota agotada), que es lo que
        permite corregir la configuración sin adivinar.
    """
    try:
        token = decart_service.crear_token_realtime()
    except DecartNoDisponibleError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    registrar(
        db,
        usuario_id=usuario.id_usuario,
        accion="CONSULTA_VESTIDOR_VIRTUAL",
        entidad="vestidor_virtual",
        detalle=(
            f"Token realtime {'simulado' if token['simulado'] else 'real'} "
            f"para {usuario.email} (modelo {token['modelo']})."
        ),
    )
    return token