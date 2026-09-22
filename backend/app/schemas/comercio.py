from datetime import date, datetime, time
from pydantic import BaseModel, ConfigDict, EmailStr, Field, model_validator

from app.models.enums import (
    EstadoReserva,
    EstadoPedido,
    MetodoCompra,
    TipoMovimiento,
    TipoPago,
)
from app.schemas.usuario import UsuarioOut

# ============================================================
# Ubicación
# ============================================================

class CiudadOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_ciudad: int
    nombre: str


class SucursalBase(BaseModel):
    ciudad_id: int
    nombre: str = Field(min_length=2, max_length=150)
    direccion: str = Field(min_length=3, max_length=255)
    telefono: str | None = None


class SucursalCreate(SucursalBase):
    horario_apertura: time
    horario_cierre: time

    @model_validator(mode="after")
    def validar_horario(self):
        if self.horario_apertura >= self.horario_cierre:
            raise ValueError("El horario de apertura debe ser anterior al horario de cierre")
        return self


class SucursalUpdate(BaseModel):
    ciudad_id: int | None = None
    nombre: str | None = Field(default=None, min_length=2, max_length=150)
    direccion: str | None = Field(default=None, min_length=3, max_length=255)
    telefono: str | None = None
    horario_apertura: time | None = None
    horario_cierre: time | None = None
    activo: bool | None = None

    @model_validator(mode="after")
    def validar_horario(self):
        if (
            self.horario_apertura is not None
            and self.horario_cierre is not None
            and self.horario_apertura >= self.horario_cierre
        ):
            raise ValueError(
                "El horario de apertura debe ser anterior al horario de cierre"
            )
        return self


class SucursalOut(SucursalBase):
    model_config = ConfigDict(from_attributes=True)
    id_sucursal: int
    horario_apertura: time
    horario_cierre: time
    activo: bool
    ciudad: CiudadOut | None = None


# ============================================================
# Catálogo
# ============================================================

class CategoriaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_categoria: int
    nombre: str
    descripcion: str | None


class ColorOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_color: int
    nombre: str
    codigo_hex: str


class TallaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_talla: int
    nombre: str


class TemporadaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_temporada: int
    nombre: str
    fecha_inicio: date
    fecha_fin: date


class TemporadaCreate(BaseModel):
    nombre: str = Field(min_length=2, max_length=100)
    fecha_inicio: date
    fecha_fin: date

    @model_validator(mode="after")
    def validar_fechas(self):
        if self.fecha_inicio >= self.fecha_fin:
            raise ValueError("fecha_inicio debe ser anterior a fecha_fin")
        return self


class TemporadaUpdate(BaseModel):
    nombre: str | None = Field(default=None, min_length=2, max_length=100)
    fecha_inicio: date | None = None
    fecha_fin: date | None = None

    @model_validator(mode="after")
    def validar_fechas(self):
        if (
            self.fecha_inicio is not None
            and self.fecha_fin is not None
            and self.fecha_inicio >= self.fecha_fin
        ):
            raise ValueError("fecha_inicio debe ser anterior a fecha_fin")
        return self


class ColeccionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_coleccion: int
    temporada_id: int
    nombre: str
    descripcion: str | None
    es_promocional: bool


class ColeccionCreate(BaseModel):
    temporada_id: int
    nombre: str = Field(min_length=2, max_length=100)
    descripcion: str | None = Field(default=None, max_length=255)
    es_promocional: bool = False


class ColeccionUpdate(BaseModel):
    temporada_id: int | None = None
    nombre: str | None = Field(default=None, min_length=2, max_length=100)
    descripcion: str | None = Field(default=None, max_length=255)
    es_promocional: bool | None = None


class ProveedorBase(BaseModel):
    nombre: str = Field(min_length=2, max_length=150)
    contacto: str | None = Field(default=None, max_length=150)
    telefono: str | None = Field(default=None, max_length=30)
    email: EmailStr | None = Field(default=None, max_length=150)
    direccion: str | None = Field(default=None, max_length=255)


class ProveedorCreate(ProveedorBase):
    pass


class ProveedorUpdate(BaseModel):
    nombre: str | None = Field(default=None, min_length=2, max_length=150)
    contacto: str | None = Field(default=None, max_length=150)
    telefono: str | None = Field(default=None, max_length=30)
    email: str | None = Field(default=None, max_length=150)
    direccion: str | None = Field(default=None, max_length=255)


class ProveedorOut(ProveedorBase):
    model_config = ConfigDict(from_attributes=True)
    id_proveedor: int


class ProductoBase(BaseModel):
    nombre: str = Field(min_length=2, max_length=150)
    descripcion: str | None = None
    precio: float = Field(gt=0)
    categoria_id: int
    temporada_id: int
    coleccion_id: int | None = None
    proveedor_id: int
    imagen_url: str | None = None
    modelo_3d_url: str | None = None


class ProductoCreate(ProductoBase):
    pass


