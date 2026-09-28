import re
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import stripe
from fastapi import APIRouter, Body, Depends, HTTPException, Request, status
from pydantic import BaseModel
from sqlalchemy.orm import Session, joinedload

from app.core.config import get_settings
from app.core.dependencies import cajero_required, get_current_user, pago_required
from app.db.session import get_db
from app.models import (
    CheckoutPendiente,
    Inventario,
    Pago,
    Pedido,
    PedidoItem,
    Producto,
    ProductoVariante,
    Sucursal,
    Usuario,
)
from app.models.enums import EstadoPago, EstadoPedido
from app.schemas.comercio import (
    CarritoItem,
    CobroTarjetaCreate,
    CobroTarjetaOut,
    CobroTarjetaVerificar,
    QrCobroCreate,
    QrCobroOut,
    QrPagoConfirmarIn,
    TipoPago,
    VentaDigitalCreate,
    VentaPresencialCreate,
)
from app.services.estado_pago_service import (
    PROVEEDORES_QR,
    StockInsuficienteError,
    cobro_vencido,
    rechazar_cobro_qr,
    reservar_stock,
    vencer_cobro_qr as _vencer_cobro_qr,
)
from app.services.estado_pago_service import (
    aprobar_cobro_qr as _aprobar_cobro_qr,
)
from app.services.estado_pago_service import (
    estado_texto as _estado_texto,
)
from app.services.notification_service import NotificationService
from app.services.qr_service import ErrorConfiguracionPasarela
from app.services.qr_service import crear_cobro_qr as crear_cobro_pasarela
from app.services.qr_service import proveedor_del_cobro
import logging

from app.services.stripe_service import (
    confirmar_pago_simulado,
    crear_intencion_pago,
    crear_sesion_checkout,
    pasarela_operativa,
)

router = APIRouter()

logger = logging.getLogger(__name__)


def _precio_variante(db: Session, variante_id: int) -> Decimal:
    variante = db.get(ProductoVariante, variante_id)
    if not variante:
        raise HTTPException(status_code=404, detail="Variante no encontrada")
    return variante.producto.precio + (variante.precio_extra or 0)


def _validar_stock(db: Session, sucursal_id: int, variante_id: int, cantidad: int):
    variante = db.get(ProductoVariante, variante_id)
    nombre_prod = variante.producto.nombre if variante and variante.producto else f"Variante #{variante_id}"
    stock = (
        db.query(Inventario)
        .filter(
            Inventario.variante_id == variante_id,
            Inventario.sucursal_id == sucursal_id,
        )
        .first()
    )
    if not stock or stock.cantidad_disponible < cantidad:
        disponible = stock.cantidad_disponible if stock else 0
        raise HTTPException(
            status_code=400,
            detail=f"Stock insuficiente para '{nombre_prod}' (disponible: {disponible}, solicitado: {cantidad})",
        )


def _validar_y_total(db: Session, sucursal_id: int, items) -> Decimal:
    """Valida disponibilidad y calcula el total de la venta.

    El stock se valida por variante SUMANDO las lineas repetidas. Validarlas
    una por una daria un "si hay stock" falso: con 3 disponibles, dos lineas de
    2 unidades pasarian el filtro por separado y solo fallaria mas tarde, cuando
    la reserva toma el lock, con un error de conflicto en vez de un mensaje claro
    de stock insuficiente.
    """
    total = Decimal("0")
    por_variante: dict[int, int] = {}
    for item in items:
        por_variante[item.variante_id] = por_variante.get(item.variante_id, 0) + item.cantidad
        total += _precio_variante(db, item.variante_id) * item.cantidad
    for variante_id, cantidad in por_variante.items():
        _validar_stock(db, sucursal_id, variante_id, cantidad)
    return total


@router.post(
    "/presencial", status_code=status.HTTP_201_CREATED,
    summary="Registrar venta presencial en caja (CU11, CU17, RF17, RF18)",
)
def venta_presencial(
    data: VentaPresencialCreate,
    db: Session = Depends(get_db),
    current: Usuario = Depends(cajero_required),
):
    # 1. Validar stock y calcular total
    total = Decimal("0")
    for item in data.items:
        _validar_stock(db, data.sucursal_id, item.variante_id, item.cantidad)
        precio = _precio_variante(db, item.variante_id)
        total += precio * item.cantidad

    # 2. Crear pedido pagado (presencial)
    pedido = Pedido(
        usuario_id=current.id_usuario,
        sucursal_id=data.sucursal_id,
        total=total,
        metodo_compra="presencial",
        estado="pagado",
        tipo_pago=data.tipo_pago,
    )
    db.add(pedido)
    db.flush()

    # 3. Crear ítems y descontar stock
    for item in data.items:
        precio = _precio_variante(db, item.variante_id)
        db.add(
            PedidoItem(
                pedido_id=pedido.id_pedido,
                variante_id=item.variante_id,
                cantidad=item.cantidad,
                precio_unitario=precio,
                subtotal=precio * item.cantidad,
            )
        )
        stock = (
            db.query(Inventario)
            .filter(
                Inventario.variante_id == item.variante_id,
                Inventario.sucursal_id == data.sucursal_id,
            )
            .first()
        )
        stock.cantidad_disponible -= item.cantidad

    # 4. Registrar pago
    if data.tipo_pago != "efectivo":
        db.add(
            Pago(
                pedido_id=pedido.id_pedido,
                monto=total,
                proveedor_pago="Punto de Venta",
                transaccion_id=f"CAJA-{pedido.id_pedido}",
                estado="aprobado",
            )
        )

    db.commit()
    db.refresh(pedido)

    items_res = []
    for item in data.items:
        variante = db.get(ProductoVariante, item.variante_id)
        precio = _precio_variante(db, item.variante_id)
        items_res.append({
            "variante_id": item.variante_id,
            "cantidad": item.cantidad,
            "precio_unitario": float(precio),
            "subtotal": float(precio * item.cantidad),
            "producto_nombre": variante.producto.nombre if variante and variante.producto else "Producto",
            "sku": variante.sku if variante else None,
            "talla": variante.talla.nombre if variante and variante.talla else None,
            "color": variante.color.nombre if variante and variante.color else None,
        })

    sucursal = db.get(Sucursal, data.sucursal_id) if data.sucursal_id else None

    return {
        "id_pedido": pedido.id_pedido,
        "total": float(total),
        "estado": "pagado",
        "tipo_pago": data.tipo_pago.value if hasattr(data.tipo_pago, 'value') else str(data.tipo_pago),
        "fecha_pedido": pedido.fecha_pedido.isoformat() if pedido.fecha_pedido else None,
        "sucursal_nombre": sucursal.nombre if sucursal else "Sucursal",
        "cajero_nombre": current.nombre,
        "items": items_res,
    }


