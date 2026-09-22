import logging

import stripe

from app.core.config import get_settings

settings = get_settings()
stripe.api_key = settings.STRIPE_SECRET_KEY

logger = logging.getLogger(__name__)


def pasarela_operativa() -> bool:
    """Verifica que la clave secreta configurada realmente funcione con la API de Stripe.

    Retorna True solo si hay una clave real válida; si la clave es placeholder, está vacía
    o es rechazada por Stripe, retorna False (el sistema opera en modo simulado).
    """
    if not settings.STRIPE_SECRET_KEY or settings.STRIPE_SECRET_KEY.startswith("sk_test_placeholder"):
        return False
    try:
        stripe.Balance.retrieve()
        return True
    except stripe.error.StripeError:
        logger.warning(
            "La clave de API de Stripe configurada no es válida; se usará el modo simulado."
        )
        return False


def crear_intencion_pago(monto_total: float, descripcion: str) -> dict:
    """Crea un PaymentIntent de Stripe (modo sandbox/test).

    Retorna el client_secret que la app móvil/web usará para confirmar.
    Si no hay claves reales válidas, genera una intención simulada.
    """
    if not pasarela_operativa():
        # Modo de simulación cuando no hay claves reales configuradas.
        return {
            "id": "pi_simulado_" + descripcion[:20].replace(" ", "_"),
            "client_secret": "pi_simulado_secret",
            "simulado": True,
        }
    try:
        intent = stripe.PaymentIntent.create(
            amount=int(round(monto_total * 100)),
            currency=settings.STRIPE_CURRENCY,
            description=descripcion,
        )
    except stripe.error.StripeError as e:
        logger.warning("No se pudo crear el PaymentIntent en Stripe: %s", e)
        return {
            "id": "pi_simulado_" + descripcion[:20].replace(" ", "_"),
            "client_secret": "pi_simulado_secret",
            "simulado": True,
        }
    return {
        "id": intent.id,
        "client_secret": intent.client_secret,
        "simulado": False,
    }


def crear_sesion_checkout(
    monto_total: float,
    descripcion: str,
    correo: str,
    success_url: str,
    cancel_url: str,
) -> dict:
    """Crea una Checkout Session (página alojada) de Stripe.

    Devuelve la URL a la que el cliente debe ser redirigido para pagar en la
    página de Stripe. Si no hay claves reales válidas, retorna simulado=True
    sin URL (el cliente conserva el flujo simulado embebido).
    """
    if not pasarela_operativa():
        return {"session_id": None, "checkout_url": None, "simulado": True}
    try:
        sesion = stripe.checkout.Session.create(
            mode="payment",
            payment_method_types=["card"],
            line_items=[{
                "price_data": {
                    "currency": settings.STRIPE_CURRENCY,
                    "unit_amount": int(round(monto_total * 100)),
                    "product_data": {"name": descripcion},
                },
                "quantity": 1,
            }],
            customer_email=correo,
            success_url=success_url,
            cancel_url=cancel_url,
        )
    except stripe.error.StripeError as e:
        logger.warning("No se pudo crear la Checkout Session en Stripe: %s", e)
        return {"session_id": None, "checkout_url": None, "simulado": True}
    return {"session_id": sesion.id, "checkout_url": sesion.url, "simulado": False}


def confirmar_pago_simulado(numero_tarjeta: str | None = None) -> bool:
    """
    En modo sandbox, valida números de tarjeta de prueba conocidos de Stripe:
    - Tarjetas estándar (4242...): Aprobado.
    - Tarjetas de error (4000 0000 0000 0002, o con '0000'): Rechazado.
    """
    if numero_tarjeta:
        clean = numero_tarjeta.replace(" ", "").replace("-", "")
        if clean.startswith("4000") or "00000000" in clean or clean.endswith("0002"):
            return False
    return True
