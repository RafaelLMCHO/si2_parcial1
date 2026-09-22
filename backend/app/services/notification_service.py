import logging

logger = logging.getLogger(__name__)

class NotificationService:
    @staticmethod
    def enviar_notificacion_reserva_preparada(email: str, reserva_id: int):
        """
        Simula el envío de una notificación al cliente (vía correo o push).
        En un entorno real, aquí se integraría con un proveedor como SendGrid, AWS SES, Firebase, etc.
        """
        mensaje = f"NOTIFICACIÓN ENVIADA: Cliente {email} -> Su reserva #{reserva_id} está lista para probarse."
        logger.info(mensaje)
        # Podríamos guardar esto en una tabla de base de datos también si fuera necesario
        return True

    @staticmethod
    def enviar_notificacion_compra_digital(email: str, pedido_id: int, total: float):
        """
        Simula el envío del comprobante de compra digital por correo electrónico al cliente.
        """
        mensaje = f"COMPROBANTE ENVIADO: Cliente {email} -> Pedido Digital #{pedido_id} confirmado. Total: Bs. {total:.2f}"
        logger.info(mensaje)
        return True

