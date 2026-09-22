from decimal import Decimal

import stripe
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session, joinedload

from app.core.dependencies import cajero_required, get_current_user
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
from app.schemas.comercio import CarritoItem, VentaDigitalCreate, VentaPresencialCreate
from app.services.notification_service import NotificationService
from app.services.stripe_service import (
    confirmar_pago_simulado,
    crear_intencion_pago,
    crear_sesion_checkout,
    pasarela_operativa,
)

router = APIRouter()


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
    total = Decimal("0")
    for item in items:
        _validar_stock(db, sucursal_id, item.variante_id, item.cantidad)
        total += _precio_variante(db, item.variante_id) * item.cantidad
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

    sucursal_id = data.sucursal_id or 1
    total = _validar_y_total(db, sucursal_id, data.items)

    pedido = Pedido(
        usuario_id=current.id_usuario,
        sucursal_id=sucursal_id,
        total=total,
        metodo_compra="digital",
        estado="pagado",
        tipo_pago="tarjeta_credito",
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
            proveedor_pago="STRIPE",
            transaccion_id=transaccion_id or f"TXN-STRIPE-{pedido.id_pedido}",
            estado="aprobado",
        )
    )

    if pendiente_activa:
        db.delete(pendiente_activa)

    db.commit()
    db.refresh(pedido)

    # Simular notificación de comprobante enviado
    NotificationService.enviar_notificacion_compra_digital(current.email, pedido.id_pedido, float(total))

    return {"id_pedido": pedido.id_pedido, "total": float(total), "estado": "pagado"}


@router.post(
    "/digital/pagar-reserva/{reserva_id}", status_code=status.HTTP_201_CREATED,
    summary="Pagar y convertir reserva a compra digital (CU10)",
)
def pagar_reserva_digital(
    reserva_id: int,
    db: Session = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    from app.models import Reserva
    reserva = db.get(Reserva, reserva_id)
    if not reserva:
        raise HTTPException(status_code=404, detail="Reserva no encontrada")
    if reserva.usuario_id != current.id_usuario and current.rol != "admin":
        raise HTTPException(status_code=403, detail="No tienes permiso sobre esta reserva")
    if reserva.estado.value if hasattr(reserva.estado, 'value') else str(reserva.estado) not in ("pendiente", "preparada"):
        raise HTTPException(status_code=400, detail="Solo se pueden pagar reservas pendientes o preparadas")

    if not confirmar_pago_simulado():
        raise HTTPException(status_code=402, detail="Pago rechazado por la pasarela")

    total = Decimal("0")
    for item in reserva.items:
        precio = _precio_variante(db, item.variante_id)
        total += precio * item.cantidad

    pedido = Pedido(
        usuario_id=current.id_usuario,
        sucursal_id=reserva.sucursal_id,
        total=total,
        metodo_compra="digital",
        estado="pagado",
        tipo_pago="tarjeta_credito",
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
            proveedor_pago="STRIPE",
            transaccion_id=f"TXN-STRIPE-RES-{pedido.id_pedido}",
            estado="aprobado",
        )
    )

    reserva.estado = "completada"
    db.commit()
    db.refresh(pedido)

    NotificationService.enviar_notificacion_compra_digital(current.email, pedido.id_pedido, float(total))
    return {"id_pedido": pedido.id_pedido, "total": float(total), "estado": "pagado"}



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

