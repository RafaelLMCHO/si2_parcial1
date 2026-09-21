from datetime import date, datetime, time
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.api.v1.endpoints.bitacora import registrar
from app.core.dependencies import encargado_required
from app.db.session import get_db
from app.models import (
    Categoria,
    Color,
    Inventario,
    Pago,
    Pedido,
    PedidoItem,
    Producto,
    ProductoVariante,
    Reserva,
    Sucursal,
    Talla,
    Temporada,
    Usuario,
    EstadoPago,
)
from app.schemas.reportes import (
    MasVendidoRow,
    ProductoRank,
    ReservaEstadoRow,
    ReservasReporte,
    ReservaSucursalRow,
    ResumenReporte,
    RotacionRow,
    StockCriticoRow,
    TendenciaRow,
    VentaSucursalRow,
)

router = APIRouter()


def _to_datetime(iso: str, fin_dia: bool = False) -> datetime:
    d = date.fromisoformat(iso)
    if fin_dia:
        return datetime.combine(d, time(23, 59, 59, 999999))
    return datetime.combine(d, time.min)


class _Filtros:
    """Filtros comunes de los reportes + restricción por rol (CU-16)."""

    def __init__(
        self,
        current: Usuario,
        fecha_desde: str | None,
        fecha_hasta: str | None,
        sucursal_id: int | None,
        categoria_id: int | None,
        temporada_id: int | None,
    ):
        if fecha_desde and fecha_hasta and fecha_desde > fecha_hasta:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="La fecha de inicio no puede ser mayor que la fecha de fin",
            )
        self.desde = _to_datetime(fecha_desde) if fecha_desde else None
        self.hasta = _to_datetime(fecha_hasta, fin_dia=True) if fecha_hasta else None
        self.categoria_id = categoria_id
        self.temporada_id = temporada_id

        if current.rol == "encargado":
            if not current.sucursal_id:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="No tiene sucursal asignada, contacte al administrador",
                )
            self.sucursal_id = current.sucursal_id
        else:
            self.sucursal_id = sucursal_id


def _apply_pedido_filtros(db: Session, q, f: _Filtros):
    """Aplica sucursal, rango de fechas y filtro de producto al query de pedidos."""
    if f.sucursal_id:
        q = q.filter(Pedido.sucursal_id == f.sucursal_id)
    if f.desde:
        q = q.filter(Pedido.fecha_pedido >= f.desde)
    if f.hasta:
        q = q.filter(Pedido.fecha_pedido <= f.hasta)
    if f.categoria_id or f.temporada_id:
        sub = (
            db.query(PedidoItem.pedido_id)
            .join(ProductoVariante, ProductoVariante.id_variante == PedidoItem.variante_id)
            .join(Producto, Producto.id_producto == ProductoVariante.producto_id)
        )
        if f.categoria_id:
            sub = sub.filter(Producto.categoria_id == f.categoria_id)
        if f.temporada_id:
            sub = sub.filter(Producto.temporada_id == f.temporada_id)
        q = q.filter(Pedido.id_pedido.in_(sub))
    return q


def _base_mas_vendidos(db: Session, f: _Filtros):
    """Team de consulta de productos más vendidos (unidades y monto)."""
    q = (
        db.query(
            Producto.nombre,
            Categoria.nombre,
            func.sum(PedidoItem.cantidad),
            func.coalesce(func.sum(PedidoItem.subtotal), 0),
        )
        .select_from(PedidoItem)
        .join(Pedido, Pedido.id_pedido == PedidoItem.pedido_id)
        .join(ProductoVariante, ProductoVariante.id_variante == PedidoItem.variante_id)
        .join(Producto, Producto.id_producto == ProductoVariante.producto_id)
        .join(Categoria, Categoria.id_categoria == Producto.categoria_id)
        .group_by(Producto.id_producto, Producto.nombre, Categoria.nombre)
    )
    return _apply_pedido_filtros(db, q, f)


