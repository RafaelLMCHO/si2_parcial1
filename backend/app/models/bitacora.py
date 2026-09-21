from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


class Bitacora(Base):
    """CU-23 · Registrar bitácora.

    Tabla transversal de auditoría: cada evento relevante del sistema
    (login, logout, CRUD, ventas, reservas, pagos, cambios de estado)
    queda trazado con usuario, acción, entidad afectada, fecha e IP.
    """

    __tablename__ = "bitacoras"

    id_bitacora: Mapped[int] = mapped_column(
        Integer, primary_key=True, autoincrement=True
    )
    usuario_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("usuarios.id_usuario"), nullable=True, index=True
    )
    accion: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    entidad: Mapped[Optional[str]] = mapped_column(String(60), nullable=True)
    entidad_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    detalle: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    ip_origen: Mapped[Optional[str]] = mapped_column(String(45), nullable=True)
    fecha: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=datetime.utcnow, index=True
    )

    usuario: Mapped[Optional["Usuario"]] = relationship(
        foreign_keys=[usuario_id]
    )
