"""Transiciones de estado de un cobro QR y reserva del inventario.

La logica vive aqui y no en los endpoints porque la necesitan dos entradas
distintas que deben comportarse igual:

    - el webhook de la pasarela, que confirma el pago desde internet;
    - el punto de venta, que sondea el estado y (en modo simulado) dispara la
      aprobacion.

Si cada entrada tuviera su propia copia, un webhook repetido y un clic en la
interfaz podrian descontar stock de formas distintas.

Modelo de reserva
-----------------
El inventario se descuenta al GENERAR el cobro, no al aprobarlo. Mientras el
cliente no paga, esas unidades quedan comprometidas y ninguna otra venta puede
tomarlas. Si el cobro vence o la pasarela lo rechaza, el inventario vuelve.

Reservar descontando (en vez de marcar una fila aparte) hace que la
restitucion sea exacta: como nadie pudo comprar esas unidades mientras
estaban reservadas, devolver las mismas cantidades devuelve el numero real.
"""

import logging
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from sqlalchemy.orm import Session

from app.models import Inventario, Pago, Pedido, PedidoItem
from app.services.qr_service import (
    PROVEEDOR_LIBELULA,
    consultar_pagos,
    qr_operativa,
)

logger = logging.getLogger(__name__)

# El enum estado_pago no tiene un valor 'vencido', asi que un cobro no pagado se
# almacena como 'rechazado' y el motivo viaja en la respuesta y en el log.
MOTIVO_VENCIDO = "vencido"

PROVEEDORES_QR = ("QR", "SIMULADO", "LIBELULA")


def estado_texto(valor) -> str:
    """Valor legible de un enum SQLAlchemy.

    `str()` sobre un enum de SQLAlchemy devuelve 'EstadoPedido.pendiente', que
    no sirve para comparar ni para enviar al frontend.
    """
    return valor.value if hasattr(valor, "value") else str(valor)


def _stock_de(
    db: Session,
    variante_id: int,
    sucursal_id: int,
    bloquear: bool = False,
) -> Inventario | None:
    """Fila de inventario de una variante en una sucursal.

    Con `bloquear` toma un lock de fila (SELECT ... FOR UPDATE) para que dos
    reservas simultaneas no puedan leer la misma cantidad antes de restarla. Sin
    el, dos cajeros generan cobros a la vez, ambos ven 20 disponibles y ambos
    restan: la segunda escritura pisa a la primera y se sobrevende.
    """
    consulta = db.query(Inventario).filter(
        Inventario.variante_id == variante_id,
        Inventario.sucursal_id == sucursal_id,
    )
    if bloquear:
        consulta = consulta.with_for_update()
    return consulta.first()


def _items_de(db: Session, pedido: Pedido) -> list[PedidoItem]:
    """Lineas del pedido leidas de la base de datos.

    No se usa `pedido.items` porque los items se insertan con `pedido_id` y la
    coleccion de la relacion no llega a poblarse en la misma transaccion que crea
    el cobro. Leerlos por consulta da el mismo resultado siempre.
    """
    return (
        db.query(PedidoItem)
        .filter(PedidoItem.pedido_id == pedido.id_pedido)
        .all()
    )


class StockInsuficienteError(Exception):
    """La reserva no cabe en el inventario disponible.

    Se lanza con las filas ya bloqueadas pero sin haber modificado ninguna
    cantidad, de modo que al soltar la transaccion el inventario queda intacto.
    """

    def __init__(self, faltantes: list[str]):
        self.faltantes = faltantes
        super().__init__("; ".join(faltantes))


def _necesidades(db: Session, pedido: Pedido) -> dict[int, int]:
    """Unidades a mover por variante, agregando lineas repetidas del pedido.

    El POS admite varias lineas de la misma variante. Sumarlas aqui evita
    comparar cada linea por separado contra el stock total, que daria un "si hay
    stock" falso cuando dos lineas compiten por las mismas unidades.
    """
    necesita: dict[int, int] = {}
    for item in _items_de(db, pedido):
        necesita[item.variante_id] = necesita.get(item.variante_id, 0) + item.cantidad
    return necesita


