from typing import Annotated

from fastapi import (
    APIRouter,
    Depends,
    File,
    HTTPException,
    Query,
    UploadFile,
    status,
)
from sqlalchemy.orm import Session

from app.api.v1.endpoints.bitacora import registrar
from app.core.dependencies import get_current_user
from app.core.config import get_settings
from app.db.session import get_db
from app.models import Usuario
from app.services import decart_service

router = APIRouter()

_MAX_TAM = 50 * 1024 * 1024  # 50 MB


def _campo_obligatorio(
    campo: UploadFile,
    nombre: str,
    extensiones: tuple[str, ...],
):
    if campo is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Falta el campo '{nombre}'.",
        )
    nombre_archivo = (campo.filename or "").lower()
    if not any(nombre_archivo.endswith(e) for e in extensiones):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"El campo '{nombre}' debe ser {', '.join(extensiones)}.",
        )
    return campo


async def _leer_limite(campo: UploadFile, nombre: str) -> bytes:
    contenido = await campo.read()
    if len(contenido) > _MAX_TAM:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"'{nombre}' supera el l��mite de 50 MB.",
        )
    return contenido


@router.post(
    "/virtual/token",
    summary="Token ef��mero del vestidor virtual (CU-07, modo realtime)",
)
def token_virtual(
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_current_user),
):
    """Emite un token de cliente ef��mero (``ek_``, TTL 10 min) para conectar la
    c��mara del cliente al flujo realtime de Decart, o un token simulado si la
    plataforma no est�� operativa."""
    settings = get_settings()
    token_info = decart_service.crear_token_realtime(usuario)
    registrar(
        db,
        usuario_id=usuario.id_usuario,
        accion="CONSULTA_VESTIDOR_VIRTUAL",
        entidad="vestidor_virtual",
        detalle=(
            f"Token realtime {token_info['tipo']} para {usuario.email} "
            f"(simulado={'si' if token_info['simulado'] else 'no'})."
        ),
    )
    return token_info


@router.post(
    "/virtual/tryon",
    summary="Probar prenda con foto del cliente (CU-07, modo batch/imagen)",
)
async def probar_prenda(
    persona: Annotated[UploadFile, File(description="Foto del cliente (JPG/PNG)")],
    prenda: Annotated[UploadFile, File(description="Foto o recorte de la prenda (JPG/PNG)")],
    prompt: Annotated[str | None, Query(description="Descripci��n opcional de la prenda")] = None,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_current_user),
):
    """Lanza un job batch de virtual try-on: sube la foto de la persona y la
    imagen de la prenda, y consulta el resultado del vestidor virtual."""
    _campo_obligatorio(persona, "persona", (".jpg", ".jpeg", ".png"))
    _campo_obligatorio(prenda, "prenda", (".jpg", ".jpeg", ".png"))
    persona_b = await _leer_limite(persona, "persona")
    prenda_b = await _leer_limite(prenda, "prenda")
    job = decart_service.lanzar_tryon_batch(
        db,
        usuario_id=usuario.id_usuario,
        persona_bytes=persona_b,
        prenda_bytes=prenda_b,
        prompt=prompt,
    )
    registrar(
        db,
        usuario_id=usuario.id_usuario,
        accion="PROBAR_PRENDA_VESTIDOR",
        entidad="vestidor_virtual",
        detalle=(
            f"Try-on batch {job['job_id']} para {usuario.email} "
            f"(simulado={'si' if job['simulado'] else 'no'})."
        ),
    )
    return job


@router.get(
    "/virtual/tryon/{job_id}",
    summary="Consultar estado del try-on batch (CU-07)",
)
def consultar_tryon(
    job_id: str,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_current_user),
):
    """Consulta el estado del job de virtual try-on y, si termin��, el resultado."""
    job = decart_service.consultar_job(db, job_id=job_id)
    if not job:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No existe el job solicitado.",
        )
    registrar(
        db,
        usuario_id=usuario.id_usuario,
        accion="CONSULTA_VESTIDOR_VIRTUAL",
        entidad="vestidor_virtual",
        detalle=f"Estado {job.get('estado')} para job {job_id}.",
    )
    return job