def _registrar_reporte(
    db: Session,
    usuario: Usuario,
    tipo: str,
    ip: str | None,
    detalle: str,
):
    """CU-23 · Registra la generación del reporte (no interrumpe el flujo)."""
    previo = db.expire_on_commit
    db.expire_on_commit = False
    try:
        registrar(
            db,
            usuario_id=usuario.id_usuario,
            accion="GENERA_REPORTE",
            entidad="reporte",
            detalle=f"CU16 {tipo}: {detalle}",
            ip_origen=ip,
        )
    finally:
        db.expire_on_commit = previo


def _valor_enum(v):
    """Devuelve el valor legible de un enum de PostgreSQL/SQLAlchemy."""
    return getattr(v, "value", v)


@router.get(
    "/resumen",
    response_model=ResumenReporte,
    summary="Resumen ejecutivo de KPIs (CU16)",
)
def reporte_resumen(
    request: Request,
    fecha_desde: Optional[str] = Query(None, description="YYYY-MM-DD"),
    fecha_hasta: Optional[str] = Query(None, description="YYYY-MM-DD"),
    sucursal_id: Optional[int] = Query(None),
    categoria_id: Optional[int] = Query(None),
    temporada_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current: Usuario = Depends(encargado_required),
):
    """CU-16 · KPI principales: ventas del período, pedidos, stock crítico,
    reservas activas y productos más vendidos (dashboard)."""
    f = _Filtros(current, fecha_desde, fecha_hasta, sucursal_id, categoria_id, temporada_id)

    ventas_total = _apply_pedido_filtros(
        db,
        db.query(func.coalesce(func.sum(Pago.monto), 0))
        .select_from(Pago)
        .join(Pedido, Pedido.id_pedido == Pago.pedido_id),
        f,
    ).filter(Pago.estado == EstadoPago.aprobado).scalar() or 0

    total_pedidos = _apply_pedido_filtros(
        db,
        db.query(func.count(func.distinct(Pedido.id_pedido))),
        f,
    ).scalar() or 0

    total_productos = db.query(func.count(Producto.id_producto)).scalar() or 0

    q_stock = db.query(func.count(Inventario.id_inventario)).filter(
        Inventario.cantidad_disponible <= Inventario.stock_minimo
    )
    if f.sucursal_id:
        q_stock = q_stock.filter(Inventario.sucursal_id == f.sucursal_id)
    if f.categoria_id or f.temporada_id:
        q_stock = (
            q_stock.join(ProductoVariante, ProductoVariante.id_variante == Inventario.variante_id)
            .join(Producto, Producto.id_producto == ProductoVariante.producto_id)
        )
        if f.categoria_id:
            q_stock = q_stock.filter(Producto.categoria_id == f.categoria_id)
        if f.temporada_id:
            q_stock = q_stock.filter(Producto.temporada_id == f.temporada_id)
    stock_critico = q_stock.scalar() or 0

    q_reservas = db.query(func.count(Reserva.id_reserva)).filter(
        Reserva.estado.in_(["pendiente", "preparada"])
    )
    if f.sucursal_id:
        q_reservas = q_reservas.filter(Reserva.sucursal_id == f.sucursal_id)
    if f.desde:
        q_reservas = q_reservas.filter(Reserva.fecha_reserva >= f.desde.date())
    if f.hasta:
        q_reservas = q_reservas.filter(Reserva.fecha_reserva <= f.hasta.date())
    reservas_activas = q_reservas.scalar() or 0

    top = _base_mas_vendidos(db, f).order_by(
        func.sum(PedidoItem.cantidad).desc()
    ).limit(3).all()

    _registrar_reporte(
        db, current, "resumen", request.client.host if request.client else None,
        f"desde={fecha_desde or '-'}, hasta={fecha_hasta or '-'}, sucursal={f.sucursal_id or '-'}",
    )

    return ResumenReporte(
        ventas_total=float(ventas_total),
        total_pedidos=int(total_pedidos),
        total_productos=int(total_productos),
        stock_critico=int(stock_critico),
        reservas_activas=int(reservas_activas),
        top_productos=[
            ProductoRank(producto=r[0], categoria=r[1], unidades=int(r[2]), monto=float(r[3]))
            for r in top
        ],
    )