def _plan_reserva(db: Session, pedido: Pedido, bloquear: bool) -> tuple[dict[int, int], dict[int, Inventario]]:
    """Cuanto se necesita por variante y que fila de inventario lo cubre."""
    necesita = _necesidades(db, pedido)
    filas = {
        variante_id: _stock_de(db, variante_id, pedido.sucursal_id, bloquear=bloquear)
        for variante_id in necesita
    }
    return necesita, filas


def _faltantes(necesita: dict[int, int], filas: dict[int, Inventario]) -> list[str]:
    """Variantes cuya reserva no entra, con el detalle de quanto falta."""
    problemas = []
    for variante_id, cantidad in necesita.items():
        stock = filas.get(variante_id)
        # Una variante sin fila de inventario no tiene control de stock en esa
        # sucursal: es el mismo criterio que ya usa el resto del punto de venta.
        if stock and stock.cantidad_disponible < cantidad:
            problemas.append(
                f"variante {variante_id}: disponibles {stock.cantidad_disponible}, "
                f"solicitados {cantidad}"
            )
    return problemas


def reservar_stock(db: Session, pedido: Pedido) -> None:
    """Descuenta el inventario del pedido como reserva del cobro.

    Se invoca al crear el cobro, dentro de la misma transaccion que lo persiste.
    La comprobacion de disponibilidad y el descuento ocurren bajo un lock de
    fila, no en dos pasos: por eso el punto de venta puede validar antes (para
    dar un mensaje claro) pero la garantia real de no sobrevender esta aqui.
    """
    db.flush()  # asegura que las lineas del pedido existan antes de descontar
    necesita, filas = _plan_reserva(db, pedido, bloquear=True)
    problemas = _faltantes(necesita, filas)
    if problemas:
        raise StockInsuficienteError(problemas)

    for variante_id, cantidad in necesita.items():
        stock = filas[variante_id]
        if stock:
            stock.cantidad_disponible -= cantidad


def liberar_stock(db: Session, pedido: Pedido) -> None:
    """Devuelve al inventario las unidades reservadas por un cobro que no se cobro."""
    necesita, filas = _plan_reserva(db, pedido, bloquear=True)
    for variante_id, cantidad in necesita.items():
        stock = filas[variante_id]
        if stock:
            stock.cantidad_disponible += cantidad


def hay_stock_para(db: Session, pedido: Pedido) -> bool:
    """Si el pedido vuelve a caber hoy en el inventario. No modifica nada.

    Es la consulta que necesita la reapertura de un pago tardio, donde interesa
    un veredicto y no una excepcion como en la reserva.
    """
    necesita, filas = _plan_reserva(db, pedido, bloquear=True)
    return not _faltantes(necesita, filas)


def _cerrar_pedido(db: Session, pago: Pago) -> Pedido | None:
    pedido = db.get(Pedido, pago.pedido_id)
    if pedido is None:
        logger.error("El pago %s no tiene pedido asociado", pago.id_pago)
    return pedido


def aprobar_cobro_qr(db: Session, pago: Pago) -> dict:
    """Aprueba un cobro QR pendiente y cierra el pedido como pagado.

    No toca el inventario: ya estaba reservado al generar el cobro.

    Es idempotente. Si el pago ya no esta pendiente devuelve el estado actual
    sin repetir efectos, de modo que un webhook repetido o un doble clic no
    generan dos cierres ni liberan dos veces el stock.
    """
    estado = estado_texto(pago.estado)
    if estado != "pendiente":
        return {"estado": estado, "aplicado": False, "id_pago": pago.id_pago}

    pedido = _cerrar_pedido(db, pago)
    if pedido is None:
        return {"estado": estado, "aplicado": False, "id_pago": pago.id_pago}

    pago.estado = "aprobado"
    pedido.estado = "pagado"
    db.commit()

    return {"estado": "aprobado", "aplicado": True, "id_pago": pago.id_pago}


