import logging
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel
from sqlalchemy.orm import Session, joinedload

from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.models import Pago, Pedido, Usuario
from app.services.estado_pago_service import (
    estado_texto,
    resolver_pago_confirmado,
)
from app.services.qr_service import confirmar_pago, qr_operativa

logger = logging.getLogger(__name__)

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


class WebhookQrPayload(BaseModel):
    """Notificacion de pago que envia la pasarela QR.

    El manual de Libelula documenta la notificacion como un GET a
    `callback_url` con el identificador de la deuda en el query string, bajo el
    nombre `transaction_id`. Se aceptan tambien los nombres que usan otras
    versiones, y un cuerpo JSON, porque la forma exacta depende de la version
    del manual con la que se integre.

    De forma deliberada NO se declara ningun campo de estado, monto ni moneda.
    Aunque vinieran, no se usarian para aprobar: el estado real se consulta
    contra la pasarela. Aceptarlos y hacer caso omiso daria una falsa sensacion
    de que la notificacion manda en algo.
    """

    transaction_id: str | None = None
    transaccion_id: str | None = None
    id_transaccion: str | None = None
    identificador_deuda: str | None = None

    def referencia(self) -> str | None:
        return (
            self.transaction_id
            or self.transaccion_id
            or self.id_transaccion
            or self.identificador_deuda
            or ""
        ).strip() or None


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
            "estado": estado_texto(p.estado),
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
        "estado": estado_texto(pago.estado),
        "fecha_pago": pago.fecha_pago.isoformat() if pago.fecha_pago else None,
        "cliente_nombre": pago.pedido.usuario.nombre if pago.pedido and pago.pedido.usuario else "Desconocido",
        "cliente_email": pago.pedido.usuario.email if pago.pedido and pago.pedido.usuario else "—",
        "sucursal_nombre": pago.pedido.sucursal.nombre if pago.pedido and pago.pedido.sucursal else "En Línea",
    }


def _cobro_por_referencia(db: Session, referencia: str) -> Pago | None:
    return (
        db.query(Pago)
        .filter(Pago.transaccion_id == referencia)
        .order_by(Pago.id_pago.desc())
        .first()
    )


def _resolver_cobro_qr(db: Session, referencia: str | None):
    """Localiza el cobro que la notificacion menciona, o explica por que no puede.

    Devuelve un `(pago, error)` donde `error` es un `(status, detalle)` para
    responder sin seguir.

    Que no exija token es deliberado. Libelula notifica con un GET a
    `callback_url` que solo lleva el identificador de la deuda: no hay firma
    que verificar, y pedir un token propio dejaria el webhook en 403 para
    siempre. Como la notificacion NO aprueba nada por si sola (ver
    `_procesar_notificacion_qr`), que cualquiera pueda dispararla no convierte el
    producto en gratis: lo unico que consigue es que se pregunte a la pasarela.
    """
    if not referencia:
        return None, (400, "La notificacion no trae referencia de transaccion")

    pago = _cobro_por_referencia(db, referencia)
    if pago is None:
        logger.warning("Notificacion QR para una transaccion desconocida: %s", referencia)
        return None, (404, "Transaccion QR no encontrada")

    if pago.proveedor_pago == "SIMULADO":
        # Un cobro simulado no tiene pasarela detras que lo confirme: solo
        # puede aprobarse desde el punto de venta.
        return None, (409, "Un cobro simulado no se confirma por webhook")

    return pago, None


def _ventana_de_conciliacion(pago: Pago) -> tuple[datetime, datetime]:
    """Rango de fechas que se consulta a la pasarela para encontrar este cobro.

    Libelula solo permite filtrar `consultar_pagos` por fecha, sin consulta por
    transaccion. Se cubre desde un poco antes de que el cobro se creara (por si
    la pasarela registro la deuda con otra hora) hasta ahora, con margen para
    que un pago a medianoche no quede fuera.
    """
    creado = (pago.datos_gateway or {}).get("creado")
    desde = None
    if creado:
        try:
            desde = datetime.fromisoformat(creado)
        except (TypeError, ValueError):
            desde = None
    if desde is None:
        # Sin fecha de creacion conocida, se mira hacia atras un dia.
        desde = datetime.now(timezone.utc) - timedelta(days=1)
    if desde.tzinfo is None:
        desde = desde.replace(tzinfo=timezone.utc)
    return desde - timedelta(minutes=5), datetime.now(timezone.utc) + timedelta(minutes=5)