def _cobro_tarjeta_del_cajero(db: Session, id_pago: int, current: Usuario) -> Pago:
    """Devuelve el cobro con tarjeta, solo si es del cajero que pregunta.

    Sin el filtro por `usuario_id`, un cajero podria cerrar con su propia sesion
    un cobro que otro dejo abierto, y asistallar mercaderia ajena. Se comprueba
    tambien que el pedido sea de tarjeta, para que este endpoint no sirva para
    cerrar un cobro QR por el camino corto.
    """
    pago = db.get(Pago, id_pago)
    if pago is None or pago.proveedor_pago not in ("STRIPE", "SIMULADO"):
        raise HTTPException(status_code=404, detail="Cobro no encontrado")

    pedido = db.get(Pedido, pago.pedido_id)
    if pedido is None or pedido.usuario_id != current.id_usuario or pedido.tipo_pago not in (
        TipoPago.tarjeta_debito.value,
        TipoPago.tarjeta_credito.value,
    ):
        raise HTTPException(status_code=404, detail="Cobro no encontrado")
    return pago


def _crear_cobro_pendiente(
    db: Session,
    current: Usuario,
    sucursal_id: int,
    items,
    total: Decimal,
    *,
    tipo_pago: str,
    proveedor_pago: str,
    transaccion_id: str,
    datos_gateway: dict,
) -> tuple[Pago, Pedido]:
    """Deja una venta armada como cobro pendiente y con el inventario reservado.

    Es el esqueleto que comparten el cobro por QR y el cobro con tarjeta: los dos
    dejan el pedido en 'pendiente' y el stock retenido hasta que una pasarela
    confirme que el dinero llego. Lo que cambia entre uno y otro es unicamente
    como se le pide al cliente que pague, no como se registra ni como se aprueba.

    Que el stock se reserve aca, y no al cobrar, es lo que impide que otra venta
    se lleve las mismas prendas mientras el cliente esta pagando.

    Devuelve el `(pago, pedido)` ya confirmado en la base.
    """
    pedido = Pedido(
        usuario_id=current.id_usuario,
        sucursal_id=sucursal_id,
        total=total,
        metodo_compra="presencial",
        estado="pendiente",
        tipo_pago=tipo_pago,
    )
    db.add(pedido)
    db.flush()

    for item in items:
        precio = _precio_variante(db, item.variante_id)
        db.add(
            PedidoItem(
                pedido_id=pedido.id_pedido,
                variante_id=item.variante_id,
                cantidad=item.cantidad,
                precio_unitario=precio,
                subtotal=precio * item.cantidad,
            )
        )

    pago = Pago(
        pedido_id=pedido.id_pedido,
        monto=total,
        proveedor_pago=proveedor_pago,
        transaccion_id=transaccion_id,
        estado="pendiente",
        datos_gateway=datos_gateway,
    )
    db.add(pago)

    # El inventario se compromete aqui, junto con el cobro, para que ninguna
    # otra venta pueda tomar estas unidades mientras el cliente paga. Si el
    # cobro nunca se paga, el barrido de vencidos lo devuelve.
    #
    # La validacion previa (`_validar_y_total`) da el mensaje legible al cajero,
    # pero entre esa comprobacion y este lock otra venta pudo llevarse las
    # mismas unidades. Aqui se revalida bajo el lock: si ya no cabe, no se
    # descuenta nada y se responde 409 en vez de sobrevender.
    try:
        reservar_stock(db, pedido)
    except StockInsuficienteError as exc:
        db.rollback()
        logger.warning("Se perdio la reserva del cobro %s: %s", transaccion_id, exc)
        raise HTTPException(
            status_code=409,
            detail="Otra venta se llevo el inventario antes de reservar este cobro; "
                   "reintenta la operacion",
        ) from exc
    db.commit()
    db.refresh(pago)
    return pago, pedido