@router.get(
    "/ventas-por-sucursal",
    response_model=list[VentaSucursalRow],
    summary="Ventas por sucursal (CU16)",
)
def reporte_ventas_sucursal(
    request: Request,
    fecha_desde: Optional[str] = Query(None, description="YYYY-MM-DD"),
    fecha_hasta: Optional[str] = Query(None, description="YYYY-MM-DD"),
    sucursal_id: Optional[int] = Query(None),
    categoria_id: Optional[int] = Query(None),
    temporada_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current: Usuario = Depends(encargado_required),
):
    """CU-16 · Ventas agregadas por sucursal (gráfico de barras)."""
    f = _Filtros(current, fecha_desde, fecha_hasta, sucursal_id, categoria_id, temporada_id)
    q = (
        db.query(
            Pedido.sucursal_id,
            Sucursal.nombre,
            func.coalesce(func.sum(Pago.monto), 0),
        )
        .join(Pago, Pago.pedido_id == Pedido.id_pedido)
        .join(Sucursal, Sucursal.id_sucursal == Pedido.sucursal_id)
    )
    q = _apply_pedido_filtros(db, q, f).filter(Pago.estado == EstadoPago.aprobado)
    rows = (
        q.group_by(Pedido.sucursal_id, Sucursal.nombre)
        .order_by(func.sum(Pago.monto).desc())
        .all()
    )

    _registrar_reporte(
        db, current, "ventas-por-sucursal", request.client.host if request.client else None,
        f"desde={fecha_desde or '-'}, hasta={fecha_hasta or '-'}",
    )
    return [
        VentaSucursalRow(sucursal_id=r[0], sucursal=r[1], total=float(r[2])) for r in rows
    ]


@router.get(
    "/mas-vendidos",
    response_model=list[MasVendidoRow],
    summary="Productos más vendidos (CU16)",
)
def reporte_mas_vendidos(
    request: Request,
    limit: int = Query(10, ge=1, le=100),
    fecha_desde: Optional[str] = Query(None, description="YYYY-MM-DD"),
    fecha_hasta: Optional[str] = Query(None, description="YYYY-MM-DD"),
    sucursal_id: Optional[int] = Query(None),
    categoria_id: Optional[int] = Query(None),
    temporada_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current: Usuario = Depends(encargado_required),
):
    """CU-16 · Ranking de productos por unidades vendidas."""
    f = _Filtros(current, fecha_desde, fecha_hasta, sucursal_id, categoria_id, temporada_id)
    rows = (
        _base_mas_vendidos(db, f)
        .order_by(func.sum(PedidoItem.cantidad).desc())
        .limit(limit)
        .all()
    )
    _registrar_reporte(
        db, current, "mas-vendidos", request.client.host if request.client else None,
        f"limit={limit}, desde={fecha_desde or '-'}, hasta={fecha_hasta or '-'}",
    )
    return [
        MasVendidoRow(producto=r[0], categoria=r[1], unidades=int(r[2]), monto=float(r[3]))
        for r in rows
    ]


