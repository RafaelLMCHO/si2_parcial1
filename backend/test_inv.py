import sys
from app.db.session import SessionLocal
from app.models import Inventario, ProductoVariante, Producto, Sucursal, Usuario
from app.api.v1.endpoints.inventario import inventario_global

db = SessionLocal()
try:
    admin = db.query(Usuario).filter(Usuario.email == "admin@fashionstore.bo").first()
    print("Testing admin...")
    res_admin = inventario_global(sucursal_id=None, categoria_id=None, q=None, stock_bajo_solo=False, db=db, user=admin)
    print("Admin items count:", len(res_admin))

    encargado = db.query(Usuario).filter(Usuario.email == "juan.perez@fashionstore.bo").first()
    print("Testing encargado...", encargado.nombre, "sucursal:", encargado.sucursal_id)
    res_enc = inventario_global(sucursal_id=encargado.sucursal_id, categoria_id=None, q=None, stock_bajo_solo=False, db=db, user=encargado)
    print("Encargado items count:", len(res_enc))
except Exception as e:
    import traceback
    traceback.print_exc()
finally:
    db.close()