@router.post(
    "/qr/cobrar", response_model=QrCobroOut, status_code=status.HTTP_201_CREATED,
    summary="Crear cobro QR contra la pasarela y dejar el pago pendiente (CU12)",
)
def crear_cobro_qr(
    data: QrCobroCreate,
    db: Session = Depends(get_db),
    current: Usuario = Depends(pago_required),
):
    """Registra un cobro QR y devuelve el codigo para mostrar al cliente.

    A diferencia de /presencial, aqui el pago NO se aprueba de inmediato: se
    crea en estado 'pendiente' y queda a la espera de que la pasarela
    notifique el pago por webhook. El pedido tampoco se marca como pagado, de
    modo que nada se descuenta del inventario hasta la confirmacion real.

    En esta fase el stock solo se valida, no se retiene: la reserva del
    inventario y la expiracion del cobro se incorporan al conectar este
    endpoint al punto de venta.
    """
    if not data.items:
        raise HTTPException(status_code=400, detail="El cobro debe incluir al menos un producto")

    sucursal_id = data.sucursal_id or 1
    total = _validar_y_total(db, sucursal_id, data.items)

    unidades = sum(item.cantidad for item in data.items)
    descripcion = f"Compra en tienda {sucursal_id} - {unidades} unidad(es)"
    try:
        cobro = crear_cobro_pasarela(
            monto=float(total),
            descripcion=descripcion,
            email_cliente=current.email,
            referencia=f"cobro-qr-{current.id_usuario}",
        )
    except ErrorConfiguracionPasarela as exc:
        # 503 y no 500: la pasarela no esta lista. Se dice cual es el problema
        # para que el operador lo arregle, en vez de degradar en silencio y
        # mostrar un QR que jamas se va a confirmar.
        logger.error("No se pudo crear el cobro QR: %s", exc)
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    pago, pedido = _crear_cobro_pendiente(
        db,
        current,
        sucursal_id,
        data.items,
        total,
        tipo_pago="qr",
        proveedor_pago=proveedor_del_cobro(cobro),
        transaccion_id=cobro["transaccion_id"],
        datos_gateway={
            "qr_url": cobro["qr_url"],
            "url_pago": cobro["url_pago"],
            "simulado": cobro["simulado"],
            "expires_at": cobro["expires_at"].isoformat(),
            # Referencia propia de la deuda. La pasarela la devuelve como
            # `identificador` al conciliar, asi que permite rastrear el cobro
            # sin depender de su `id_transaccion`.
            "identificador_deuda": cobro.get("identificador_deuda"),
            "creado": datetime.now(timezone.utc).isoformat(),
        },
    )

    return QrCobroOut(
        id_pago=pago.id_pago,
        id_pedido=pedido.id_pedido,
        transaccion_id=pago.transaccion_id,
        proveedor_pago=pago.proveedor_pago,
        qr_url=cobro["qr_url"],
        url_pago=cobro["url_pago"],
        estado=_estado_texto(pago.estado),
        simulado=cobro["simulado"],
        expires_at=cobro["expires_at"],
        total=float(total),
        stock_reservado=True,
    )


def _cobro_qr_del_usuario(db: Session, id_pago: int, current: Usuario) -> Pago:
    pago = db.get(Pago, id_pago)
    if pago is None:
        raise HTTPException(status_code=404, detail="Cobro no encontrado")
    if pago.proveedor_pago not in PROVEEDORES_QR:
        raise HTTPException(status_code=400, detail="El pago indicado no es un cobro QR")
    return pago


@router.get(
    "/qr/{id_pago}/estado",
    summary="Consultar el estado de un cobro QR y vencerlo si expiró (CU12)",
)
def estado_cobro_qr(
    id_pago: int,
    db: Session = Depends(get_db),
    current: Usuario = Depends(pago_required),
):
    """Estado del cobro QR que el punto de venta consulta por sondeo.

    La expiracion se resuelve tambien de forma perezosa al consultar: ademas del
    barrido periodico, cualquier lectura del cobro resuelve el vencimiento, de modo
    que no quedan pedidos colgados esperando un proceso que podria no estar
    corriendo.
    """
    pago = _cobro_qr_del_usuario(db, id_pago, current)

    vencido = cobro_vencido(pago)
    if vencido:
        _vencer_cobro_qr(db, pago)

    estado = _estado_texto(pago.estado)
    pedido = db.get(Pedido, pago.pedido_id)
    return {
        "id_pago": pago.id_pago,
        "id_pedido": pago.pedido_id,
        "estado": estado,
        # Solo un vencimiento detectado aqui vale 'vencido'. Un 'rechazado'
        # que ya venía de la pasarela llega con motivo nulo.
        "motivo": "vencido" if vencido else None,
        "transaccion_id": pago.transaccion_id,
        "estado_pedido": _estado_texto(pedido.estado) if pedido is not None else None,
        "total": float(pago.monto),
        "simulado": bool((pago.datos_gateway or {}).get("simulado", False)),
    }


@router.post(
    "/qr/{id_pago}/simular-pago",
    summary="Simular la confirmación de un cobro QR (solo modo simulado)",
)
def simular_pago_qr(
    id_pago: int,
    db: Session = Depends(get_db),
    current: Usuario = Depends(pago_required),
):
    """Confirma el cobro como si la pasarela hubiera notificado el pago.

    Existe para poder demostrar el flujo completo sin credenciales reales: pasa
    por la misma transicion de estado que usara el webhook de la pasarela. Solo
    acepta cobros que la propia pasarela marco como simulados, de modo que un
    cobro real nunca se puede confirmar desde la interfaz.
    """
    if not get_settings().DEBUG:
        raise HTTPException(status_code=403, detail="Solo disponible en modo desarrollo")

    pago = _cobro_qr_del_usuario(db, id_pago, current)
    if not (pago.datos_gateway or {}).get("simulado", False):
        raise HTTPException(
            status_code=400,
            detail="Este cobro fue emitido por una pasarela real; "
            "solo la pasarela puede confirmarlo",
        )

    resultado = _aprobar_cobro_qr(db, pago)
    pedido = db.get(Pedido, pago.pedido_id)
    return {
        "id_pago": pago.id_pago,
        "id_pedido": pago.pedido_id,
        "estado": resultado["estado"],
        "aplicado": resultado["aplicado"],
        "estado_pedido": _estado_texto(pedido.estado) if pedido is not None else None,
        "total": float(pago.monto),
    }


# ============================================================
# Pago del cobro QR desde el celular del cliente
# ============================================================
# El punto de venta emite el QR y el cliente lo paga desde su telefono. El estado
# del cobro es el mismo que ya sondea la web, asi que el cajero ve el resultado
# sin cambios: no hay dos caminos de pago, hay uno solo.
#
# Lo que NO se hace aqui, por diseno: aprobar por lo que diga el cliente. El
# monto sale del cobro, la referencia se busca en la base, y la confirmacion se
# le pregunta a la pasarela. Un cobro simulado no se aprueba solo porque el
# telefono lo diga (ver `_resolver_cobro_qr` en pagos.py): aqui el dinero si
# deja huella, porque la pasarela es Stripe, y por eso puede confirmar.


