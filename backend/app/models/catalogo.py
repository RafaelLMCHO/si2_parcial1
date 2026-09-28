from sqlalchemy import Integer, String, Text, Boolean, Numeric, ForeignKey, UniqueConstraint, Date
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


class Categoria(Base):
    __tablename__ = "categorias"

    id_categoria: Mapped[int] = mapped_column(Integer, primary_key=True)
    nombre: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    descripcion: Mapped[str | None] = mapped_column(Text, nullable=True)

    productos: Mapped[list["Producto"]] = relationship(
        back_populates="categoria"
    )


class Color(Base):
    __tablename__ = "colores"

    id_color: Mapped[int] = mapped_column(Integer, primary_key=True)
    nombre: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)
    codigo_hex: Mapped[str] = mapped_column(String(7), nullable=False)

    variantes: Mapped[list["ProductoVariante"]] = relationship(
        back_populates="color"
    )


class Talla(Base):
    __tablename__ = "tallas"

    id_talla: Mapped[int] = mapped_column(Integer, primary_key=True)
    nombre: Mapped[str] = mapped_column(String(10), unique=True, nullable=False)

    variantes: Mapped[list["ProductoVariante"]] = relationship(
        back_populates="talla"
    )


class Temporada(Base):
    __tablename__ = "temporadas"

    id_temporada: Mapped[int] = mapped_column(Integer, primary_key=True)
    nombre: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    fecha_inicio: Mapped[Date] = mapped_column(Date, nullable=False)
    fecha_fin: Mapped[Date] = mapped_column(Date, nullable=False)

    colecciones: Mapped[list["Coleccion"]] = relationship(
        back_populates="temporada"
    )
    productos: Mapped[list["Producto"]] = relationship(
        back_populates="temporada"
    )


class Coleccion(Base):
    __tablename__ = "colecciones"

    id_coleccion: Mapped[int] = mapped_column(Integer, primary_key=True)
    temporada_id: Mapped[int] = mapped_column(
        ForeignKey("temporadas.id_temporada"), nullable=False
    )
    nombre: Mapped[str] = mapped_column(String(150), unique=True, nullable=False)
    descripcion: Mapped[str | None] = mapped_column(Text, nullable=True)
    es_promocional: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )

    temporada: Mapped["Temporada"] = relationship(back_populates="colecciones")
    productos: Mapped[list["Producto"]] = relationship(
        back_populates="coleccion"
    )


class Proveedor(Base):
    __tablename__ = "proveedores"

    id_proveedor: Mapped[int] = mapped_column(Integer, primary_key=True)
    nombre: Mapped[str] = mapped_column(String(150), unique=True, nullable=False)
    contacto: Mapped[str | None] = mapped_column(String(100), nullable=True)
    telefono: Mapped[str | None] = mapped_column(String(20), nullable=True)
    email: Mapped[str | None] = mapped_column(String(150), nullable=True)
    direccion: Mapped[str | None] = mapped_column(String(255), nullable=True)

    productos: Mapped[list["Producto"]] = relationship(
        back_populates="proveedor"
    )


class Producto(Base):
    __tablename__ = "productos"

    id_producto: Mapped[int] = mapped_column(Integer, primary_key=True)
    nombre: Mapped[str] = mapped_column(String(150), nullable=False)
    descripcion: Mapped[str | None] = mapped_column(Text, nullable=True)
    precio: Mapped[object] = mapped_column(Numeric(10, 2), nullable=False)
    categoria_id: Mapped[int] = mapped_column(
        ForeignKey("categorias.id_categoria"), nullable=False
    )
    temporada_id: Mapped[int] = mapped_column(
        ForeignKey("temporadas.id_temporada"), nullable=False
    )
    coleccion_id: Mapped[int | None] = mapped_column(
        ForeignKey("colecciones.id_coleccion"), nullable=True
    )
    proveedor_id: Mapped[int] = mapped_column(
        ForeignKey("proveedores.id_proveedor"), nullable=False
    )
    imagen_url: Mapped[str | None] = mapped_column(String(255), nullable=True)
    modelo_3d_url: Mapped[str | None] = mapped_column(String(255), nullable=True)
    prompt_vestidor: Mapped[str | None] = mapped_column(Text, nullable=True)
    activo: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    categoria: Mapped["Categoria"] = relationship(back_populates="productos")
    temporada: Mapped["Temporada"] = relationship(back_populates="productos")
    coleccion: Mapped["Coleccion"] = relationship(back_populates="productos")
    proveedor: Mapped["Proveedor"] = relationship(back_populates="productos")
    variantes: Mapped[list["ProductoVariante"]] = relationship(
        back_populates="producto",
        cascade="all, delete-orphan",
    )


class ProductoVariante(Base):
    __tablename__ = "producto_variantes"
    __table_args__ = (
        UniqueConstraint("producto_id", "color_id", "talla_id", name="uq_variante"),
    )

    id_variante: Mapped[int] = mapped_column(Integer, primary_key=True)
    producto_id: Mapped[int] = mapped_column(
        ForeignKey("productos.id_producto"), nullable=False
    )
    color_id: Mapped[int] = mapped_column(
        ForeignKey("colores.id_color"), nullable=False
    )
    talla_id: Mapped[int] = mapped_column(
        ForeignKey("tallas.id_talla"), nullable=False
    )
    sku: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)
    precio_extra: Mapped[object] = mapped_column(
        Numeric(10, 2), nullable=False, default=0
    )

    producto: Mapped["Producto"] = relationship(back_populates="variantes")
    color: Mapped["Color"] = relationship(back_populates="variantes")
    talla: Mapped["Talla"] = relationship(back_populates="variantes")
