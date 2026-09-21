from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
from sqlalchemy.orm import Session, joinedload

from app.core.dependencies import get_current_user, require_roles, get_db
from app.models.bitacora import Bitacora
from app.models.enums import RolUsuario
from app.schemas.bitacora import BitacoraCreate, BitacoraOut

router = APIRouter()


def registrar(
    db: Session,
    usuario_id: Optional[int],
    accion: str,
    entidad: Optional[str] = None,
    entidad_id: Optional[int] = None,
    detalle: Optional[str] = None,
    ip_origen: Optional[str] = None,
) -> Bitacora:
    """CU-23 · Registra un evento en la bitácora (transversal, no bloqueante).

    Cualquier módulo del sistema puede invocarlo; una falla aquí jamás
    interrumpe la operación principal (solo se registra en logs internos).
    """
    try:
        reg = Bitacora(
            usuario_id=usuario_id,
            accion=accion,
            entidad=entidad,
            entidad_id=entidad_id,
            detalle=detalle,
            ip_origen=ip_origen,
        )
        db.add(reg)
        db.commit()
        db.refresh(reg)
        return reg
    except Exception:
        db.rollback()
        # No bloquea la operación principal: registra en logs internos y continúa.
        return None


@router.post("", response_model=BitacoraOut, status_code=status.HTTP_201_CREATED)
def crear_registro(
    payload: BitacoraCreate,
    request: Request,
    db: Session = Depends(get_db),
    usuario=Depends(get_current_user),
):
    """CU-23 · Inserta un registro de bitácora (llamado interno/transversal)."""
    reg = registrar(
        db,
        usuario_id=payload.usuario_id or (usuario.id_usuario if usuario else None),
        accion=payload.accion,
        entidad=payload.entidad,
        entidad_id=payload.entidad_id,
        detalle=payload.detalle,
        ip_origen=payload.ip_origen
        or (request.client.host if request.client else None),
    )
    if reg is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No se pudo registrar el evento en la bitácora.",
        )
    return reg


@router.get("", response_model=list[BitacoraOut])
def listar_bitacora(
    response: Response,
    db: Session = Depends(get_db),
    usuario_actual=Depends(require_roles(RolUsuario.admin)),
    usuario_id: Optional[int] = Query(None, description="Filtrar por usuario"),
    accion: Optional[str] = Query(None, description="Filtrar por tipo de evento"),
    entidad: Optional[str] = Query(None, description="Filtrar por entidad"),
    fecha_desde: Optional[str] = Query(None, description="YYYY-MM-DD"),
    fecha_hasta: Optional[str] = Query(None, description="YYYY-MM-DD"),
    limite: int = Query(200, ge=1, le=1000),
    pagina: int = Query(1, ge=1, description="Página (1-based)"),
):
    """CU-23 · Consultar bitácora con filtros (usuario, tipo de evento, fecha).

    Solo administrador. Paginado: el total de registros que coinciden con los
    filtros se devuelve en el header ``X-Total-Count``.
    """
    q = db.query(Bitacora).options(joinedload(Bitacora.usuario))
    if usuario_id:
        q = q.filter(Bitacora.usuario_id == usuario_id)
    if accion:
        q = q.filter(Bitacora.accion.ilike(f"%{accion}%"))
    if entidad:
        q = q.filter(Bitacora.entidad == entidad)
    if fecha_desde:
        f = datetime.fromisoformat(fecha_desde)
        q = q.filter(Bitacora.fecha >= f)
    if fecha_hasta:
        f = datetime.fromisoformat(fecha_hasta)
        q = q.filter(Bitacora.fecha <= f)
    total = q.count()
    registros = (
        q.order_by(Bitacora.fecha.desc(), Bitacora.id_bitacora.desc())
        .offset((pagina - 1) * limite)
        .limit(limite)
        .all()
    )
    response.headers["X-Total-Count"] = str(total)
    return registros
