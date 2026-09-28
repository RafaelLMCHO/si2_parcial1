import asyncio
import logging
import mimetypes
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.db.session import SessionLocal
from app.services.estado_pago_service import conciliar_cobros_pendientes, vencer_cobros_vencidos

logger = logging.getLogger(__name__)

# Cada cuanto se barren los cobros QR que el cliente dejo sin pagar. La reserva
# de inventario solo se libera al vencer el cobro, asi que sin este barrido un
# cobro abandonado (el cliente se retiro y el cajero genero otro) mantendria sus
# unidades bloqueadas para siempre.
INTERVALO_BARRIDO_SEGUNDOS = 60

# La conciliacion contra la pasarela va bastante menos seguido que el barrido de
# vencimientos: implica una llamada HTTP externa, y la razon por la que existe es
# cubrir las notificaciones que Libelula pierde, no reaccionar en tiempo real.
INTERVALO_CONCILIACION_SEGUNDOS = 300


async def _barrido_cobros_periodico() -> None:
    while True:
        await asyncio.sleep(INTERVALO_BARRIDO_SEGUNDOS)
        try:
            # Se abre una sesion propia: la del ciclo de vida de la app no debe
            # cruzarse con las peticiones HTTP.
            with SessionLocal() as db:
                await asyncio.to_thread(vencer_cobros_vencidos, db)
        except Exception:  # noqa: BLE001 - el barrido nunca debe tumbar la app
            logger.exception("Fallo el barrido periodico de cobros QR")


async def _conciliacion_periodica() -> None:
    """Confirma con la pasarela los cobros pendientes que el aviso no resolvio.

    Corre en su propia tarea para que una pasarela lenta no retase el barrido de
    vencimientos, que si es tiempo critico: sin el, el inventario sigue
    reservado.
    """
    while True:
        await asyncio.sleep(INTERVALO_CONCILIACION_SEGUNDOS)
        try:
            with SessionLocal() as db:
                await asyncio.to_thread(conciliar_cobros_pendientes, db)
        except Exception:  # noqa: BLE001 - la conciliacion nunca debe tumbar la app
            logger.exception("Fallo la conciliacion periodica con la pasarela QR")


@asynccontextmanager
async def lifespan(app: FastAPI):
    tareas = [
        asyncio.create_task(_barrido_cobros_periodico()),
        asyncio.create_task(_conciliacion_periodica()),
    ]
    try:
        yield
    finally:
        for tarea in tareas:
            tarea.cancel()
        for tarea in tareas:
            try:
                await tarea
            except asyncio.CancelledError:
                pass


settings = get_settings()

app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="Plataforma Inteligente de Comercio Electrónico - FashionStore",
    openapi_url="/api/v1/openapi.json",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

# CORS - permitir Angular (web) y apps móviles (Flutter)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:4200", 
        "http://localhost:8100", 
        # Servidores locales de demostracion: Angular servido por Docker en el
        # 8080 y el build web de Flutter en el 8091. El visor web de AR/3D y
        # el probador de camara los necesitan para poder traer los modelos y las
        # imagenes de prenda desde otro origen.
        "http://localhost:8080",
        "http://127.0.0.1:8080",
        "http://localhost:8091",
        "http://127.0.0.1:8091",
        "https://frontend-sepia-seven-97.vercel.app", 
        "https://frontend-4d8zoth3c-sistemas26.vercel.app"
    ],  
    allow_origin_regex=r"^https://.*\.vercel\.app$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix="/api/v1")

# La tabla de tipos MIME de Python no conoce los dos formatos binarios que
# servimos desde /static, asi que sin esto StaticFiles los entrega como
# `text/plain` y el navegador los rechaza: los visores 3D no cargan el modelo y
# las imagenes .webp del catalogo no se muestran.
mimetypes.add_type("model/gltf-binary", ".glb")
mimetypes.add_type("image/webp", ".webp")

# CU-07 · Vestidor virtual: modelos 3D (`.glb`) de los productos.
# Las URLs se guardan relativas (`/static/models/...`) y el cliente
# (móvil/web) las resuelve contra su origen; evita hardcodear el host.
_STATIC_DIR = Path(__file__).resolve().parent.parent / "static"
app.mount("/static", StaticFiles(directory=_STATIC_DIR, html=False), name="static")


@app.get("/", tags=["health"])
def health_check():
    return {"status": "ok", "app": settings.APP_NAME, "version": settings.APP_VERSION}
