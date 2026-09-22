import os
from sqlalchemy import create_engine, MetaData

local_url = "postgresql+psycopg2://postgres:rafa@localhost:5432/fashionstore"
remote_url = "postgresql+psycopg2://postgres:Rafael123$$$rafa@db.hgwhyxbdbkqakzdmqijx.supabase.co:5432/postgres"

from app.models import Base
print("Conectando a las bases de datos...")
local_engine = create_engine(local_url)
remote_engine = create_engine(remote_url)

print("Creando tablas en la base de datos remota...")
Base.metadata.create_all(remote_engine)

meta = MetaData()
print("Leyendo estructura de la base de datos local...")
meta.reflect(bind=local_engine)

print("Iniciando migración de datos...")

# Deshabilitar constraints temporalmente en Postgres remoto si es posible, o simplemente 
# insertar en orden. Como usamos sorted_tables, se respeta el orden de las dependencias (FKs).

for table in meta.sorted_tables:
    print(f"-> Migrando tabla: {table.name}...")
    with local_engine.connect() as local_conn:
        rows = local_conn.execute(table.select()).fetchall()
    
    if rows:
        # Extraer nombres de columnas y convertir a lista de diccionarios
        keys = table.columns.keys()
        data = [dict(zip(keys, row)) for row in rows]
        
        with remote_engine.begin() as remote_conn:
            # Primero borramos cualquier dato existente para evitar colisiones
            remote_conn.execute(table.delete())
            # Insertar los datos de la BD local
            remote_conn.execute(table.insert(), data)
        print(f"   [OK] {len(data)} registros migrados.")
    else:
        print(f"   [OK] 0 registros (tabla vacía).")

print("¡Migración completada con éxito!")
