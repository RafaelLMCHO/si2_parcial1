from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.security import create_access_token, hash_password, verify_password
from app.db.session import get_db
from app.models import Usuario, RolUsuario
from app.schemas.usuario import (
    LoginRequest,
    PerfilUpdate,
    Token,
    UsuarioCreate,
    UsuarioOut,
)

router = APIRouter()


@router.post(
    "/register",
    response_model=UsuarioOut,
    status_code=status.HTTP_201_CREATED,
    summary="Registrar un nuevo cliente",
)
def register(data: UsuarioCreate, db: Session = Depends(get_db)):
    if db.query(Usuario).filter(Usuario.email == data.email).first():
        raise HTTPException(status_code=400, detail="El email ya está registrado")

    usuario = Usuario(
        nombre=data.nombre,
        email=data.email,
        telefono=data.telefono,
        contrasena=hash_password(data.contrasena),
        rol=data.rol,
        sucursal_id=data.sucursal_id,
    )
    db.add(usuario)
    db.commit()
    db.refresh(usuario)
    return usuario


@router.post("/login", response_model=Token, summary="Iniciar sesión (JWT)")
def login(data: LoginRequest, db: Session = Depends(get_db)):
    email_clean = (data.email or "").strip()
    usuario = db.query(Usuario).filter(Usuario.email.ilike(email_clean)).first()
    if not usuario or not verify_password(data.contrasena, usuario.contrasena):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Credenciales incorrectas",
        )
    if not usuario.activo:
        raise HTTPException(status_code=403, detail="Cuenta desactivada")

    token = create_access_token(subject=str(usuario.id_usuario))
    return Token(access_token=token, usuario=UsuarioOut.model_validate(usuario))


@router.post("/login/form", response_model=Token, include_in_schema=False)
def login_form(
    form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)
):
    email_clean = (form.username or "").strip()
    usuario = db.query(Usuario).filter(Usuario.email.ilike(email_clean)).first()
    if not usuario or not verify_password(form.password, usuario.contrasena):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Credenciales incorrectas",
        )
    token = create_access_token(subject=str(usuario.id_usuario))
    return Token(access_token=token, usuario=UsuarioOut.model_validate(usuario))


@router.get("/me", response_model=UsuarioOut, summary="Obtener usuario autenticado")
def read_me(current_user: Usuario = Depends(get_current_user)):
    return current_user


@router.patch(
    "/me",
    response_model=UsuarioOut,
    summary="Actualizar el perfil del usuario autenticado (CU-03)",
)
def update_me(
    data: PerfilUpdate,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    duplicado = (
        db.query(Usuario)
        .filter(
            Usuario.email == data.email,
            Usuario.id_usuario != current_user.id_usuario,
        )
        .first()
    )
    if duplicado:
        raise HTTPException(status_code=400, detail="El correo ya está en uso")

    usuario = db.get(Usuario, current_user.id_usuario)
    usuario.nombre = data.nombre
    usuario.email = data.email
    usuario.telefono = data.telefono
    db.commit()
    db.refresh(usuario)
    return usuario