def _cobro_qr_por_referencia(db: Session, referencia: str) -> Pago:
    """Localiza un cobro QR por el codigo impreso en el QR.

    El codigo se muestra en mayusculas junto al QR, pero el cliente lo teclea: se
    normaliza para que no falle por escribirlo en minusculas.
    """
    clave = (referencia or "").strip().upper()
    if not clave:
        raise HTTPException(status_code=400, detail="Falta el codigo del cobro")

    pago = (
        db.query(Pago)
        .filter(Pago.transaccion_id == clave)
        .order_by(Pago.id_pago.desc())
        .first()
    )
    if pago is None or pago.proveedor_pago not in PROVEEDORES_QR:
        raise HTTPException(
            status_code=404,
            detail="El codigo no corresponde a ningun cobro QR",
        )
    return pago


@router.post(
    "/qr/{referencia}/pagar",
    summary="Iniciar el pago de un cobro QR desde el celular del cliente",
)
def pagar_cobro_qr_cliente(
    referencia: str,
    request: Request,
    db: Session = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    """Devuelve la pagina de pago de la pasarela para un cobro QR existente.

    El monto que se cobra es el del cobro, nunca uno que mande el cliente. La
    sesion queda atada a este cobro guardando su id, para que despues no se
    pueda confirmar un cobro con el session_id de otro.
    """
    pago = _cobro_qr_por_referencia(db, referencia)

    if cobro_vencido(pago):
        _vencer_cobro_qr(db, pago)
        raise HTTPException(status_code=409, detail="El cobro ya vencio")

    if _estado_texto(pago.estado) != "pendiente":
        raise HTTPException(
            status_code=409,
            detail=f"El cobro ya no esta pendiente (estado: {_estado_texto(pago.estado)})",
        )

    if not pasarela_operativa():
        # Sin pasarela no hay pagina de pago que abrir. Se devuelve la sesion
        # marcada como simulada y el cliente va directo a la confirmacion, que es
        # exactamente lo que ya hace el carrito digital en este mismo caso.
        if not get_settings().DEBUG:
            raise HTTPException(
                status_code=503,
                detail="La pasarela no esta configurada",
            )
        datos = dict(pago.datos_gateway or {})
        datos["checkout_session_id"] = f"sim_{pago.id_pago}_{current.id_usuario}"
        datos["checkout_usuario_id"] = current.id_usuario
        pago.datos_gateway = datos
        db.commit()
        return {
            "session_id": datos["checkout_session_id"],
            "checkout_url": None,
            "simulado": True,
            "total": float(pago.monto),
            "id_pago": pago.id_pago,
            "estado": "pendiente",
        }

    retorno = str(request.url_for("retorno_pago_qr"))
    try:
        sesion = crear_sesion_checkout(
            float(pago.monto),
            f"Cobro QR {pago.transaccion_id}",
            current.email or "",
            retorno,
            retorno,
        )
    except stripe.error.StripeError as e:
        # Clave presente pero no utilizable. Se dice claro para no dejar al
        # cliente esperando una pagina que nunca va a abrir.
        logger.error("No se pudo crear la sesion de pago QR: %s", e)
        raise HTTPException(
            status_code=502,
            detail="No se pudo iniciar el pago en la pasarela",
        ) from e

    if sesion["simulado"] or not sesion.get("checkout_url"):
        raise HTTPException(
            status_code=503,
            detail="La pasarela no respondio con una pagina de pago",
        )

    datos = dict(pago.datos_gateway or {})
    datos["checkout_session_id"] = sesion["session_id"]
    datos["checkout_usuario_id"] = current.id_usuario
    pago.datos_gateway = datos
    db.commit()

    return {
        "session_id": sesion["session_id"],
        "checkout_url": sesion["checkout_url"],
        "simulado": False,
        "total": float(pago.monto),
        "id_pago": pago.id_pago,
        "estado": "pendiente",
    }


# ============================================================
# Cobro con tarjeta en el punto de venta
# ============================================================
# A diferencia de /presencial, aca el pago NO se aprueba de inmediato. Se crea en
# estado 'pendiente' con el inventario reservado, y queda a la espera de que
# `verificar` le pregunte a la pasarela. Es el mismo criterio del cobro por QR,
# y por el mismo motivo: una venta en caja que marca "pagado" sin que nadie haya
# confirmado el dinero es una venta que inventa ingresos.
#
# Débito y crédito son el mismo código. No hay dos implementaciones: lo único
# que cambia es la etiqueta que queda en el comprobante y el nombre que recibe el
# cobro. El fondo de la tarjeta lo determina la pasarela, no el botón que apretó
# el cajero.


@router.post(
    "/presencial/tarjeta", response_model=CobroTarjetaOut,
    status_code=status.HTTP_201_CREATED,
    summary="Abrir un cobro con tarjeta y dejarlo pendiente hasta la confirmacion",
)
def crear_cobro_tarjeta(
    data: CobroTarjetaCreate,
    request: Request,
    db: Session = Depends(get_db),
    current: Usuario = Depends(pago_required),
):
    """Arma el cobro y devuelve donde tiene que pagar el cliente.

    El monto es el del ticket. No hay forma de que el cajero indique otro, y el
    cliente tampoco elige el importe: el dinero se compara contra el cobro, no
    contra lo que el navegador mando.
    """
    if data.tipo_pago not in (TipoPago.tarjeta_debito, TipoPago.tarjeta_credito):
        raise HTTPException(
            status_code=400,
            detail="Este endpoint solo admite tarjeta de debito o de credito",
        )
    if not data.items:
        raise HTTPException(status_code=400, detail="El cobro debe incluir al menos un producto")

    sucursal_id = data.sucursal_id or 1
    total = _validar_y_total(db, sucursal_id, data.items)
    unidades = sum(item.cantidad for item in data.items)
    descripcion = f"Compra en tienda {sucursal_id} - {unidades} unidad(es)"

    if pasarela_operativa():
        retorno = str(request.url_for("retorno_pago_qr"))
        try:
            sesion = crear_sesion_checkout(
                float(total), descripcion, current.email or "", retorno, retorno
            )
        except stripe.error.StripeError as e:
            logger.error("No se pudo crear la sesion de pago con tarjeta: %s", e)
            raise HTTPException(
                status_code=502,
                detail="No se pudo iniciar el pago en la pasarela",
            ) from e

        if sesion["simulado"] or not sesion.get("checkout_url"):
            raise HTTPException(
                status_code=503, detail="La pasarela no respondio con una pagina de pago"
            )
        checkout_url = sesion["checkout_url"]
        session_id = sesion["session_id"]
        simulado = False
    else:
        # Sin pasarela no hay pagina que abrir. El cobro queda igual de pendiente
        # y esperando: lo que cambia es que se confirma con la pasarela simulada.
        checkout_url = None
        session_id = None
        simulado = True

    pago, _pedido = _crear_cobro_pendiente(
        db,
        current,
        sucursal_id,
        data.items,
        total,
        tipo_pago=data.tipo_pago.value,
        proveedor_pago="SIMULADO" if simulado else "STRIPE",
        transaccion_id=f"TXN-TARJ-{uuid.uuid4().hex[:20].upper()}",
        datos_gateway={
            "simulado": simulado,
            "checkout_session_id": session_id,
            "checkout_url": checkout_url,
            "creado": datetime.now(timezone.utc).isoformat(),
        },
    )

    return CobroTarjetaOut(
        id_pago=pago.id_pago,
        id_pedido=_pedido.id_pedido,
        transaccion_id=pago.transaccion_id,
        estado=_estado_texto(pago.estado),
        total=float(pago.monto),
        simulado=simulado,
        checkout_url=checkout_url,
    )


@router.post(
    "/presencial/tarjeta/{id_pago}/verificar",
    summary="Preguntar a la pasarela si el pago con tarjeta entro (CU11)",
)
def verificar_cobro_tarjeta(
    id_pago: int,
    data: CobroTarjetaVerificar | None = None,
    db: Session = Depends(get_db),
    current: Usuario = Depends(pago_required),
):
    """Consulta el estado real del cobro y lo cierra si el dinero llego.

    Es el equivalente en ventanilla del webhook de Libélula: en vez de que la
    pasarela avise, el punto de venta pregunta. Se puede llamar las veces que
    haga falta porque cerrar un cobro ya cerrado no vuelve a descontar stock.

    El cliente jamas dice "aprobado". Dice que tarjeta uso, y la pasarela (o su
    equivalente simulado) decide.
    """
    pago = _cobro_tarjeta_del_cajero(db, id_pago, current)
    tarjeta = (data.numero_tarjeta if data else None)

    if _estado_texto(pago.estado) in ("aprobado", "rechazado"):
        return _respuesta_cobro(db, pago, {"estado": _estado_texto(pago.estado),
                                           "aplicado": False, "motivo": None})

    if cobro_vencido(pago):
        _vencer_cobro_qr(db, pago)
        return _respuesta_cobro(db, pago, {"estado": "rechazado", "aplicado": False,
                                           "motivo": "El cobro vencio"})

    session_id = (pago.datos_gateway or {}).get("checkout_session_id")
    if not pasarela_operativa():
        if not get_settings().DEBUG:
            raise HTTPException(status_code=503, detail="La pasarela no esta configurada")
        if not confirmar_pago_simulado(tarjeta):
            return _respuesta_cobro(
                db, pago, rechazar_cobro_qr(db, pago, "Tarjeta rechazada por la pasarela")
            )
        return _respuesta_cobro(db, pago, _aprobar_cobro_qr(db, pago))

    if not session_id:
        raise HTTPException(
            status_code=400, detail="Este cobro no tiene sesion de pago para verificar"
        )
    try:
        sesion = stripe.checkout.Session.retrieve(session_id)
    except stripe.error.StripeError as e:
        raise HTTPException(
            status_code=402, detail="No se pudo verificar el pago con la pasarela"
        ) from e

    estado_pago = (
        sesion.get("payment_status") if isinstance(sesion, dict) else sesion.payment_status
    )
    if estado_pago != "paid":
        return _respuesta_cobro(
            db, pago, rechazar_cobro_qr(db, pago, "La pasarela no confirmo el pago")
        )
    return _respuesta_cobro(db, pago, _aprobar_cobro_qr(db, pago))


@router.get(
    "/qr/retorno",
    summary="Pagina de retorno del pago QR (a donde manda la pasarela)",
)
def retorno_pago_qr():
    """Pagina minima a la que vuelve el cliente tras pagar.

    La confirmacion real la hace `confirmar_cobro_qr`, que pregunta a la pasarela.
    Esta pagina solo evita el callejon sin salida de un 404 e indica que vuelva a
    la aplicacion para ver el resultado.
    """
    from fastapi.responses import HTMLResponse

    return HTMLResponse(
        content=(
            "<!doctype html><html lang='es'><head><meta charset='utf-8'>"
            "<meta name='viewport' content='width=device-width,initial-scale=1'>"
            "<title>Pago recibido</title></head>"
            "<body style=\"font-family:system-ui;display:flex;align-items:center;"
            "justify-content:center;height:100vh;margin:0;background:#f5f5f5\">"
            "<div style='text-align:center;padding:24px;background:#fff;"
            "border-radius:12px;box-shadow:0 2px 12px rgba(0,0,0,.08)'>"
            "<h2 style='margin:0 0 8px'>Pago recibido</h2>"
            "<p style='margin:0 0 16px;color:#555'>Vuelve a la aplicacion "
            "FashionStore para ver el resultado.</p>"
            "</div></body></html>"
        )
    )


def _respuesta_cobro(db: Session, pago: Pago, resultado: dict) -> dict:
    """Arma la respuesta que ve el celular, con el estado del pedido al lado.

    El motivo solo se devuelve si el cobro quedo rechazado: en el resto de casos
    seria ruido.
    """
    pedido = db.get(Pedido, pago.pedido_id)
    return {
        "id_pago": pago.id_pago,
        "id_pedido": pago.pedido_id,
        "estado": resultado["estado"],
        "aplicado": resultado.get("aplicado", False),
        "motivo": resultado.get("motivo"),
        "estado_pedido": _estado_texto(pedido.estado) if pedido is not None else None,
        "total": float(pago.monto),
    }


def _confirmar_cobro_simulado(
    db: Session, pago: Pago, data: QrPagoConfirmarIn
) -> dict:
    """Confirma un cobro sin pasarela, para poder demostrar el flujo completo.

    NO es "el cliente dice que pago": la decision se toma aqui, en el servidor,
    a partir de la tarjeta. El cliente solo aporta un dato y no puede exigir un
    resultado. Es el mismo criterio con el que razona la pasarela simulada del
    carrito digital, y solo existe en desarrollo.

    El rechazo usa la misma transicion que un fallo definitivo de pasarela: el
    cobro queda rechazado y el inventario reservado se libera. Asi el punto de
    venta ve 'rechazado' y no un cobro colgado en 'pendiente' para siempre.
    """
    if not get_settings().DEBUG:
        raise HTTPException(
            status_code=503,
            detail="La pasarela no esta configurada",
        )

    tarjeta = re.sub(r"\D", "", data.numero_tarjeta or "")
    if tarjeta.endswith("0002"):
        return _respuesta_cobro(
            db, pago, rechazar_cobro_qr(db, pago, "Tarjeta rechazada por la pasarela")
        )
    return _respuesta_cobro(db, pago, _aprobar_cobro_qr(db, pago))


@router.post(
    "/qr/{referencia}/confirmar",
    summary="Confirmar el pago QR hechos desde el celular (preguntando a la pasarela)",
)
def confirmar_cobro_qr(
    referencia: str,
    data: QrPagoConfirmarIn,
    db: Session = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    """Confirma el cobro solo si la pasarela dice que el dinero llego.

    Un rechazo se responde 200 con `estado: rechazado`, no un error: es un
    resultado valido y el cliente necesita distinguirlo de una falla tecnica
    para poder mostrarlo.

    Idempotente: si el cobro ya quedo aprobado se devuelve tal cual, sin cobrar
    ni descontar stock dos veces.
    """
    pago = _cobro_qr_por_referencia(db, referencia)
    estado_actual = _estado_texto(pago.estado)

    if estado_actual == "aprobado":
        return _respuesta_cobro(
            db,
            pago,
            {"estado": "aprobado", "aplicado": False, "motivo": None},
        )

    if estado_actual != "pendiente":
        raise HTTPException(
            status_code=409,
            detail=f"El cobro ya no se puede confirmar (estado: {estado_actual})",
        )

    # La sesion tiene que ser la que se creo para ESTE cobro. Sin esto, cualquiera
    # podria mandar el session_id de otro pago y marcaria este cobro como pagado.
    esperado = (pago.datos_gateway or {}).get("checkout_session_id")
    if not esperado or esperado != data.session_id:
        raise HTTPException(
            status_code=400,
            detail="La sesion de pago no corresponde a este cobro",
        )

    if not pasarela_operativa():
        return _confirmar_cobro_simulado(db, pago, data)

    try:
        sesion = stripe.checkout.Session.retrieve(data.session_id)
    except stripe.error.StripeError as e:
        raise HTTPException(
            status_code=402,
            detail="No se pudo verificar el pago con la pasarela",
        ) from e

    estado_pago = (
        sesion.get("payment_status") if isinstance(sesion, dict) else sesion.payment_status
    )
    if estado_pago != "paid":
        return _respuesta_cobro(
            db, pago, rechazar_cobro_qr(db, pago, "La pasarela no confirmo el pago")
        )

    return _respuesta_cobro(db, pago, _aprobar_cobro_qr(db, pago))


@router.post(
    "/digital/payment-intent", status_code=status.HTTP_201_CREATED,
    summary="Crear intención de pago para compra digital (CU10, RF19)",
)
def crear_pago_digital(
    data: VentaDigitalCreate,
    db: Session = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    sucursal_id = data.sucursal_id or 1
    total = _validar_y_total(db, sucursal_id, data.items)

    intent = crear_intencion_pago(float(total), f"Pedido de {current.nombre}")
    return {"monto": float(total), **intent}


@router.post(
    "/digital/checkout", status_code=status.HTTP_201_CREATED,
    summary="Crear Checkout Session alojada en Stripe (redirección a la página de la pasarela)",
)
def crear_checkout_digital(
    data: VentaDigitalCreate,
    request: Request,
    db: Session = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    """Crea una Checkout Session de Stripe y devuelve checkout_url.

    En el retorno, Stripe redirige a success_url (con ?session_id=...), donde el
    cliente confirma la compra enviando ese session_id a /digital/confirmar.
    El carrito se persiste en checkout_pendiente para poder confirmar aunque el
    cliente vuelva desde otra app/pestaña (la SPA se recarga / la app se reabre).
    """
    sucursal_id = data.sucursal_id or 1
    total = _validar_y_total(db, sucursal_id, data.items)

    base = (data.return_url or f"{request.base_url.scheme}://{request.base_url.netloc}").rstrip("/")
    success_url = f"{base}/pago/confirmacion?session_id={{CHECKOUT_SESSION_ID}}"
    cancel_url = f"{base}/carrito"

    sesion = crear_sesion_checkout(
        float(total),
        f"Pedido de {current.nombre}",
        current.email,
        success_url,
        cancel_url,
    )
    if not sesion["simulado"]:
        db.add(
            CheckoutPendiente(
                session_id=sesion["session_id"],
                usuario_id=current.id_usuario,
                sucursal_id=sucursal_id,
                items=[
                    {"variante_id": i.variante_id, "cantidad": i.cantidad}
                    for i in data.items
                ],
                monto=total,
            )
        )
        db.commit()
    return {"monto": float(total), **sesion}


@router.post(
    "/digital/confirmar", status_code=status.HTTP_201_CREATED,
    summary="Confirmar y registrar compra digital tras pago aprobado",
)
def confirmar_compra_digital(
    data: VentaDigitalCreate,
    db: Session = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    pendiente_activa = None
    transaccion_id = None
    if data.session_id and not data.payment_intent_id:
        if not pasarela_operativa():
            raise HTTPException(
                status_code=402,
                detail="La pasarela no está operativa; completa el pago por el flujo simulado",
            )
        try:
            sesion = stripe.checkout.Session.retrieve(data.session_id)
        except stripe.error.StripeError as e:
            raise HTTPException(
                status_code=402,
                detail="No se pudo verificar el pago con la pasarela",
            ) from e
        estado = sesion.get("payment_status") if isinstance(sesion, dict) else sesion.payment_status
        if estado != "paid":
            raise HTTPException(status_code=402, detail="Pago no aprobado por la pasarela")
        pendiente = db.get(CheckoutPendiente, data.session_id)
        if not pendiente:
            raise HTTPException(
                status_code=404,
                detail="Sesión de pago no encontrada o ya procesada",
            )
        data = data.model_copy(update={
            "items": [
                CarritoItem.model_validate({k: it[k] for k in ("variante_id", "cantidad")})
                for it in pendiente.items
            ],
            "sucursal_id": data.sucursal_id or pendiente.sucursal_id,
        })
        transaccion_id = data.session_id
        pendiente_activa = pendiente
    elif data.payment_intent_id:
        if not pasarela_operativa():
            # Modo simulado: acepta el intent simulado devuelto por el backend.
            transaccion_id = data.payment_intent_id
        else:
            try:
                intent = stripe.PaymentIntent.retrieve(data.payment_intent_id)
            except stripe.error.StripeError as e:
                raise HTTPException(
                    status_code=402,
                    detail="No se pudo verificar el pago con la pasarela",
                ) from e
            estado = intent.get("status") if isinstance(intent, dict) else intent.status
            if estado != "succeeded":
                raise HTTPException(status_code=402, detail="Pago no aprobado por la pasarela")
            transaccion_id = data.payment_intent_id
    elif not confirmar_pago_simulado():
        raise HTTPException(status_code=402, detail="Pago rechazado por la pasarela")

    tipo_pago_raw = (getattr(data, "tipo_pago", None) or "tarjeta_credito").lower()
    if "qr" in tipo_pago_raw:
        tipo_pago_enum = TipoPago.qr
        prov_pago = "QR_SIMPLE"
        estado_pedido = EstadoPedido.pagado
        estado_pago = EstadoPago.aprobado
        txn_id = transaccion_id or f"TXN-QR-{int(datetime.now().timestamp())}"
    elif "efectivo" in tipo_pago_raw:
        tipo_pago_enum = TipoPago.efectivo
        prov_pago = "EFECTIVO"
        estado_pedido = EstadoPedido.pendiente
        estado_pago = EstadoPago.pendiente
        txn_id = f"TXN-EFECTIVO-{int(datetime.now().timestamp())}"
    elif "debito" in tipo_pago_raw:
        tipo_pago_enum = TipoPago.tarjeta_debito
        prov_pago = "STRIPE"
        estado_pedido = EstadoPedido.pagado
        estado_pago = EstadoPago.aprobado
        txn_id = transaccion_id or f"TXN-STRIPE-{int(datetime.now().timestamp())}"
    else:
        tipo_pago_enum = TipoPago.tarjeta_credito
        prov_pago = "STRIPE"
        estado_pedido = EstadoPedido.pagado
        estado_pago = EstadoPago.aprobado
        txn_id = transaccion_id or f"TXN-STRIPE-{int(datetime.now().timestamp())}"

    sucursal_id = data.sucursal_id or 1
    total = _validar_y_total(db, sucursal_id, data.items)

    pedido = Pedido(
        usuario_id=current.id_usuario,
        sucursal_id=sucursal_id,
        total=total,
        metodo_compra="digital",
        estado=estado_pedido,
        tipo_pago=tipo_pago_enum,
    )
    db.add(pedido)
    db.flush()

    for item in data.items:
        precio = _precio_variante(db, item.variante_id)
        db.add(
            PedidoItem(
                pedido_id=pedido.id_pedido,
                variante_id=item.variante_id,
                cantidad=item.cantidad,
                precio_unitario=precio,
                subtotal=precio * item.cantidad,
            )
        )
        stock = (
            db.query(Inventario)
            .filter(
                Inventario.variante_id == item.variante_id,
                Inventario.sucursal_id == sucursal_id,
            )
            .first()
        )
        if stock:
            stock.cantidad_disponible -= item.cantidad

    db.add(
        Pago(
            pedido_id=pedido.id_pedido,
            monto=total,
            proveedor_pago=prov_pago,
            transaccion_id=txn_id,
            estado=estado_pago,
        )
    )

    if pendiente_activa:
        db.delete(pendiente_activa)

    db.commit()
    db.refresh(pedido)

    # Simular notificación de comprobante enviado
    NotificationService.enviar_notificacion_compra_digital(current.email, pedido.id_pedido, float(total))

    return {
        "id_pedido": pedido.id_pedido,
        "total": float(total),
        "estado": estado_pedido.value if hasattr(estado_pedido, "value") else str(estado_pedido),
        "tipo_pago": tipo_pago_enum.value if hasattr(tipo_pago_enum, "value") else str(tipo_pago_enum),
    }


@router.post(
    "/digital/qr-generar",
    summary="Generar código QR dinámico para pago digital",
)
def generar_qr_digital(
    data: VentaDigitalCreate,
    db: Session = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    sucursal_id = data.sucursal_id or 1
    total = _validar_y_total(db, sucursal_id, data.items)
    from app.services.qr_service import _qr_a_data_uri
    ref = f"CLI-{current.id_usuario}-{int(datetime.now().timestamp())}"
    contenido = (
        f"FASHIONSTORE BOLIVIA - PAGO DIGITAL QR\n"
        f"Cliente: {current.nombre}\n"
        f"Monto: BOB {float(total):.2f}\n"
        f"Referencia: {ref}\n"
        f"Concepto: Compra digital FashionStore"
    )
    qr_data_uri = _qr_a_data_uri(contenido)
    return {
        "monto": float(total),
        "qr_url": qr_data_uri,
        "referencia": ref,
        "moneda": "BOB",
    }


class PagarReservaData(BaseModel):
    tipo_pago: str = "tarjeta_credito"


@router.post(
    "/digital/pagar-reserva/{reserva_id}", status_code=status.HTTP_201_CREATED,
    summary="Pagar y convertir reserva a compra digital (CU10)",
)
def pagar_reserva_digital(
    reserva_id: int,
    data: PagarReservaData = Body(default_factory=PagarReservaData),
    db: Session = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    from app.models import Reserva
    reserva = db.get(Reserva, reserva_id)
    if not reserva:
        raise HTTPException(status_code=404, detail="Reserva no encontrada")
    if reserva.usuario_id != current.id_usuario and current.rol != "admin":
        raise HTTPException(status_code=403, detail="No tienes permiso sobre esta reserva")
    estado_reserva = (
        reserva.estado.value if hasattr(reserva.estado, "value") else str(reserva.estado)
    )
    if estado_reserva not in ("pendiente", "preparada"):
        raise HTTPException(status_code=400, detail="Solo se pueden pagar reservas pendientes o preparadas")

    if not confirmar_pago_simulado():
        raise HTTPException(status_code=402, detail="Pago rechazado por la pasarela")

    total = Decimal("0")
    for item in reserva.items:
        precio = _precio_variante(db, item.variante_id)
        total += precio * item.cantidad

    tipo_pago_raw = (data.tipo_pago or "tarjeta_credito").lower()
    if "qr" in tipo_pago_raw:
        tipo_pago_enum = TipoPago.qr
        prov_pago = "QR_SIMPLE"
        estado_pedido = EstadoPedido.pagado
        estado_pago = EstadoPago.aprobado
        txn_id = f"TXN-QR-RES-{reserva.id_reserva}"
    elif "efectivo" in tipo_pago_raw:
        tipo_pago_enum = TipoPago.efectivo
        prov_pago = "EFECTIVO"
        estado_pedido = EstadoPedido.pendiente
        estado_pago = EstadoPago.pendiente
        txn_id = f"TXN-EFECTIVO-RES-{reserva.id_reserva}"
    elif "debito" in tipo_pago_raw:
        tipo_pago_enum = TipoPago.tarjeta_debito
        prov_pago = "STRIPE"
        estado_pedido = EstadoPedido.pagado
        estado_pago = EstadoPago.aprobado
        txn_id = f"TXN-STRIPE-RES-{reserva.id_reserva}"
    else:
        tipo_pago_enum = TipoPago.tarjeta_credito
        prov_pago = "STRIPE"
        estado_pedido = EstadoPedido.pagado
        estado_pago = EstadoPago.aprobado
        txn_id = f"TXN-STRIPE-RES-{reserva.id_reserva}"

    pedido = Pedido(
        usuario_id=current.id_usuario,
        sucursal_id=reserva.sucursal_id,
        total=total,
        metodo_compra="digital",
        estado=estado_pedido,
        tipo_pago=tipo_pago_enum,
    )
    db.add(pedido)
    db.flush()

    for item in reserva.items:
        precio = _precio_variante(db, item.variante_id)
        db.add(
            PedidoItem(
                pedido_id=pedido.id_pedido,
                variante_id=item.variante_id,
                cantidad=item.cantidad,
                precio_unitario=precio,
                subtotal=precio * item.cantidad,
            )
        )

    db.add(
        Pago(
            pedido_id=pedido.id_pedido,
            monto=total,
            proveedor_pago=prov_pago,
            transaccion_id=txn_id,
            estado=estado_pago,
        )
    )

    reserva.estado = "completada"
    db.commit()
    db.refresh(pedido)

    NotificationService.enviar_notificacion_compra_digital(current.email, pedido.id_pedido, float(total))
    return {
        "id_pedido": pedido.id_pedido,
        "total": float(total),
        "estado": estado_pedido.value if hasattr(estado_pedido, "value") else str(estado_pedido),
        "tipo_pago": tipo_pago_enum.value if hasattr(tipo_pago_enum, "value") else str(tipo_pago_enum),
    }



@router.get("/historial", summary="Historial de compras del usuario")
def historial(db: Session = Depends(get_db), current: Usuario = Depends(get_current_user)):
    pedidos = (
        db.query(Pedido)
        .options(
            joinedload(Pedido.items).joinedload(PedidoItem.variante).joinedload(ProductoVariante.producto),
            joinedload(Pedido.items).joinedload(PedidoItem.variante).joinedload(ProductoVariante.talla),
            joinedload(Pedido.items).joinedload(PedidoItem.variante).joinedload(ProductoVariante.color),
            joinedload(Pedido.sucursal),
            joinedload(Pedido.pagos),
        )
        .filter(Pedido.usuario_id == current.id_usuario)
        .order_by(Pedido.fecha_pedido.desc())
        .all()
    )
    
    res = []
    for p in pedidos:
        res.append({
            "id_pedido": p.id_pedido,
            "fecha_pedido": p.fecha_pedido.isoformat() if p.fecha_pedido else None,
            "total": float(p.total),
            "metodo_compra": p.metodo_compra.value if hasattr(p.metodo_compra, 'value') else str(p.metodo_compra),
            "estado": p.estado.value if hasattr(p.estado, 'value') else str(p.estado),
            "tipo_pago": p.tipo_pago.value if p.tipo_pago and hasattr(p.tipo_pago, 'value') else (str(p.tipo_pago) if p.tipo_pago else None),
            "sucursal_nombre": p.sucursal.nombre if p.sucursal else "Tienda en línea",
            "items": [
                {
                    "id_pedido_item": item.id_pedido_item,
                    "cantidad": item.cantidad,
                    "precio_unitario": float(item.precio_unitario),
                    "subtotal": float(item.subtotal),
                    "producto_nombre": item.variante.producto.nombre if item.variante and item.variante.producto else "Producto",
                    "imagen_url": item.variante.producto.imagen_url if item.variante and item.variante.producto else None,
                    "sku": item.variante.sku if item.variante else None,
                    "talla": item.variante.talla.nombre if item.variante and item.variante.talla else None,
                    "color": item.variante.color.nombre if item.variante and item.variante.color else None,
                }
                for item in p.items
            ]
        })
    return res