def rechazar_cobro_qr(db: Session, pago: Pago, motivo: str) -> dict:
    """Cancela un cobro que no se pudo cobrar y devuelve el inventario reservado."""
    estado = estado_texto(pago.estado)
    if estado != "pendiente":
        return {"estado": estado, "aplicado": False, "id_pago": pago.id_pago}

    pago.estado = "rechazado"
    pedido = _cerrar_pedido(db, pago)
    if pedido is not None:
        if estado_texto(pedido.estado) != "pagado":
            pedido.estado = "cancelado"
        liberar_stock(db, pedido)
    db.commit()

    return {
        "estado": "rechazado",
        "motivo": motivo,
        "aplicado": True,
        "id_pago": pago.id_pago,
    }


def vencer_cobro_qr(db: Session, pago: Pago) -> dict:
    """Cancela un cobro que supero su ventana de pago."""
    return rechazar_cobro_qr(db, pago, MOTIVO_VENCIDO)


def limite_de_pago(pago: Pago) -> datetime | None:
    """Instante en que el cobro deja de ser pagable, o None si no se conoce.

    El vencimiento lo dicta la pasarela, asi que se lee de `datos_gateway` en
    lugar de un campo propio de `pagos`.
    """
    crudo = (pago.datos_gateway or {}).get("expires_at")
    if not crudo:
        return None
    try:
        limite = datetime.fromisoformat(crudo)
    except (TypeError, ValueError):
        logger.warning("Vencimiento ilegible en el pago %s: %r", pago.id_pago, crudo)
        return None
    if limite.tzinfo is None:
        limite = limite.replace(tzinfo=timezone.utc)
    return limite


def cobro_vencido(pago: Pago, ahora: datetime | None = None) -> bool:
    """True si el cobro sigue pendiente pero su ventana de pago ya paso."""
    if estado_texto(pago.estado) != "pendiente":
        return False
    limite = limite_de_pago(pago)
    if limite is None:
        return False
    return (ahora or datetime.now(timezone.utc)) > limite


def vencer_cobros_vencidos(db: Session) -> int:
    """Vence todos los cobros QR pendientes cuya ventana ya paso.

    El punto de venta tambien vence de forma perezosa al consultar el estado, pero
    un cobro abandonado (el cliente se retiro y el cajero genero otro) no vuelve a
    consultarse nunca. Sin este barrido, sus unidades quedarian reservadas para
    siempre. Es idempotente: solo toca cobros en estado pendiente.
    """
    pendientes = (
        db.query(Pago)
        .filter(Pago.estado == "pendiente", Pago.proveedor_pago.in_(PROVEEDORES_QR))
        .all()
    )
    vencidos = 0
    for pago in pendientes:
        if cobro_vencido(pago):
            vencer_cobro_qr(db, pago)
            vencidos += 1
    if vencidos:
        logger.info("Barrido QR: %s cobro(s) vencido(s) y liberados", vencidos)
    return vencidos


def monto_coincide(pago: Pago, monto_recibido: Decimal | float | None) -> bool:
    """Comprueba que lo cobrado por la pasarela sea lo que el sistema espera.

    Sin esto, un pago parcial de Libelula aprobaria el pedido completo.
    """
    if monto_recibido is None:
        return True
    return abs(Decimal(str(monto_recibido)) - Decimal(pago.monto)) < Decimal("0.01")


def _monto_registrado(registro: dict) -> Decimal | None:
    """`monto_pagado` de la pasarela, con el nombre que documented el manual."""
    crudo = registro.get("monto_pagado", registro.get("monto"))
    if crudo is None:
        return None
    try:
        return Decimal(str(crudo))
    except (TypeError, ValueError, ArithmeticError):
        logger.warning("Monto ilegible en la conciliacion: %r", crudo)
        return None