@router.get(
    "/rotacion-inventario",
    response_model=list[RotacionRow],
    summary="Rotación de inventario por producto (CU16)",
)
def reporte_rotacion(
    request: Request,
    limit: int = Query(10, ge=1, le=100),
    fecha_desde: Optional[str] = Query(None, description="YYYY-MM-DD"),
    fecha_hasta: Optional[str] = Query(None, description="YYYY-MM-DD"),
    sucursal_id: Optional[int] = Query(None),
    categoria_id: Optional[int] = Query(None),
    temporada_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current: Usuario = Depends(encargado_required),
):
    """CU-16 · Rotación = unidades vendidas en el período / stock actual."""
    f = _Filtros(current, fecha_desde, fecha_hasta, sucursal_id, categoria_id, temporada_id)

    vendidas = (
        db.query(
            Producto.id_producto,
            Producto.nombre,
            func.coalesce(func.sum(PedidoItem.cantidad), 0),
        )
        .select_from(PedidoItem)
        .join(Pedido, Pedido.id_pedido == PedidoItem.pedido_id)
        .join(ProductoVariante, ProductoVariante.id_variante == PedidoItem.variante_id)
        .join(Producto, Producto.id_producto == ProductoVariante.producto_id)
    )
    vendidas = _apply_pedido_filtros(db, vendidas, f)
    vendidas_rows = {
        r[0]: (r[1], int(r[2])) for r in vendidas.group_by(Producto.id_producto, Producto.nombre).all()
    }

    stock = db.query(
        Producto.id_producto,
        func.coalesce(func.sum(Inventario.cantidad_disponible), 0),
    ).select_from(Inventario).join(
        ProductoVariante, ProductoVariante.id_variante == Inventario.variante_id
    ).join(Producto, Producto.id_producto == ProductoVariante.producto_id)
    if f.sucursal_id:
        stock = stock.filter(Inventario.sucursal_id == f.sucursal_id)
    if f.categoria_id:
        stock = stock.filter(Producto.categoria_id == f.categoria_id)
    if f.temporada_id:
        stock = stock.filter(Producto.temporada_id == f.temporada_id)
    stock_rows = {r[0]: int(r[1]) for r in stock.group_by(Producto.id_producto).all()}

    resultado: list[RotacionRow] = []
    for pid, (nombre, vend) in vendidas_rows.items():
        stock_actual = stock_rows.get(pid, 0)
        if stock_actual <= 0:
            continue
        resultado.append(
            RotacionRow(
                producto=nombre,
                unidades_vendidas=vend,
                stock_actual=stock_actual,
                rotacion=round(vend / stock_actual, 2),
            )
        )
    resultado.sort(key=lambda r: r.rotacion, reverse=True)

    _registrar_reporte(
        db, current, "rotacion-inventario", request.client.host if request.client else None,
        f"limit={limit}, desde={fecha_desde or '-'}, hasta={fecha_hasta or '-'}",
    )
    return resultado[:limit]


@router.get(
    "/stock-critico",
    response_model=list[StockCriticoRow],
    summary="Niveles de stock crítico (CU16)",
)
def reporte_stock_critico(
    request: Request,
    fecha_desde: Optional[str] = Query(None, description="YYYY-MM-DD"),
    fecha_hasta: Optional[str] = Query(None, description="YYYY-MM-DD"),
    sucursal_id: Optional[int] = Query(None),
    categoria_id: Optional[int] = Query(None),
    temporada_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current: Usuario = Depends(encargado_required),
):
    """CU-16 · Variantes con stock disponible menor o igual al mínimo."""
    f = _Filtros(current, fecha_desde, fecha_hasta, sucursal_id, categoria_id, temporada_id)
    q = (
        db.query(
            Producto.nombre,
            Talla.nombre,
            Color.nombre,
            ProductoVariante.sku,
            Sucursal.nombre,
            Inventario.stock_minimo,
            Inventario.cantidad_disponible,
        )
        .select_from(Inventario)
        .join(ProductoVariante, ProductoVariante.id_variante == Inventario.variante_id)
        .join(Producto, Producto.id_producto == ProductoVariante.producto_id)
        .join(Talla, Talla.id_talla == ProductoVariante.talla_id)
        .join(Color, Color.id_color == ProductoVariante.color_id)
        .join(Sucursal, Sucursal.id_sucursal == Inventario.sucursal_id)
        .filter(Inventario.cantidad_disponible <= Inventario.stock_minimo)
    )
    if f.sucursal_id:
        q = q.filter(Inventario.sucursal_id == f.sucursal_id)
    if f.categoria_id:
        q = q.filter(Producto.categoria_id == f.categoria_id)
    if f.temporada_id:
        q = q.filter(Producto.temporada_id == f.temporada_id)
    rows = q.order_by(Inventario.cantidad_disponible.asc()).all()

    _registrar_reporte(
        db, current, "stock-critico", request.client.host if request.client else None,
        f"desde={fecha_desde or '-'}, hasta={fecha_hasta or '-'}, sucursal={f.sucursal_id or '-'}",
    )
    return [
        StockCriticoRow(
            producto=r[0],
            talla=r[1],
            color=r[2],
            sku=r[3],
            sucursal=r[4],
            stock_minimo=int(r[5]),
            disponible=int(r[6]),
            faltante=max(0, int(r[5]) - int(r[6])),
        )
        for r in rows
    ]