def _procesar_notificacion_qr(db: Session, referencia: str | None) -> dict:
    """Notificacion = aviso. El pago se confirma preguntando a la pasarela.

    Este es el punto de seguridad del diseño. La plataforma no dice "pago" y el
    sistema le cree: localiza el cobro, consulta a Libelula si ese pago existe de
    verdad, y solo entonces lo aprueba. Una URL de callback falsificada no
    aprueba nada, porque la pasarela no conoce esa transaccion.
    """
    pago, error = _resolver_cobro_qr(db, referencia)
    if error is not None:
        status_http, detalle = error
        raise HTTPException(status_code=status_http, detail=detalle)

    if not qr_operativa():
        # Sin pasarela configurada no hay contra quien confirmar. Aprobar aqui
        # seria volver al agujero original, asi que no se aprueba nada.
        logger.error(
            "Llego una notificacion QR pero no hay pasarela configurada; "
            "no se aprueba el pago %s.", pago.id_pago,
        )
        return {
            "status": "sin_pasarela",
            "estado": estado_texto(pago.estado),
            "aplicado": False,
            "id_pago": pago.id_pago,
            "detalle": "No hay pasarela QR configurada para confirmar el pago",
        }

    desde, hasta = _ventana_de_conciliacion(pago)
    registro = confirmar_pago(pago.transaccion_id, desde, hasta)
    if registro is None:
        # "No hay evidencia todavia" no es "no se pago": la pasarela puede
        # tardar en liquidar. El cobro sigue pendiente y el barrido de
        # conciliacion lo revisitara.
        logger.info(
            "La pasarela aun no registra el pago de la transaccion %s; queda pendiente.",
            pago.transaccion_id,
        )
        return {
            "status": "sin_confirmar",
            "estado": estado_texto(pago.estado),
            "aplicado": False,
            "id_pago": pago.id_pago,
            "detalle": "La pasarela todavia no registra el pago; se reintentara en la conciliacion",
        }

    resultado = resolver_pago_confirmado(db, pago, registro)

    respuesta = {
        "estado": resultado["estado"],
        "aplicado": resultado["aplicado"],
        "id_pago": resultado["id_pago"],
        "codigo_recaudacion": registro.get("codigo_recaudacion"),
    }
    if resultado.get("reabierto"):
        respuesta["status"] = "pago_tardio_reabierto"
    elif resultado.get("caso") == "monto_discrepante":
        # El dinero llego pero no por la puerta del cobro: no es un pago tardio,
        # es un cobro que no corresponde a este pedido.
        respuesta["status"] = "monto_discrepante"
        respuesta["detalle"] = resultado.get("detalle")
    elif resultado.get("caso") == "sin_stock":
        respuesta["status"] = "pago_tardio_sin_stock"
        respuesta["detalle"] = resultado.get("detalle")
    else:
        respuesta["status"] = "procesado" if resultado["aplicado"] else "duplicado"
    return respuesta


@router.get(
    "/webhook/qr",
    summary="Notificacion GET de pago QR (formato del manual de Libelula)",
)
def webhook_pago_qr_get(
    request: Request,
    db: Session = Depends(get_db),
):
    """Notificacion de pago tal como la documenta Libelula: un GET.

    Libelula llama por GET a `callback_url` y anexa el identificador de la deuda
    al query string. El nombre del parametro se acepta en varias variantes
    porque la pasarela ha cambiado el nombre entre versiones del manual.
    """
    referencia = next(
        (
            request.query_params.get(campo)
            for campo in ("transaction_id", "transaccion_id", "id_transaccion", "identificador_deuda")
            if request.query_params.get(campo)
        ),
        None,
    )
    return _procesar_notificacion_qr(db, referencia)


@router.post(
    "/webhook/qr",
    summary="Webhook de confirmacion de pago QR (CU12)",
)
def webhook_pago_qr(
    payload: WebhookQrPayload,
    db: Session = Depends(get_db),
):
    """Recibe la notificacion de la pasarela QR y refleja el pago en el pedido.

    No exige token JWT: quien llama es la pasarela, no un usuario del sistema. Y
    no se aprueba solo por lo que diga el cuerpo: el estado real se consulta
    contra la pasarela antes de cerrar el pedido.
    """
    return _procesar_notificacion_qr(db, payload.referencia())


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

    estado_str = estado_texto(pago.estado)
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