def resolver_pago_confirmado(db: Session, pago: Pago, registro: dict) -> dict:
    """Aplica un pago que la pasarela ya confirme, incluso si aqui vencio.

    La pasarela no puede imponer una ventana de minutos: `fecha_vencimiento` en
    Libelula es de granularidad diaria, asi que sigue aceptando el pago horas
    despues de que este sistema lo dio por vencido. Cuando eso pasa hay dinero
    real de por medio y no se puede ignorar en silencio.

    Que hacer depende del inventario:

        - si el pedido vuelve a caber, se reabre: se reserva de nuevo el stock,
          el pago queda aprobado y el pedido pagado. El cliente se lleva la
          compra que si pago.
        - si no cabe, esas unidades ya se vendieron a otro. El pago se registra
          con el detalle en `datos_gateway` y queda `rechazado`, para que el
          dinero se devuelva. No se inventa stock que no existe.

    El enum `estado_pago` es nativo de Postgres, asi que agregar un valor
    'pago_tardio' exigiria un `ALTER TYPE` y una migracion. El detalle vive en
    `datos_gateway` y el log queda en nivel ERROR para que salte a un humano.
    """
    monto = _monto_registrado(registro)

    # El monto se verifica PRIMERO, antes de mirar el estado. Si se comprobara
    # despues, un cobro pendiente con pago parcial caeria en la rama de
    # aprobacion y cerraria el pedido completo por una parte del dinero.
    if not monto_coincide(pago, monto):
        # Se recibio dinero, pero no el monto del pedido. Es el peor caso: hay
        # que detenerlo para que una persona lo resuelva, nunca aprobar en falso.
        datos = dict(pago.datos_gateway or {})
        datos["pago_tardio"] = {
            "estado": "monto_discrepante",
            "monto_esperado": float(Decimal(pago.monto)),
            "monto_recibido": float(monto) if monto is not None else None,
            "codigo_recaudacion": registro.get("codigo_recaudacion"),
            "fecha_pago": registro.get("fecha_pago"),
        }
        pago.datos_gateway = datos
        db.commit()
        logger.error(
            "MONTO DISCREPANTE en el pago %s: se esperaban %s y la pasarela reporta %s. "
            "Requiere devolucion o cobro de la diferencia.",
            pago.id_pago, pago.monto, monto,
        )
        return {
            "estado": estado_texto(pago.estado),
            "aplicado": False,
            "id_pago": pago.id_pago,
            "caso": "monto_discrepante",
            "detalle": "El monto cobrado no coincide con el pedido; requiere revision manual",
        }

    if estado_texto(pago.estado) == "pendiente":
        # El stock sigue reservado desde que se genero el cobro, asi que aqui
        # solo se cierra el pago y el pedido.
        return aprobar_cobro_qr(db, pago)

    estado = estado_texto(pago.estado)
    if estado != "rechazado":
        # 'aprobado' o 'reembolsado': la notificacion llego repetida y no hay
        # nada que hacer. Entrar aqui seria peligroso: reabrir un pago ya
        # cobrado volveria a descontar inventario que ya se entrego.
        return {"estado": estado, "aplicado": False, "id_pago": pago.id_pago}

    pedido = _cerrar_pedido(db, pago)
    if pedido is None:
        return {"estado": estado, "aplicado": False, "id_pago": pago.id_pago}

    if hay_stock_para(db, pedido):
        reservar_stock(db, pedido)
        pago.estado = "aprobado"
        pedido.estado = "pagado"
        datos = dict(pago.datos_gateway or {})
        datos["pago_tardio"] = {
            "estado": "reabierto",
            "codigo_recaudacion": registro.get("codigo_recaudacion"),
            "fecha_pago": registro.get("fecha_pago"),
        }
        pago.datos_gateway = datos
        db.commit()
        logger.warning(
            "PAGO TARDIO reabierta: la transaccion %s se cobro fuera de plazo pero el "
            "pedido %s volvio a caber en inventario.",
            pago.transaccion_id, pedido.id_pedido,
        )
        return {
            "estado": "aprobado",
            "aplicado": True,
            "reabierto": True,
            "id_pago": pago.id_pago,
        }

    datos = dict(pago.datos_gateway or {})
    datos["pago_tardio"] = {
        "estado": "sin_stock",
        "codigo_recaudacion": registro.get("codigo_recaudacion"),
        "fecha_pago": registro.get("fecha_pago"),
        "monto": float(monto) if monto is not None else None,
    }
    pago.datos_gateway = datos
    db.commit()
    logger.error(
        "PAGO TARDIO SIN STOCK: la transaccion %s se cobro en la pasarela pero el pedido "
        "%s ya no tiene inventario. Se debe devolver el dinero (pago %s).",
        pago.transaccion_id, pedido.id_pedido, pago.id_pago,
    )
    return {
        "estado": estado_texto(pago.estado),
        "aplicado": False,
        "id_pago": pago.id_pago,
        "caso": "sin_stock",
        "detalle": "Pago recibido fuera de plazo y sin stock disponible; requiere devolucion",
    }


