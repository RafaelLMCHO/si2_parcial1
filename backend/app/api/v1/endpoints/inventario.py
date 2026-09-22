from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session, joinedload

from app.core.dependencies import (
    encargado_required,
    get_current_user,
    get_db,
)
from app.models import (
    Inventario,
    MovimientoInventario,
    Producto,
    ProductoVariante,
    Sucursal,
    TipoMovimiento,
    Usuario,
)
from app.schemas.comercio import (
    InventarioGlobalOut,
    InventarioOut,
    InventarioUpdate,
    MovimientoInventarioCreate,
    MovimientoInventarioOut,
    SucursalDisponibilidadOut,
    TransferenciaInventarioCreate,
)

router = APIRouter()


def _inventario_o_404(db: Session, variante_id: int, sucursal_id: int) -> Inventario:
    registro = (
        db.query(Inventario)
        .filter(
            Inventario.variante_id == variante_id,
            Inventario.sucursal_id == sucursal_id,
        )
        .first()
    )
    if not registro:
        # Si no existe registro de inventario, crearlo con 0 unidades por defecto
        registro = Inventario(
            variante_id=variante_id,
            sucursal_id=sucursal_id,
            cantidad_disponible=0,
            cantidad_reservada=0,
            cantidad_recibida=0,
            stock_minimo=5,
        )
        db.add(registro)
        db.flush()
    return registro


def _aplicar_movimiento(registro: Inventario, data: MovimientoInventarioCreate):
    if data.tipo_movimiento == TipoMovimiento.entrada:
        registro.cantidad_disponible += data.cantidad
        registro.cantidad_recibida += data.cantidad
    elif data.tipo_movimiento == TipoMovimiento.salida:
        if registro.cantidad_disponible < data.cantidad:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Stock insuficiente para realizar la salida (Disponible: {registro.cantidad_disponible}, Solicitado: {data.cantidad})",
            )
        registro.cantidad_disponible -= data.cantidad
    elif data.tipo_movimiento == TipoMovimiento.ajuste:
        registro.cantidad_disponible = data.cantidad


@router.get(
    "/global",
    response_model=list[InventarioGlobalOut],
    summary="Listado consolidado de inventario global y local (CU13)",
)
def inventario_global(
    sucursal_id: int | None = None,
    categoria_id: int | None = None,
    q: str | None = None,
    stock_bajo_solo: bool = False,
    db: Session = Depends(get_db),
    user: Usuario = Depends(get_current_user),
):
    query = db.query(Inventario).options(
        joinedload(Inventario.sucursal),
        joinedload(Inventario.variante).joinedload(ProductoVariante.producto),
        joinedload(Inventario.variante).joinedload(ProductoVariante.talla),
        joinedload(Inventario.variante).joinedload(ProductoVariante.color),
    )

    if sucursal_id:
        query = query.filter(Inventario.sucursal_id == sucursal_id)
    elif user.rol == "encargado" and user.sucursal_id:
        query = query.filter(Inventario.sucursal_id == user.sucursal_id)

    if categoria_id:
        query = query.join(ProductoVariante).join(Producto).filter(Producto.categoria_id == categoria_id)

    if q:
        query = query.join(ProductoVariante).join(Producto).filter(
            (Producto.nombre.ilike(f"%{q}%")) | (ProductoVariante.sku.ilike(f"%{q}%"))
        )

    registros = query.all()

    res = []
    for r in registros:
        v = r.variante
        p = v.producto if v else None
        stock_bajo = r.cantidad_disponible <= r.stock_minimo

        if stock_bajo_solo and not stock_bajo:
            continue

        precio_final = (p.precio + (v.precio_extra or 0)) if p else 0.0

        res.append({
            "id_inventario": r.id_inventario,
            "variante_id": r.variante_id,
            "sucursal_id": r.sucursal_id,
            "sucursal_nombre": r.sucursal.nombre if r.sucursal else f"Sucursal #{r.sucursal_id}",
            "producto_nombre": p.nombre if p else f"Variante #{r.variante_id}",
            "sku": v.sku if v else None,
            "talla": v.talla.nombre if v and v.talla else None,
            "color": v.color.nombre if v and v.color else None,
            "precio": float(precio_final),
            "cantidad_disponible": r.cantidad_disponible,
            "cantidad_reservada": r.cantidad_reservada,
            "cantidad_recibida": r.cantidad_recibida,
            "stock_minimo": r.stock_minimo,
            "stock_bajo": stock_bajo,
            "imagen_url": p.imagen_url if p else None,
        })

    return res


