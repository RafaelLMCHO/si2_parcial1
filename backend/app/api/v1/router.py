from fastapi import APIRouter

from app.api.v1.endpoints import (
    auth,
    usuarios,
    sucursales,
    catalogo,
    inventario,
    reservas,
    vestidor,
    ventas,
    pagos,
    ia,
    bitacora,
    reportes,
    publico,
)

api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["Autenticación"])
api_router.include_router(usuarios.router, prefix="/usuarios", tags=["Usuarios"])
api_router.include_router(sucursales.router, prefix="/sucursales", tags=["Sucursales"])
api_router.include_router(catalogo.router, prefix="/catalogo", tags=["Catálogo"])
api_router.include_router(inventario.router, prefix="/inventario", tags=["Inventario"])
api_router.include_router(reservas.router, prefix="/reservas", tags=["Reservas"])
api_router.include_router(vestidor.router, tags=["Vestidor Virtual"])
api_router.include_router(ventas.router, prefix="/ventas", tags=["Ventas y Pagos"])
api_router.include_router(pagos.router, prefix="/pagos", tags=["Gestión de Pagos y Pasarela"])
api_router.include_router(ia.router, prefix="/ia", tags=["Inteligencia Artificial"])
api_router.include_router(bitacora.router, prefix="/bitacora", tags=["Bitácora"])
api_router.include_router(reportes.router, prefix="/reportes", tags=["Reportes"])
api_router.include_router(publico.router, prefix="/config/public", tags=["Configuración"])
