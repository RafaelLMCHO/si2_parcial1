from datetime import date

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session, joinedload

from app.api.v1.endpoints.bitacora import registrar
from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.models import (
    Inventario,
    Pedido,
    PedidoItem,
    Producto,
    ProductoVariante,
    Temporada,
    Usuario,
)
from app.schemas.comercio import ProductoOut

router = APIRouter()


def _temporada_actual(db: Session):
    """Obtiene la temporada vigente según fecha actual."""
    hoy = date.today()
    return (
        db.query(Temporada)
        .filter(Temporada.fecha_inicio <= hoy, Temporada.fecha_fin >= hoy)
        .first()
    )


def _variantes_historial(db: Session, usuario_id: int):
    """Variantes adquiridas por el cliente según su historial de pedidos."""
    return (
        db.query(ProductoVariante)
        .join(PedidoItem, PedidoItem.variante_id == ProductoVariante.id_variante)
        .join(Pedido, Pedido.id_pedido == PedidoItem.pedido_id)
        .filter(Pedido.usuario_id == usuario_id)
        .all()
    )


def _preferencias_historial(db: Session, usuario_id: int):
    """Preferencias del cliente según su historial:
    (categorías_ids, tallas_ids, colores_ids)."""
    variantes = _variantes_historial(db, usuario_id)
    if not variantes:
        return set(), set(), set()

    productos = (
        db.query(Producto)
        .filter(Producto.id_producto.in_([v.producto_id for v in variantes]))
        .all()
    )
    categoria_ids = {p.categoria_id for p in productos}
    talla_ids = {v.talla_id for v in variantes if v.talla_id}
    color_ids = {v.color_id for v in variantes if v.color_id}
    return categoria_ids, talla_ids, color_ids


def _ids_con_stock(db: Session, sucursal_id: int | None):
    """Ids de productos con al menos una variante disponible en la sucursal."""
    if sucursal_id is None:
        return None
    rows = (
        db.query(Producto.id_producto)
        .join(Producto.variantes)
        .join(Inventario, Inventario.variante_id == ProductoVariante.id_variante)
        .filter(
            Inventario.sucursal_id == sucursal_id,
            Inventario.cantidad_disponible > 0,
        )
        .all()
    )
    return set(r[0] for r in rows)


def _producto_base(db: Session):
    """Query base de productos activos con todas las relaciones cargadas."""
    return (
        db.query(Producto)
        .options(
            joinedload(Producto.categoria),
            joinedload(Producto.temporada),
            joinedload(Producto.proveedor),
            joinedload(Producto.coleccion),
            joinedload(Producto.variantes).joinedload(ProductoVariante.color),
            joinedload(Producto.variantes).joinedload(ProductoVariante.talla),
        )
        .filter(Producto.activo == True)  # noqa: E712
    )


@router.get(
    "/recomendaciones",
    response_model=list[ProductoOut],
    summary="Recomendar prendas según historial, temporada y disponibilidad (CU17, RF25)",
)
def recomendar(
    limit: int = Query(default=6, ge=1, le=30),
    db: Session = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    """CU-17 · Asistente/recomendador de IA: sugiere productos considerando
    las preferencias del cliente (categorías, tallas y colores de su historial),
    la temporada actual y la disponibilidad local en su sucursal."""
    categoria_ids, talla_ids, color_ids = _preferencias_historial(
        db, current.id_usuario
    )
    temporada = _temporada_actual(db)
    con_stock = _ids_con_stock(db, current.sucursal_id)

    query = _producto_base(db)

    if temporada:
        query = query.filter(Producto.temporada_id == temporada.id_temporada)
    if con_stock is not None:
        query = query.filter(Producto.id_producto.in_(con_stock))
    if talla_ids:
        query = query.filter(
            Producto.id_producto.in_(
                db.query(ProductoVariante.producto_id).filter(
                    ProductoVariante.talla_id.in_(talla_ids)
                )
            )
        )
    if color_ids:
        query = query.filter(
            Producto.id_producto.in_(
                db.query(ProductoVariante.producto_id).filter(
                    ProductoVariante.color_id.in_(color_ids)
                )
            )
        )

    if categoria_ids:
        destacados = (
            query.filter(Producto.categoria_id.in_(categoria_ids))
            .order_by(Producto.precio)
            .limit(limit)
            .all()
        )
        if len(destacados) >= limit:
            resultado = destacados
        else:
            restantes = (
                query.filter(~Producto.categoria_id.in_(categoria_ids))
                .order_by(Producto.precio)
                .limit(limit - len(destacados))
                .all()
            )
            resultado = destacados + restantes
    else:
        resultado = query.order_by(Producto.precio).limit(limit).all()

    _registrar_recomendacion(db, current, len(resultado))
    return resultado


@router.get(
    "/recomendaciones/disponibles",
    response_model=list[ProductoOut],
    summary="Recomendar prendas disponibles en una sucursal específica (CU17)",
)
def recomendar_por_sucursal(
    sucursal_id: int,
    limit: int = Query(default=6, ge=1, le=30),
    db: Session = Depends(get_db),
):
    """CU-17 · Productos con stock disponible en una sucursal concreta."""
    ids_con_stock = _ids_con_stock(db, sucursal_id)
    if not ids_con_stock:
        return []

    temporada = _temporada_actual(db)
    query = _producto_base(db).filter(Producto.id_producto.in_(ids_con_stock))
    if temporada:
        query = query.filter(Producto.temporada_id == temporada.id_temporada)
    return query.order_by(Producto.precio).limit(limit).all()


def _registrar_recomendacion(db: Session, usuario: Usuario, cantidad: int):
    """CU-23 · Registra la consulta de recomendaciones (no interrumpe el flujo)."""
    previo = db.expire_on_commit
    db.expire_on_commit = False
    try:
        registrar(
            db,
            usuario_id=usuario.id_usuario,
            accion="CONSULTA_RECOMENDACIONES",
            entidad="producto",
            detalle=f"IA (CU17): {cantidad} recomendaciones generadas",
        )
    finally:
        db.expire_on_commit = previo