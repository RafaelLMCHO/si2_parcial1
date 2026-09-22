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

    # IA / recomendador
    AI_API_URL: str = "https://api.openai.com/v1"
    AI_API_KEY: str = ""

    # Decart (vestidor virtual / virtual try-on, CU-07)
    DECART_API_KEY: str = ""
    DECART_BASE_URL: str = "https://api.decart.ai"
    DECART_VION_MODELO: str = "lucy-vton-latest"

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
