from fastapi import APIRouter

from app.core.config import get_settings
from app.services.stripe_service import pasarela_operativa

router = APIRouter()


@router.get("", summary="Configuración pública (cliente móvil/web)")
def config_publica():
    """Expone la clave pública de la pasarela para que el cliente móvil inicialice
    Stripe Elements, e indica si la pasarela corre en modo simulado."""
    settings = get_settings()
    operativa = pasarela_operativa()
    pk = settings.STRIPE_PUBLISHABLE_KEY or ""
    return {
        "stripe_publishable_key": pk if operativa and pk and not pk.startswith("pk_test_placeholder") else None,
        "pasarela_simulada": not operativa,
        "moneda": settings.STRIPE_CURRENCY,
    }