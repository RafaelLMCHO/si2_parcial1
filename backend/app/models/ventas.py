from datetime import datetime, date, time
from typing import Optional

from sqlalchemy import (
    Integer,
    Date,
    Time,
    DateTime,
    ForeignKey,
    Numeric,
    String,
    Enum as SAEnum,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.enums import (
    EstadoReserva,
    EstadoPedido,
    MetodoCompra,
    TipoPago,
    EstadoPago,
)


class Reserva(Base):
    __tablename__ = "reservas"

    id_reserva: Mapped[int] = mapped_column(Integer, primary_key=True)
    usuario_id: Mapped[int] = mapped_column(
        ForeignKey("usuarios.id_usuario"), nullable=False
    )
    sucursal_id: Mapped[int] = mapped_column(
        ForeignKey("sucursales.id_sucursal"), nullable=False
    )
    fecha_reserva: Mapped[date] = mapped_column(Date, nullable=False)
    hora_atencion: Mapped[time] = mapped_column(Time, nullable=False)
    estado: Mapped[EstadoReserva] = mapped_column(
        SAEnum(
            EstadoReserva,
            name="estado_reserva",
            native_enum=True,
            values_callable=lambda x: [e.value for e in x],
        ),
        nullable=False,
        default=EstadoReserva.pendiente,
    )
    fecha_creacion: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, server_default=func.now()
    )

    usuario: Mapped["Usuario"] = relationship(back_populates="reservas")
    sucursal: Mapped["Sucursal"] = relationship()
    items: Mapped[list["ReservaItem"]] = relationship(
        back_populates="reserva", cascade="all, delete-orphan"
    )


class ReservaItem(Base):
    __tablename__ = "reserva_items"

    id_reserva_item: Mapped[int] = mapped_column(Integer, primary_key=True)
    reserva_id: Mapped[int] = mapped_column(
        ForeignKey("reservas.id_reserva"), nullable=False
    )
    variante_id: Mapped[int] = mapped_column(
        ForeignKey("producto_variantes.id_variante"), nullable=False
    )
    cantidad: Mapped[int] = mapped_column(Integer, nullable=False)

    reserva: Mapped["Reserva"] = relationship(back_populates="items")
    variante: Mapped["ProductoVariante"] = relationship()

    @property
    def producto(self) -> Optional["Producto"]:
        return self.variante.producto if self.variante else None


class Pedido(Base):
    __tablename__ = "pedidos"

    id_pedido: Mapped[int] = mapped_column(Integer, primary_key=True)
    usuario_id: Mapped[int] = mapped_column(
        ForeignKey("usuarios.id_usuario"), nullable=False
    )
    sucursal_id: Mapped[int | None] = mapped_column(
        ForeignKey("sucursales.id_sucursal"), nullable=True
    )
    fecha_pedido: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, server_default=func.now()
    )
    total: Mapped[object] = mapped_column(Numeric(10, 2), nullable=False)
    metodo_compra: Mapped[MetodoCompra] = mapped_column(
        SAEnum(
            MetodoCompra,
            name="metodo_compra",
            native_enum=True,
            values_callable=lambda x: [e.value for e in x],
        ),
        nullable=False,
    )
    estado: Mapped[EstadoPedido] = mapped_column(
        SAEnum(
            EstadoPedido,
            name="estado_pedido",
            native_enum=True,
            values_callable=lambda x: [e.value for e in x],
        ),
        nullable=False,
        default=EstadoPedido.pendiente,
    )
    tipo_pago: Mapped[TipoPago | None] = mapped_column(
        SAEnum(
            TipoPago,
            name="tipo_pago",
            native_enum=True,
            values_callable=lambda x: [e.value for e in x],
            validate_strings=True,
        ),
        nullable=True,
    )

    usuario: Mapped["Usuario"] = relationship(back_populates="pedidos")
    sucursal: Mapped["Sucursal"] = relationship()
    items: Mapped[list["PedidoItem"]] = relationship(
        back_populates="pedido", cascade="all, delete-orphan"
    )
    pagos: Mapped[list["Pago"]] = relationship(back_populates="pedido")


class PedidoItem(Base):
    __tablename__ = "pedido_items"

    id_pedido_item: Mapped[int] = mapped_column(Integer, primary_key=True)
    pedido_id: Mapped[int] = mapped_column(
        ForeignKey("pedidos.id_pedido"), nullable=False
    )
    variante_id: Mapped[int] = mapped_column(
        ForeignKey("producto_variantes.id_variante"), nullable=False
    )
    cantidad: Mapped[int] = mapped_column(Integer, nullable=False)
    precio_unitario: Mapped[object] = mapped_column(Numeric(10, 2), nullable=False)
    subtotal: Mapped[object] = mapped_column(Numeric(10, 2), nullable=False)

    pedido: Mapped["Pedido"] = relationship(back_populates="items")
    variante: Mapped["ProductoVariante"] = relationship()


class Pago(Base):
    __tablename__ = "pagos"

    id_pago: Mapped[int] = mapped_column(Integer, primary_key=True)
    pedido_id: Mapped[int] = mapped_column(
        ForeignKey("pedidos.id_pedido"), nullable=False
    )
    monto: Mapped[object] = mapped_column(Numeric(10, 2), nullable=False)
    proveedor_pago: Mapped[str] = mapped_column(String(50), nullable=False)
    transaccion_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    estado: Mapped[EstadoPago] = mapped_column(
        SAEnum(
            EstadoPago,
            name="estado_pago",
            native_enum=True,
            values_callable=lambda x: [e.value for e in x],
        ),
        nullable=False,
    )
    fecha_pago: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, server_default=func.now()
    )
    datos_gateway: Mapped[dict | None] = mapped_column(JSONB, nullable=True)

    pedido: Mapped["Pedido"] = relationship(back_populates="pagos")


class CheckoutPendiente(Base):
    """Carrito de una compra digital esperando el retorno de Stripe Checkout.

    Se crea al generar la Checkout Session y se elimina cuando la compra se
    confirma (o se vence/quedan obsoletas por un pagador que no regresó).
    """

    __tablename__ = "checkout_pendiente"

    session_id: Mapped[str] = mapped_column(String(255), primary_key=True)
    usuario_id: Mapped[int] = mapped_column(
        ForeignKey("usuarios.id_usuario"), nullable=False
    )
    sucursal_id: Mapped[int] = mapped_column(Integer, nullable=False)
    items: Mapped[list] = mapped_column(JSONB, nullable=False)
    monto: Mapped[object] = mapped_column(Numeric(10, 2), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, server_default=func.now()
    )