def conciliar_cobros_pendientes(db: Session, horas: int = 36) -> int:
    """Confirma contra la pasarela los cobros QR que siguen pendientes.

    La notificacion de Libelula no es una garantia: la propia documentacion
    reconoce que esas llamadas se pierden. Si el cliente paga y la notificacion
    no llega, el cobro queda pendiente hasta vencer, el stock se devuelve y el
    cliente habria pagado sin recibir nada.

    Este barrido es la red que cubre ese caso. Hace UNA sola consulta a la
    pasarela para toda la ventana (que es justo para lo que sirve
    `consultar_pagos`, que no permite filtrar por transaccion) y luego cruza en
    memoria, en vez de llamar una vez por cobro.

    Se miran tambien los cobros `rechazado`, no solo los `pendiente`: ese es el
    caso del pago tardio con la notificacion perdida. El cliente pago, el aviso
    se perdio, el cobro vencio y el stock se devolvio. Si la conciliacion solo
    mirara pendientes, ese dinero se perderia en silencio. Aqui la pasarela dice
    que si se cobro, y `resolver_pago_confirmado` reabre o deja para devolucion.

    La busqueda esta acotada por `fecha_pago` y solo abarca cobros de la pasarela
    real. Es idempotente: lo ya aprobado o reembolsado deja de aparecer.
    """
    if not qr_operativa():
        return 0

    desde_pago = datetime.now(timezone.utc) - timedelta(hours=horas)

    # Los identificadores se leen antes del bucle porque `aprobar_cobro_qr`
    # confirma la transaccion y dejaria obsoletos los objetos ya cargados.
    pendientes = [
        (pago.id_pago, (pago.transaccion_id or "").strip())
        for pago in db.query(Pago)
        .filter(
            Pago.estado.in_(("pendiente", "rechazado")),
            Pago.proveedor_pago == PROVEEDOR_LIBELULA,
            Pago.fecha_pago >= desde_pago,
        )
        .all()
    ]
    if not pendientes:
        return 0

    hasta = datetime.now(timezone.utc)
    registros = consultar_pagos(desde_pago, hasta)
    if not registros:
        return 0

    por_transaccion = {
        str(registro.get("id_transaccion") or "").strip(): registro
        for registro in registros
        if registro.get("id_transaccion")
    }

    confirmados = 0
    for id_pago, transaccion_id in pendientes:
        registro = por_transaccion.get(transaccion_id)
        if registro is None:
            continue
        pago = db.get(Pago, id_pago)
        if pago is None or estado_texto(pago.estado) not in ("pendiente", "rechazado"):
            continue
        resultado = resolver_pago_confirmado(db, pago, registro)
        if resultado.get("aplicado"):
            confirmados += 1
        elif resultado.get("detalle"):
            # No se aprobo y hay dinero de por medio: la conciliation lo deja
            # registrado y el log ya salio en nivel ERROR.
            logger.error(
                "Conciliacion: el pago %s no pudo cerrarse (%s)",
                id_pago, resultado.get("detalle"),
            )

    if confirmados:
        logger.info("Conciliacion QR: %s cobro(s) confirmado(s) con la pasarela", confirmados)
    return confirmados
