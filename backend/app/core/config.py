from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Configuración central de la aplicación (variables de entorno)."""

    # Base de datos
    DATABASE_URL: str = (
        "postgresql+psycopg2://postgres:09091991@localhost:5432/fashionstore"
    )

    # Seguridad / JWT
    SECRET_KEY: str = "fashionstore-secret-key-cambiar-en-produccion"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 120

    # Stripe (modo sandbox/test)
    STRIPE_SECRET_KEY: str = "sk_test_placeholder"
    STRIPE_WEBHOOK_SECRET: str = "whsec_placeholder"
    STRIPE_PUBLISHABLE_KEY: str = "pk_test_placeholder"
    STRIPE_CURRENCY: str = "usd"

    # Pasarela QR (Libelula / Todotix) - modo simulado por defecto.
    # Con QR_PROVEEDOR="libelula" y un QR_APPKEY real el cobro pasa a producción;
    # sin appkey el servicio genera el QR localmente y mantiene el mismo contrato.
    QR_PROVEEDOR: str = "simulado"  # "libelula" | "simulado"
    QR_APPKEY: str = ""
    QR_BASE_URL: str = "https://api.todotix.com"
    QR_CALLBACK_BASE: str = ""  # URL publica del tunel (ngrok/cloudflared)
    QR_TIMEOUT_MINUTOS: int = 15
    QR_MONEDA: str = "BOB"

    # Pantalla a la que vuelve el cliente tras pagar en Libelula (`url_retorno`).
    # No puede ser el webhook: el usuario debe caer en la interfaz del POS.
    QR_URL_RETORNO: str = ""

    # Datos fiscales que Libelula exige en el alta de la deuda. Vienen en la
    # config y no en el codigo para que activar la facturacion electronica sea
    # un cambio de configuracion y no de despliegue.
    QR_RAZON_SOCIAL: str = "-"
    QR_NIT: str = "-"
    QR_CLIENTE_CI: str = "-"
    QR_CLIENTE_APELLIDO: str = "-"
    QR_EMITE_FACTURA: str = "0"  # "1" para que Libelula emita factura electronica

    # IA / recomendador
    AI_API_URL: str = "https://api.openai.com/v1"
    AI_API_KEY: str = ""

    # Decart (vestidor virtual / virtual try-on, CU-07)
    DECART_API_KEY: str = ""
    DECART_BASE_URL: str = "https://api.decart.ai"
    DECART_VION_MODELO: str = "lucy-vton-latest"
    # Resolucion de la Process API foto→foto (lucy-image-2). Cada generacion
    # se factura con tarifa plana segun la resolucion: $0.01 en 480p / $0.02 en
    # 720p. Se baja a 480p por defecto porque es el costo por probada que fija
    # el plan del demo.
    DECART_PROCESS_RESOLUCION: str = "480p"
    # Orígenes web autorizados a usar el token de Decart. Deben coincidir con los
    # que el backend acepta en CORS: Decart valida el `Origin` de la conexión
    # WebRTC contra esta lista, así que un origen que quede fuera impide abrir la
    # sesión aunque CORS lo deje pasar.
    DECART_ORIGENES_PERMITIDOS: str = (
        "http://localhost:4200,http://127.0.0.1:4200,"
        "http://localhost:8080,http://127.0.0.1:8080,"
        "http://localhost:8091,http://127.0.0.1:8091,"
        "https://frontend-sepia-seven-97.vercel.app,"
        "https://frontend-4d8zoth3c-sistemas26.vercel.app"
    )

    # Configuración general
    APP_NAME: str = "FashionStore API"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = True

    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
