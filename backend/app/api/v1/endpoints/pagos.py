from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy.orm import Session, joinedload

from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.models import Pago, Pedido, Usuario

router = APIRouter()


class WebhookPayload(BaseModel):
    transaccion_id: str
    monto: float
    estado: str = "aprobado"
    proveedor: str = "STRIPE"


class ReembolsoResponse(BaseModel):
    id_pago: int
    transaccion_id: str | None
    monto: float
    estado: str
    mensaje: str


@router.get(
    "/",
    summary="Listar transacciones de pago (CU12)",
)
def listar_pagos(
    estado: str | None = Query(None, description="Filtrar por estado: pendiente, aprobado, rechazado, reembolsado"),
    proveedor: str | None = Query(None, description="Filtrar por proveedor: STRIPE, Punto de Venta, QR"),
    db: Session = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    if current.rol not in ("admin", "encargado", "cajero"):
        raise HTTPException(status_code=403, detail="Acceso no autorizado a la gestión de pagos")

    query = db.query(Pago).options(
        joinedload(Pago.pedido).joinedload(Pedido.usuario),
        joinedload(Pago.pedido).joinedload(Pedido.sucursal),
    )

    if estado:
        query = query.filter(Pago.estado == estado)
    if proveedor:
        query = query.filter(Pago.proveedor_pago == proveedor)

    pagos = query.order_by(Pago.fecha_pago.desc()).all()

    res = []
    for p in pagos:
        res.append({
            "id_pago": p.id_pago,
            "pedido_id": p.pedido_id,
            "monto": float(p.monto),
            "proveedor_pago": p.proveedor_pago,
            "transaccion_id": p.transaccion_id,
            "estado": p.estado.value if hasattr(p.estado, "value") else str(p.estado),
            "fecha_pago": p.fecha_pago.isoformat() if p.fecha_pago else None,
            "cliente_nombre": p.pedido.usuario.nombre if p.pedido and p.pedido.usuario else "Desconocido",
            "cliente_email": p.pedido.usuario.email if p.pedido and p.pedido.usuario else "—",
            "sucursal_nombre": p.pedido.sucursal.nombre if p.pedido and p.pedido.sucursal else "En Línea",
        })
    return res


@router.get(
    "/{id_pago}",
    summary="Obtener detalle de una transacción de pago",
)
def detalle_pago(
    id_pago: int,
    db: Session = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    pago = (
        db.query(Pago)
        .options(
            joinedload(Pago.pedido).joinedload(Pedido.usuario),
            joinedload(Pago.pedido).joinedload(Pedido.sucursal),
        )
        .filter(Pago.id_pago == id_pago)
        .first()
    )
    if not pago:
        raise HTTPException(status_code=404, detail="Pago no encontrado")

    if current.rol == "cliente" and (not pago.pedido or pago.pedido.usuario_id != current.id_usuario):
        raise HTTPException(status_code=403, detail="No autorizado")

    return {
        "id_pago": pago.id_pago,
        "pedido_id": pago.pedido_id,
        "monto": float(pago.monto),
        "proveedor_pago": pago.proveedor_pago,
        "transaccion_id": pago.transaccion_id,
        "estado": pago.estado.value if hasattr(pago.estado, "value") else str(pago.estado),
        "fecha_pago": pago.fecha_pago.isoformat() if pago.fecha_pago else None,
        "cliente_nombre": pago.pedido.usuario.nombre if pago.pedido and pago.pedido.usuario else "Desconocido",
        "cliente_email": pago.pedido.usuario.email if pago.pedido and pago.pedido.usuario else "—",
        "sucursal_nombre": pago.pedido.sucursal.nombre if pago.pedido and pago.pedido.sucursal else "En Línea",
    }


@router.post(
    "/webhook",
    summary="Webhook de simulación e idempotencia de pasarela Stripe (CU12)",
)
def webhook_pasarela(
    payload: WebhookPayload,
    db: Session = Depends(get_db),
):
    # Verificación de Idempotencia: evitar procesar la misma transacción dos veces
    existente = db.query(Pago).filter(Pago.transaccion_id == payload.transaccion_id).first()
    if existente:
        return {
            "status": "duplicado",
            "mensaje": f"La transacción '{payload.transaccion_id}' ya fue procesada anteriormente.",
            "id_pago": existente.id_pago,
        }

    return {
        "status": "recibido",
        "transaccion_id": payload.transaccion_id,
        "mensaje": "Evento de webhook procesado correctamente.",
    }


@router.post(
    "/{id_pago}/reembolsar",
    response_model=ReembolsoResponse,
    summary="Procesar reembolso/anulación de pago (CU12)",
)
def reembolsar_pago(
    id_pago: int,
    db: Session = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    if current.rol not in ("admin", "encargado"):
        raise HTTPException(status_code=403, detail="Solo administradores o encargados pueden autorizar reembolsos")

    pago = db.get(Pago, id_pago)
    if not pago:
        raise HTTPException(status_code=404, detail="Pago no encontrado")

    estado_str = pago.estado.value if hasattr(pago.estado, "value") else str(pago.estado)
    if estado_str == "reembolsado":
        raise HTTPException(status_code=400, detail="Este pago ya se encuentra reembolsado")
    if estado_str != "aprobado":
        raise HTTPException(status_code=400, detail="Solo se pueden reembolsar pagos en estado aprobado")

    pago.estado = "reembolsado"

    if pago.pedido:
        pago.pedido.estado = "cancelado"

    db.commit()
    db.refresh(pago)

    return ReembolsoResponse(
        id_pago=pago.id_pago,
        transaccion_id=pago.transaccion_id,
        monto=float(pago.monto),
        estado="reembolsado",
        mensaje=f"Reembolso procesado exitosamente por Bs. {float(pago.monto):.2f}",
    )
