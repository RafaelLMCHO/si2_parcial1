from pydantic import BaseModel, Field


class ProductoRank(BaseModel):
    producto: str
    categoria: str = ""
    unidades: int = 0
    monto: float = 0.0


class ResumenReporte(BaseModel):
    ventas_total: float = 0.0
    total_pedidos: int = 0
    total_productos: int = 0
    stock_critico: int = 0
    reservas_activas: int = 0
    top_productos: list[ProductoRank] = Field(default_factory=list)


class VentaSucursalRow(BaseModel):
    sucursal_id: int | None = None
    sucursal: str
    total: float = 0.0


class MasVendidoRow(ProductoRank):
    pass


class RotacionRow(BaseModel):
    producto: str
    unidades_vendidas: int = 0
    stock_actual: int = 0
    rotacion: float = 0.0


class StockCriticoRow(BaseModel):
    producto: str
    talla: str
    color: str
    sku: str
    sucursal: str
    stock_minimo: int = 0
    disponible: int = 0
    faltante: int = 0


class ReservaEstadoRow(BaseModel):
    estado: str
    total: int = 0


class ReservaSucursalRow(BaseModel):
    sucursal: str
    total: int = 0


class ReservasReporte(BaseModel):
    por_estado: list[ReservaEstadoRow] = Field(default_factory=list)
    por_sucursal: list[ReservaSucursalRow] = Field(default_factory=list)


class TendenciaRow(BaseModel):
    temporada: str
    unidades: int = 0
    monto: float = 0.0