@router.get(
    "/disponibilidad",
    response_model=list[SucursalDisponibilidadOut],
    summary="Consultar disponibilidad de una variante por sucursal (CU6, RF08)",
)
def disponibilidad(
    variante_id: int,
    sucursal_id: int | None = None,
    ciudad_id: int | None = None,
    db: Session = Depends(get_db),
    user: Usuario = Depends(get_current_user),
):
    consulta = (
        db.query(Inventario)
        .join(Sucursal, Inventario.sucursal_id == Sucursal.id_sucursal)
        .filter(Inventario.variante_id == variante_id)
        .filter(Sucursal.activo == True)
    )
    if sucursal_id:
        consulta = consulta.filter(Inventario.sucursal_id == sucursal_id)
    if ciudad_id:
        consulta = consulta.filter(Sucursal.ciudad_id == ciudad_id)
    registros = consulta.all()

    return [
        {
            "variante_id": r.variante_id,
            "sucursal_id": r.sucursal_id,
            "nombre_sucursal": r.sucursal.nombre,
            "ciudad": r.sucursal.ciudad.nombre,
            "cantidad_disponible": r.cantidad_disponible,
            "cantidad_reservada": r.cantidad_reservada,
            "cantidad_recibida": r.cantidad_recibida,
            "stock_minimo": r.stock_minimo,
            "estado": (
                "Disponible"
                if r.cantidad_disponible > 0
                else (
                    "Reservada"
                    if r.cantidad_reservada > 0
                    else (
                        "Proxima a ingresar"
                        if r.cantidad_recibida > 0
                        else "Agotada"
                    )
                )
            ),
        }
        for r in registros
    ]


@router.post(
    "/movimientos",
    response_model=InventarioOut,
    status_code=status.HTTP_201_CREATED,
    summary="Registrar movimiento de inventario (CU13, RF10/RF11/RF12): entrada, salida o ajuste",
)
def crear_movimiento(
    data: MovimientoInventarioCreate,
    db: Session = Depends(get_db),
    _: Usuario = Depends(encargado_required),
):
    registro = _inventario_o_404(db, data.variante_id, data.sucursal_id)
    _aplicar_movimiento(registro, data)
    db.add(
        MovimientoInventario(
            variante_id=data.variante_id,
            sucursal_id=data.sucursal_id,
            tipo_movimiento=data.tipo_movimiento,
            cantidad=data.cantidad,
            observacion=data.observacion,
        )
    )
    db.commit()
    db.refresh(registro)
    return registro


@router.post(
    "/transferir",
    summary="Transferir inventario entre sucursales (CU13)",
)
def transferir_inventario(
    data: TransferenciaInventarioCreate,
    db: Session = Depends(get_db),
    _: Usuario = Depends(encargado_required),
):
    if data.sucursal_origen_id == data.sucursal_destino_id:
        raise HTTPException(status_code=400, detail="La sucursal de origen y destino no pueden ser la misma")

    origen = _inventario_o_404(db, data.variante_id, data.sucursal_origen_id)
    destino = _inventario_o_404(db, data.variante_id, data.sucursal_destino_id)

    if origen.cantidad_disponible < data.cantidad:
        raise HTTPException(
            status_code=400,
            detail=f"Stock insuficiente en origen (Disponible: {origen.cantidad_disponible}, Requerido: {data.cantidad})",
        )

    # Descontar de origen
    origen.cantidad_disponible -= data.cantidad
    db.add(
        MovimientoInventario(
            variante_id=data.variante_id,
            sucursal_id=data.sucursal_origen_id,
            tipo_movimiento=TipoMovimiento.salida,
            cantidad=data.cantidad,
            observacion=f"Transferencia a Sucursal #{data.sucursal_destino_id}. {data.observacion or ''}",
        )
    )

    # Incrementar en destino
    destino.cantidad_disponible += data.cantidad
    destino.cantidad_recibida += data.cantidad
    db.add(
        MovimientoInventario(
            variante_id=data.variante_id,
            sucursal_id=data.sucursal_destino_id,
            tipo_movimiento=TipoMovimiento.entrada,
            cantidad=data.cantidad,
            observacion=f"Transferencia desde Sucursal #{data.sucursal_origen_id}. {data.observacion or ''}",
        )
    )

    db.commit()
    return {"status": "ok", "mensaje": f"Transferencia de {data.cantidad} unidad(es) realizada con éxito."}


@router.get(
    "/movimientos",
    response_model=list[MovimientoInventarioOut],
    summary="Historial de movimientos de inventario (CU13, RF30)",
)
def list_movimientos(
    variante_id: int | None = None,
    sucursal_id: int | None = None,
    db: Session = Depends(get_db),
    _: Usuario = Depends(encargado_required),
):
    query = db.query(MovimientoInventario)
    if variante_id:
        query = query.filter(MovimientoInventario.variante_id == variante_id)
    if sucursal_id:
        query = query.filter(MovimientoInventario.sucursal_id == sucursal_id)
    return query.order_by(MovimientoInventario.fecha_movimiento.desc()).all()


@router.patch(
    "/movimientos/{id_inventario}",
    response_model=InventarioOut,
    summary="Actualizar inventario (stock mínimo)",
)
def update_inventario(
    id_inventario: int,
    data: InventarioUpdate,
    db: Session = Depends(get_db),
    _: Usuario = Depends(encargado_required),
):
    registro = db.get(Inventario, id_inventario)
    if not registro:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Registro de inventario no encontrado",
        )
    cambios = data.model_dump(exclude_unset=True)
    for campo, valor in cambios.items():
        setattr(registro, campo, valor)
    db.commit()
    db.refresh(registro)
    return registro


@router.get(
    "/",
    response_model=list[InventarioOut],
    summary="Listar inventario (filtro por sucursal)",
)
def list_inventario(
    sucursal_id: int | None = None,
    variante_id: int | None = None,
    db: Session = Depends(get_db),
):
    query = db.query(Inventario)
    if sucursal_id:
        query = query.filter(Inventario.sucursal_id == sucursal_id)
    if variante_id:
        query = query.filter(Inventario.variante_id == variante_id)
    return query.all()
