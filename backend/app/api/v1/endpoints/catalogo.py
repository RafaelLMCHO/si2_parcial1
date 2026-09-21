from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy.exc import IntegrityError, InternalError
from sqlalchemy.orm import Session, joinedload

from app.core.dependencies import admin_required, get_current_user_optional
from app.db.session import get_db
from app.models import (
    Categoria,
    Color,
    Coleccion,
    Inventario,
    Producto,
    ProductoVariante,
    Proveedor,
    Talla,
    Temporada,
    Usuario,
)
from app.models.enums import EstadoPedido, RolUsuario
from app.models.inventario import MovimientoInventario
from app.models.ventas import Pedido, PedidoItem
from app.schemas.comercio import (
    CategoriaOut,
    ColeccionOut,
    ColorOut,
    ProductoCreate,
    ProductoOut,
    ProductoUpdate,
    ProductoVarianteCreate,
    ProductoVarianteOut,
    ProveedorOut,
    TallaOut,
    TemporadaOut,
)

router = APIRouter()


_UPLOADS_DIR = Path(__file__).resolve().parents[4] / "static" / "uploads"
_MAX_IMAGEN_BYTES = 10 * 1024 * 1024
_EXT_POR_TIPO = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}


def _verificar_magic(contenido: bytes, content_type: str) -> bool:
    if content_type == "image/jpeg":
        return contenido[:3] == b"\xff\xd8\xff"
    if content_type == "image/png":
        return contenido[:8] == b"\x89PNG\r\n\x1a\n"
    if content_type == "image/webp":
        return (
            len(contenido) >= 12
            and contenido[:4] == b"RIFF"
            and contenido[8:12] == b"WEBP"
        )
    return False


def _maestro_o_404(db: Session, modelo, id_valor: int, nombre: str):
    if not db.get(modelo, id_valor):
        raise HTTPException(status_code=404, detail=f"{nombre} no encontrado/a")


def _producto_cargado(db: Session, producto_id: int, con_variantes: bool = True) -> Producto:
    query = db.query(Producto).options(
        joinedload(Producto.categoria),
        joinedload(Producto.temporada),
        joinedload(Producto.proveedor),
        joinedload(Producto.coleccion),
    )
    if con_variantes:
        query = query.options(
            joinedload(Producto.variantes).joinedload(ProductoVariante.color),
            joinedload(Producto.variantes).joinedload(ProductoVariante.talla),
        )
    producto = query.filter(Producto.id_producto == producto_id).first()
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return producto


def _tiene_operaciones_activas(db: Session, producto: Producto) -> bool:
    variantes_ids = [v.id_variante for v in producto.variantes]
    if not variantes_ids:
        return False
    tiene_movimientos = db.query(
        db.query(MovimientoInventario.id_movimiento)
        .filter(MovimientoInventario.variante_id.in_(variantes_ids))
        .exists()
    ).scalar()
    tiene_stock = db.query(
        db.query(Inventario.id_inventario)
        .filter(Inventario.variante_id.in_(variantes_ids))
        .exists()
    ).scalar()
    estados_activos = [e.value for e in EstadoPedido if e != EstadoPedido.cancelado]
    tiene_ventas = db.query(
        db.query(PedidoItem.id_pedido_item)
        .join(PedidoItem.pedido)
        .filter(
            PedidoItem.variante_id.in_(variantes_ids),
            Pedido.estado.in_(estados_activos),
        )
        .exists()
    ).scalar()
    return tiene_movimientos or tiene_stock or tiene_ventas


@router.get(
    "/categorias",
    response_model=list[CategoriaOut] | None,
    summary="Listar categorías",
)
def list_categorias(db: Session = Depends(get_db)):
    return db.query(Categoria).order_by(Categoria.nombre).all()


@router.get("/tallas", response_model=list[TallaOut] | None, summary="Listar tallas")
def list_tallas(db: Session = Depends(get_db)):
    return db.query(Talla).order_by(Talla.nombre).all()


@router.get("/colores", response_model=list[ColorOut] | None, summary="Listar colores")
def list_colores(db: Session = Depends(get_db)):
    return db.query(Color).order_by(Color.nombre).all()


@router.get(
    "/temporadas",
    response_model=list[TemporadaOut] | None,
    summary="Listar temporadas",
)
def list_temporadas(db: Session = Depends(get_db)):
    return db.query(Temporada).order_by(Temporada.nombre).all()


