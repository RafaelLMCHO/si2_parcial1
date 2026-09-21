import logging
from datetime import date, time as dt_time

logger = logging.getLogger(__name__)

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dependencies import encargado_required, get_current_user
from app.db.session import get_db
from app.models import (
    Inventario,
    Reserva,
    ReservaItem,
    Sucursal,
    Usuario,
)
from app.schemas.comercio import ReservaCreate, ReservaOut
from app.services.notification_service import NotificationService

router = APIRouter()

MAX_PRENDAS_POR_RESERVA = 10


def _reserva_con_items(db: Session, reserva_id: int) -> Reserva:
    reserva = (
        db.query(Reserva)
        .filter(Reserva.id_reserva == reserva_id)
        .first()
    )
    if not reserva:
        raise HTTPException(status_code=404, detail="Reserva no encontrada")
    return reserva


def _parsear_hora(valor: str) -> dt_time:
    try:
        hora, minuto = valor.split(":")
        return dt_time(int(hora), int(minuto))
    except Exception:
        raise HTTPException(
            status_code=400, detail="Formato de hora inválido. Use HH:MM."
        )


def _inventario_con_bloqueo(db: Session, variante_id: int, sucursal_id: int) -> Inventario:
    return (
        db.query(Inventario)
        .filter(
            Inventario.variante_id == variante_id,
            Inventario.sucursal_id == sucursal_id,
        )
        .with_for_update()
        .first()
    )


@router.post(
    "/", response_model=ReservaOut, status_code=status.HTTP_201_CREATED,
    summary="Crear reserva de múltiples prendas (CU8)",
)
def crear_reserva(
    data: ReservaCreate,
    db: Session = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    if current.rol != "admin" and current.rol != "cliente":
        raise HTTPException(status_code=403, detail="Solo clientes pueden reservar")

    if not data.items:
        raise HTTPException(status_code=400, detail="Debe incluir al menos una prenda")

    total_prendas = sum(item.cantidad for item in data.items)
    if total_prendas > MAX_PRENDAS_POR_RESERVA:
        raise HTTPException(
            status_code=400,
            detail=f"Solo se permite reservar hasta {MAX_PRENDAS_POR_RESERVA} prendas por reserva",
        )

    sucursal = db.query(Sucursal).filter(Sucursal.id_sucursal == data.sucursal_id).first()
    if not sucursal or not sucursal.activo:
        raise HTTPException(status_code=404, detail="Sucursal no encontrada")

    hora = _parsear_hora(data.hora_atencion)
    if hora < sucursal.horario_apertura or hora > sucursal.horario_cierre:
        raise HTTPException(
            status_code=400,
            detail=(
                f"La sucursal no atiende en el horario seleccionado. "
                f"Atendemos de {sucursal.horario_apertura:%H:%M} a {sucursal.horario_cierre:%H:%M}."
            ),
        )

    if data.fecha_reserva < date.today():
        raise HTTPException(
            status_code=400, detail="La fecha de reserva no puede ser anterior a hoy"
        )

    # Verificación de stock en tiempo real (SELECT FOR UPDATE).
    # La mutación de inventario y la bitácora las realizan los triggers
    # de la base de datos (trg_reserva_item_insert), evitando duplicar.
    for item in data.items:
        inventario = _inventario_con_bloqueo(db, item.variante_id, data.sucursal_id)
        if not inventario or inventario.cantidad_disponible < item.cantidad:
            db.rollback()
            raise HTTPException(
                status_code=409,
                detail="Lo sentimos, el stock ha cambiado, revise las cantidades disponibles",
            )

    try:
        reserva = Reserva(
            usuario_id=current.id_usuario,
            sucursal_id=data.sucursal_id,
            fecha_reserva=data.fecha_reserva,
            hora_atencion=hora,
        )
        db.add(reserva)
        db.flush()  # obtener id_reserva

        for item in data.items:
            db.add(
                ReservaItem(
                    reserva_id=reserva.id_reserva,
                    variante_id=item.variante_id,
                    cantidad=item.cantidad,
                )
            )

        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="Lo sentimos, el stock ha cambiado, revise las cantidades disponibles",
        )

    db.refresh(reserva)
    return reserva