class ProductoUpdate(BaseModel):
    nombre: str | None = None
    descripcion: str | None = None
    precio: float | None = Field(default=None, gt=0)
    categoria_id: int | None = None
    temporada_id: int | None = None
    coleccion_id: int | None = None
    proveedor_id: int | None = None
    imagen_url: str | None = None
    modelo_3d_url: str | None = None
    activo: bool | None = None


class ProductoVarianteCreate(BaseModel):
    producto_id: int
    color_id: int
    talla_id: int
    sku: str | None = Field(default=None, max_length=50)
    precio_extra: float = 0


class ProductoVarianteOut(ProductoVarianteCreate):
    model_config = ConfigDict(from_attributes=True)
    id_variante: int
    color: ColorOut | None = None
    talla: TallaOut | None = None


class ProductoOut(ProductoBase):
    model_config = ConfigDict(from_attributes=True)
    id_producto: int
    activo: bool
    categoria: CategoriaOut | None = None
    temporada: TemporadaOut | None = None
    proveedor: ProveedorOut | None = None
    coleccion: ColeccionOut | None = None
    variantes: list[ProductoVarianteOut] = []


# ============================================================
# Inventario
# ============================================================

class InventarioOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_inventario: int
    variante_id: int
    sucursal_id: int
    cantidad_disponible: int
    cantidad_reservada: int
    cantidad_recibida: int
    stock_minimo: int


class InventarioUpdate(BaseModel):
    stock_minimo: int | None = Field(default=None, ge=0)


class TransferenciaInventarioCreate(BaseModel):
    variante_id: int
    sucursal_origen_id: int
    sucursal_destino_id: int
    cantidad: int = Field(ge=1)
    observacion: str | None = Field(default=None, max_length=255)


class InventarioGlobalOut(BaseModel):
    id_inventario: int
    variante_id: int
    sucursal_id: int
    sucursal_nombre: str
    producto_nombre: str
    sku: str | None
    talla: str | None
    color: str | None
    precio: float
    cantidad_disponible: int
    cantidad_reservada: int
    cantidad_recibida: int
    stock_minimo: int
    stock_bajo: bool
    imagen_url: str | None = None



class MovimientoInventarioCreate(BaseModel):
    variante_id: int
    sucursal_id: int
    tipo_movimiento: TipoMovimiento
    cantidad: int = Field(ge=1)
    referencia_id: int | None = None
    observacion: str | None = Field(default=None, max_length=255)


class MovimientoInventarioOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_movimiento: int
    variante_id: int
    sucursal_id: int
    tipo_movimiento: TipoMovimiento
    cantidad: int
    referencia_id: int | None
    observacion: str | None
    fecha_movimiento: datetime
    variante: ProductoVarianteOut | None = None
    sucursal: SucursalOut | None = None


class SucursalDisponibilidadOut(BaseModel):
    variante_id: int
    sucursal_id: int
    nombre_sucursal: str
    ciudad: str
    cantidad_disponible: int
    cantidad_reservada: int
    cantidad_recibida: int
    stock_minimo: int
    estado: str


# ============================================================
# Reservas
# ============================================================

class ReservaItemCreate(BaseModel):
    variante_id: int
    cantidad: int = Field(ge=1)


class ReservaCreate(BaseModel):
    sucursal_id: int
    fecha_reserva: date
    hora_atencion: str
    items: list[ReservaItemCreate]


class ReservaItemOut(ReservaItemCreate):
    model_config = ConfigDict(from_attributes=True)
    id_reserva_item: int
    variante_id: int
    variante: ProductoVarianteOut | None = None
    producto: ProductoOut | None = None


class ReservaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_reserva: int
    usuario_id: int
    sucursal_id: int
    fecha_reserva: date
    hora_atencion: object
    estado: EstadoReserva
    fecha_creacion: datetime
    usuario: UsuarioOut | None = None
    sucursal: SucursalOut | None = None
    items: list[ReservaItemOut] = []


# ============================================================
# Pedidos y Pagos
# ============================================================

class PedidoItemCreate(BaseModel):
    variante_id: int
    cantidad: int = Field(ge=1)


class VentaPresencialCreate(BaseModel):
    sucursal_id: int
    tipo_pago: TipoPago
    items: list[PedidoItemCreate]


class CarritoItem(BaseModel):
    variante_id: int
    cantidad: int = Field(ge=1)


class VentaDigitalCreate(BaseModel):
    items: list[CarritoItem] = []
    sucursal_id: int | None = 1
    pasarela: str = "stripe"
    payment_intent_id: str | None = None
    session_id: str | None = None
    return_url: str | None = None


class PedidoItemOut(PedidoItemCreate):
    model_config = ConfigDict(from_attributes=True)
    id_pedido_item: int
    precio_unitario: float
    subtotal: float


class PedidoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_pedido: int
    usuario_id: int
    sucursal_id: int | None
    fecha_pedido: datetime
    total: float
    metodo_compra: MetodoCompra
    estado: EstadoPedido
    tipo_pago: TipoPago | None
    items: list[PedidoItemOut] = []
