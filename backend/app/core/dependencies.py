from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.security import decode_access_token
from app.db.session import get_db
from app.models import Usuario, RolUsuario
from app.models.usuario import Usuario as UsuarioModel

settings = get_settings()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")
oauth2_scheme_optional = OAuth2PasswordBearer(
    tokenUrl="/api/v1/auth/login", auto_error=False
)


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> Usuario:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Credenciales inválidas o expiradas",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = decode_access_token(token)
        user_id: str = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    user = db.get(UsuarioModel, int(user_id))
    if user is None or not user.activo:
        raise credentials_exception
    return user


def get_current_user_optional(
    token: str | None = Depends(oauth2_scheme_optional),
    db: Session = Depends(get_db),
) -> Usuario | None:
    if not token:
        return None
    try:
        payload = decode_access_token(token)
        user_id: str = payload.get("sub")
        if user_id is None:
            return None
    except JWTError:
        return None
    user = db.get(UsuarioModel, int(user_id))
    if user is None or not user.activo:
        return None
    return user


def require_roles(*roles: RolUsuario):
    """Dependencia que valida que el usuario actual tenga uno de los roles dados."""

    def checker(user: Usuario = Depends(get_current_user)) -> Usuario:
        if user.rol not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="No tiene permisos para realizar esta acción",
            )
        return user

    return checker


admin_required = require_roles(RolUsuario.admin)
encargado_required = require_roles(RolUsuario.admin, RolUsuario.encargado)
cajero_required = require_roles(
    RolUsuario.admin, RolUsuario.encargado, RolUsuario.cajero
)

# Cobrar con QR o con tarjeta desde el POS web lo puede hacer tambien el
# cliente. El efectivo sigue siendo exclusivo del personal de caja, porque ahi
# es el cajero el que cuenta el dinero y se queda con el ticket.
pago_required = require_roles(
    RolUsuario.admin,
    RolUsuario.encargado,
    RolUsuario.cajero,
    RolUsuario.cliente,
)