@router.get(
    "/colecciones",
    response_model=list[ColeccionOut] | None,
    summary="Listar colecciones",
)
def list_colecciones(db: Session = Depends(get_db)):
    return db.query(Coleccion).order_by(Coleccion.nombre).all()


@router.get(
    "/proveedores",
    response_model=list[ProveedorOut] | None,
    summary="Listar proveedores",
)
def list_proveedores(db: Session = Depends(get_db)):
    return db.query(Proveedor).order_by(Proveedor.nombre).all()


@router.get(
    "/productos",
    response_model=list[ProductoOut],
    summary="Filtrar/consultar catálogo (CU4, CU5, CU21)",
)
def list_productos(
    categoria_id: int | None = None,
    temporada_id: int | None = None,
    talla_id: int | None = None,
    color_id: int | None = None,
    proveedor_id: int | None = None,
    precio_min: float | None = None,
    precio_max: float | None = None,
    q: str | None = None,
    todas: bool = Query(
        default=False,
        description="Incluir productos inactivos (solo administrador)",
    ),
    usuario: Usuario | None = Depends(get_current_user_optional),
    db: Session = Depends(get_db),
):
    if todas and (usuario is None or usuario.rol != RolUsuario.admin):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No tiene permisos para realizar esta acción",
        )
    query = (
        db.query(Producto)
        .options(
            joinedload(Producto.categoria),
            joinedload(Producto.temporada),
            joinedload(Producto.proveedor),
            joinedload(Producto.coleccion),
            joinedload(Producto.variantes).joinedload(ProductoVariante.color),
            joinedload(Producto.variantes).joinedload(ProductoVariante.talla),
        )
    )
    if not todas:
        query = query.filter(Producto.activo == True)  # noqa: E712

    if categoria_id:
        query = query.filter(Producto.categoria_id == categoria_id)
    if temporada_id:
        query = query.filter(Producto.temporada_id == temporada_id)
    if proveedor_id:
        query = query.filter(Producto.proveedor_id == proveedor_id)
    if precio_min is not None:
        query = query.filter(Producto.precio >= precio_min)
    if precio_max is not None:
        query = query.filter(Producto.precio <= precio_max)
    if q:
        query = query.filter(Producto.nombre.ilike(f"%{q}%"))

    if talla_id or color_id:
        query = query.join(ProductoVariante).distinct()
        if talla_id:
            query = query.filter(ProductoVariante.talla_id == talla_id)
        if color_id:
            query = query.filter(ProductoVariante.color_id == color_id)

    return query.order_by(Producto.id_producto.desc()).all()


@router.get("/productos/{producto_id}", response_model=ProductoOut, summary="Detalle de producto")
def get_producto(
    producto_id: int,
    usuario: Usuario | None = Depends(get_current_user_optional),
    db: Session = Depends(get_db),
):
    producto = _producto_cargado(db, producto_id)
    # Un producto desactivado debe desaparecer del catálogo público, pero seguir
    # siendo consultable por el administrador desde el panel de gestión.
    if not producto.activo and (usuario is None or usuario.rol != RolUsuario.admin):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Producto no encontrado")
    return producto


@router.post(
    "/productos", response_model=ProductoOut, status_code=status.HTTP_201_CREATED,
    summary="Crear producto (administrador)",
)
def create_producto(
    data: ProductoCreate,
    db: Session = Depends(get_db),
    _: Usuario = Depends(admin_required),
):
    _maestro_o_404(db, Categoria, data.categoria_id, "Categoría")
    _maestro_o_404(db, Temporada, data.temporada_id, "Temporada")
    _maestro_o_404(db, Proveedor, data.proveedor_id, "Proveedor")
    if data.coleccion_id:
        _maestro_o_404(db, Coleccion, data.coleccion_id, "Colección")
    producto = Producto(**data.model_dump())
    db.add(producto)
    db.commit()
    return _producto_cargado(db, producto.id_producto)