@router.get("/pendientes", response_model=list[ReservaOut], summary="Listar reservas pendientes (Encargado/Admin)")
def list_reservas_pendientes(
    db: Session = Depends(get_db),
    current: Usuario = Depends(encargado_required),
):
    query = db.query(Reserva)
    if current.rol == "encargado":
        # Encargado: solo las de su sucursal.
        query = query.filter(Reserva.sucursal_id == current.sucursal_id)
    # Admin: ve las pendientes de todas las sucursales.
    return query.filter(Reserva.estado == "pendiente").order_by(Reserva.fecha_creacion.desc()).all()


@router.get("/", response_model=list[ReservaOut], summary="Consultar reservas (CU9)")
def list_reservas(
    db: Session = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    query = db.query(Reserva)
    if current.rol == "cliente":
        # Cliente: solo sus reservas.
        query = query.filter(Reserva.usuario_id == current.id_usuario)
    elif current.rol == "encargado":
        # Encargado: reservas de su sucursal.
        query = query.filter(Reserva.sucursal_id == current.sucursal_id)
    return query.order_by(Reserva.fecha_creacion.desc()).all()


@router.get("/{reserva_id}", response_model=ReservaOut, summary="Detalle de reserva")
def get_reserva(
    reserva_id: int,
    db: Session = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    reserva = _reserva_con_items(db, reserva_id)
    if current.rol == "cliente" and reserva.usuario_id != current.id_usuario:
        raise HTTPException(status_code=403, detail="No autorizado")
    return reserva


@router.patch(
    "/{reserva_id}/cancelar", response_model=ReservaOut,
    summary="Cancelar reserva (libera stock)",
)
def cancelar_reserva(
    reserva_id: int,
    db: Session = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    reserva = _reserva_con_items(db, reserva_id)
    if current.rol == "cliente" and reserva.usuario_id != current.id_usuario:
        raise HTTPException(status_code=403, detail="No autorizado")
    if reserva.estado == "completada":
        raise HTTPException(
            status_code=400, detail="No se puede cancelar una reserva ya completada"
        )
    if reserva.estado not in ("pendiente", "preparada"):
        raise HTTPException(status_code=400, detail="No se puede cancelar en este estado")

    # El trigger trg_reserva_cancelada libera el stock reservado y
    # registra el movimiento de inventario correspondiente.
    reserva.estado = "cancelada"
    db.commit()
    db.refresh(reserva)
    return reserva


@router.patch(
    "/{reserva_id}/preparar", response_model=ReservaOut,
    summary="Preparar reserva (encargado - CU18)",
)
def preparar_reserva(
    reserva_id: int,
    db: Session = Depends(get_db),
    current: Usuario = Depends(encargado_required),
):
    reserva = _reserva_con_items(db, reserva_id)
    if current.rol != "admin" and reserva.sucursal_id != current.sucursal_id:
        raise HTTPException(status_code=403, detail="Esta reserva pertenece a otra sucursal")
    if reserva.estado != "pendiente":
        raise HTTPException(status_code=400, detail="Solo se preparan reservas pendientes")
    reserva.estado = "preparada"
    db.commit()
    db.refresh(reserva)
    
    # Enviar notificación vía NotificationService
    cliente_email = reserva.usuario.email if reserva.usuario else "Desconocido"
    NotificationService.enviar_notificacion_reserva_preparada(cliente_email, reserva.id_reserva)
    
    return reserva


@router.patch(
    "/{reserva_id}/completar", response_model=ReservaOut,
    summary="Completar reserva (encargado)",
)
def completar_reserva(
    reserva_id: int,
    db: Session = Depends(get_db),
    _: Usuario = Depends(encargado_required),
):
    reserva = _reserva_con_items(db, reserva_id)
    if reserva.estado not in ("pendiente", "preparada"):
        raise HTTPException(status_code=400, detail="Estado inválido")
    reserva.estado = "completada"
    db.commit()
    db.refresh(reserva)
    return reserva