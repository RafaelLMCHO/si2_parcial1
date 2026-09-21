from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class BitacoraCreate(BaseModel):
    usuario_id: Optional[int] = Field(default=None, description="ID del usuario que originó el evento")
    accion: str = Field(..., min_length=1, max_length=80, description="Acción registrada (login, logout, CRUD, venta, reserva, pago)")
    entidad: Optional[str] = Field(default=None, max_length=60, description="Entidad afectada (Usuario, Producto, Pedido, etc.)")
    entidad_id: Optional[int] = Field(default=None, description="ID del registro de la entidad afectada")
    detalle: Optional[str] = Field(default=None, description="Detalle legible del evento")
    ip_origen: Optional[str] = Field(default=None, max_length=45, description="Dirección IP de origen (auditoría)")


class BitacoraOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id_bitacora: int
    usuario_id: Optional[int] = None
    accion: str
    entidad: Optional[str] = None
    entidad_id: Optional[int] = None
    detalle: Optional[str] = None
    ip_origen: Optional[str] = None
    fecha: datetime
    usuario_nombre: Optional[str] = None