@router.patch("/productos/{producto_id}", response_model=ProductoOut, summary="Actualizar producto")
def update_producto(
    producto_id: int,
    data: ProductoUpdate,
    db: Session = Depends(get_db),
    _: Usuario = Depends(admin_required),
    forzar: bool = Query(
        default=False,
        description="Desactivar aun con movimientos de inventario o ventas",
    ),
):
    producto = _producto_cargado(db, producto_id)
    cambios = data.model_dump(exclude_unset=True)
    if "categoria_id" in cambios and cambios["categoria_id"]:
        _maestro_o_404(db, Categoria, cambios["categoria_id"], "Categoría")
    if "temporada_id" in cambios and cambios["temporada_id"]:
        _maestro_o_404(db, Temporada, cambios["temporada_id"], "Temporada")
    if "proveedor_id" in cambios and cambios["proveedor_id"]:
        _maestro_o_404(db, Proveedor, cambios["proveedor_id"], "Proveedor")
    if cambios.get("coleccion_id"):
        _maestro_o_404(db, Coleccion, cambios["coleccion_id"], "Colección")

    if cambios.get("activo") is False and not forzar:
        if _tiene_operaciones_activas(db, producto):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    "Este producto tiene operaciones activas (movimientos de "
                    "inventario o ventas). Envíe forzar=true si desea "
                    "desactivarlo de todos modos."
                ),
            )

    for field, value in cambios.items():
        setattr(producto, field, value)
    db.commit()
    return _producto_cargado(db, producto.id_producto)


@router.post(
    "/productos/{producto_id}/imagen",
    response_model=ProductoOut,
    summary="Subir imagen real del producto (admin)",
)
def subir_imagen_producto(
    producto_id: int,
    archivo: UploadFile = File(...),
    db: Session = Depends(get_db),
    _: Usuario = Depends(admin_required),
):
    producto = _producto_cargado(db, producto_id)

    content_type = (archivo.content_type or "").lower()
    if content_type not in _EXT_POR_TIPO:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Formato no permitido. Usa JPG, PNG o WebP.",
        )

    contenido = bytearray()
    while True:
        chunk = archivo.file.read(1 << 16)
        if not chunk:
            break
        contenido.extend(chunk)
        if len(contenido) > _MAX_IMAGEN_BYTES:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f"La imagen supera el límite de {_MAX_IMAGEN_BYTES // (1024 * 1024)} MB.",
            )

    if not _verificar_magic(bytes(contenido), content_type):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El archivo no es una imagen válida.",
        )

    _UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
    for previo in _UPLOADS_DIR.glob(f"producto_{producto_id}.*"):
        previo.unlink(missing_ok=True)
    destino = _UPLOADS_DIR / f"producto_{producto_id}{_EXT_POR_TIPO[content_type]}"
    destino.write_bytes(bytes(contenido))

    producto.imagen_url = f"/static/uploads/{destino.name}"
    db.commit()
    return _producto_cargado(db, producto.id_producto)


@router.post(
    "/productos/variantes", response_model=ProductoVarianteOut,
    status_code=status.HTTP_201_CREATED, summary="Agregar variante a producto",
)
def create_variante(
    data: ProductoVarianteCreate,
    db: Session = Depends(get_db),
    _: Usuario = Depends(admin_required),
):
    _producto_cargado(db, data.producto_id, con_variantes=False)
    _maestro_o_404(db, Color, data.color_id, "Color")
    _maestro_o_404(db, Talla, data.talla_id, "Talla")
    sku = (
        (data.sku or "").strip()
        or f"P{data.producto_id:04d}-C{data.color_id:02d}-T{data.talla_id:02d}"
    )
    variante = ProductoVariante(
        producto_id=data.producto_id,
        color_id=data.color_id,
        talla_id=data.talla_id,
        sku=sku,
        precio_extra=data.precio_extra,
    )
    try:
        db.add(variante)
        db.commit()
    except (IntegrityError, InternalError):
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El SKU o la combinación de color/talla ya existe",
        )
    db.refresh(variante)
    return variante


@router.delete(
    "/productos/variantes/{variante_id}",
    status_code=status.HTTP_200_OK,
    summary="Eliminar variante de un producto",
)
def delete_variante(
    variante_id: int,
    db: Session = Depends(get_db),
    _: Usuario = Depends(admin_required),
):
    variante = db.get(ProductoVariante, variante_id)
    if not variante:
        raise HTTPException(status_code=404, detail="Variante no encontrada")
    tiene_inventario = db.query(
        db.query(MovimientoInventario.id_movimiento)
        .filter(MovimientoInventario.variante_id == variante_id)
        .exists()
    ).scalar()
    if tiene_inventario:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No se puede eliminar la variante: tiene inventario o movimientos asociados",
        )
    db.delete(variante)
    db.commit()
    return {"ok": True, "eliminado": variante_id}