@router.get(
    "/reservas",
    response_model=ReservasReporte,
    summary="Comportamiento de reservas (CU16)",
)
def reporte_reservas(
    request: Request,
    fecha_desde: Optional[str] = Query(None, description="YYYY-MM-DD"),
    fecha_hasta: Optional[str] = Query(None, description="YYYY-MM-DD"),
    sucursal_id: Optional[int] = Query(None),
    categoria_id: Optional[int] = Query(None),
    temporada_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current: Usuario = Depends(encargado_required),
):
    """CU-16 · Reservas por estado y por sucursal."""
    f = _Filtros(current, fecha_desde, fecha_hasta, sucursal_id, categoria_id, temporada_id)

    q_estado = db.query(Reserva.estado, func.count(Reserva.id_reserva))
    if f.sucursal_id:
        q_estado = q_estado.filter(Reserva.sucursal_id == f.sucursal_id)
    if f.desde:
        q_estado = q_estado.filter(Reserva.fecha_reserva >= f.desde.date())
    if f.hasta:
        q_estado = q_estado.filter(Reserva.fecha_reserva <= f.hasta.date())
    por_estado = q_estado.group_by(Reserva.estado).order_by(
        func.count(Reserva.id_reserva).desc()
    ).all()

    q_suc = (
        db.query(Sucursal.nombre, func.count(Reserva.id_reserva))
        .join(Sucursal, Sucursal.id_sucursal == Reserva.sucursal_id)
    )
    if f.sucursal_id:
        q_suc = q_suc.filter(Reserva.sucursal_id == f.sucursal_id)
    if f.desde:
        q_suc = q_suc.filter(Reserva.fecha_reserva >= f.desde.date())
    if f.hasta:
        q_suc = q_suc.filter(Reserva.fecha_reserva <= f.hasta.date())
    por_sucursal = q_suc.group_by(Sucursal.nombre).order_by(
        func.count(Reserva.id_reserva).desc()
    ).all()

    _registrar_reporte(
        db, current, "reservas", request.client.host if request.client else None,
        f"desde={fecha_desde or '-'}, hasta={fecha_hasta or '-'}, sucursal={f.sucursal_id or '-'}",
    )
    return ReservasReporte(
        por_estado=[
            ReservaEstadoRow(estado=str(_valor_enum(r[0])), total=int(r[1]))
            for r in por_estado
        ],
        por_sucursal=[ReservaSucursalRow(sucursal=r[0], total=int(r[1])) for r in por_sucursal],
    )


@router.get(
    "/tendencias-temporada",
    response_model=list[TendenciaRow],
    summary="Tendencias de ventas por temporada (CU16)",
)
def reporte_tendencias(
    request: Request,
    fecha_desde: Optional[str] = Query(None, description="YYYY-MM-DD"),
    fecha_hasta: Optional[str] = Query(None, description="YYYY-MM-DD"),
    sucursal_id: Optional[int] = Query(None),
    categoria_id: Optional[int] = Query(None),
    temporada_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current: Usuario = Depends(encargado_required),
):
    """CU-16 · Montos vendidos agrupados por temporada de los productos."""
    f = _Filtros(current, fecha_desde, fecha_hasta, sucursal_id, categoria_id, temporada_id)
    q = (
        db.query(
            Temporada.nombre,
            func.coalesce(func.sum(PedidoItem.cantidad), 0),
            func.coalesce(func.sum(PedidoItem.subtotal), 0),
        )
        .select_from(PedidoItem)
        .join(Pedido, Pedido.id_pedido == PedidoItem.pedido_id)
        .join(ProductoVariante, ProductoVariante.id_variante == PedidoItem.variante_id)
        .join(Producto, Producto.id_producto == ProductoVariante.producto_id)
        .join(Temporada, Temporada.id_temporada == Producto.temporada_id)
    )
    q = _apply_pedido_filtros(db, q, f)
    rows = (
        q.group_by(Temporada.id_temporada, Temporada.nombre, Temporada.fecha_inicio)
        .order_by(Temporada.fecha_inicio)
        .all()
    )

    _registrar_reporte(
        db, current, "tendencias-temporada", request.client.host if request.client else None,
        f"desde={fecha_desde or '-'}, hasta={fecha_hasta or '-'}, sucursal={f.sucursal_id or '-'}",
    )
    return [
        TendenciaRow(temporada=r[0], unidades=int(r[1]), monto=float(r[2])) for r in rows
    ]