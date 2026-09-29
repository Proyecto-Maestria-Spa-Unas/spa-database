# Base de Datos Spa de Uñas - PostgreSQL + PostGIS (Supabase)

Repositorio del esquema de base de datos del sistema de inventario de un spa de uñas. Contiene las migraciones, políticas de seguridad a nivel de fila (RLS), funciones, triggers de control de stock, datos semilla del catálogo y pruebas SQL. Es la única fuente de verdad del modelo de datos: ningún otro repositorio crea ni modifica tablas.

## 🚀 Tecnologías Principales

* PostgreSQL 16
* PostGIS
* Supabase (hosting, autenticación y API)
* Supabase CLI
* Docker Desktop (base de datos local)
* psql

## ⚙️ Configuración del Entorno

### 1️⃣ Clonar el repositorio

```
git clone https://github.com/Proyecto-Maestria-Spa-Unas/spa-database.git
cd spa-database
git checkout develop
```

### 2️⃣ Instalar Docker Desktop

Supabase CLI levanta la base de datos local en contenedores. Instale Docker Desktop y verifique:

```
docker version
```

### 3️⃣ Instalar Supabase CLI

#### 🐧 Linux / Mac

```
brew install supabase/tap/supabase
```

#### 🪟 Windows (PowerShell)

```
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase
```

Alternativa sin instalación global (cualquier sistema con Node.js):

```
npx supabase --version
```

### 4️⃣ Inicializar y vincular el proyecto

```
supabase init
supabase link --project-ref <ref-del-proyecto>
```

El `project-ref` se encuentra en el panel de Supabase → Project Settings → General.

## ▶️ Ejecutar la base de datos en local

```
supabase start
supabase db reset
```

`supabase db reset` recrea la base local, aplica todas las migraciones de `supabase/migrations` en orden y carga `supabase/seed.sql`.

Acceder a:

* 🗄️ Supabase Studio local: http://127.0.0.1:54323
* 🔌 Conexión PostgreSQL local: `postgresql://postgres:postgres@127.0.0.1:54322/postgres`

Detener:

```
supabase stop
```

## 🧱 Crear una migración

```
supabase migration new nombre_descriptivo
```

Se crea `supabase/migrations/AAAAMMDDHHMMSS_nombre_descriptivo.sql`. Cada migración debe:

* Ser idempotente (`IF NOT EXISTS`, `CREATE OR REPLACE`).
* Ser compatible hacia atrás con la versión desplegada del backend.
* Venir acompañada de su prueba en `tests/sql/`.
* No modificarse una vez fusionada en `develop` (los cambios se hacen con una migración nueva).

## 📦 Componentes Principales

### 🔹 Migraciones (`supabase/migrations`)
DDL versionado: tablas, restricciones, índices, funciones, triggers y políticas RLS.

### 🔹 Seeds (`supabase/seed.sql`)
Catálogo inicial de categorías (Esmaltes, Materiales, Uñas, Decoración, Productos químicos, Herramientas, Bioseguridad / limpieza, Atención al cliente) y unidades de medida.

### 🔹 Pruebas SQL (`tests/sql`)
Bloques `DO $$ ... ASSERT ... $$` que validan estructura, permisos y reglas de negocio (stock no negativo, cantidades mayores que cero, estados del inventario).

### 🔹 Extensiones
* **pgcrypto**: generación de UUID y funciones criptográficas.
* **citext**: textos sin distinción de mayúsculas para códigos y correos.
* **postgis**: capacidades espaciales para análisis territorial y sedes.

## 🔐 Variables de Entorno

Este repositorio no requiere `.env` para trabajar en local. Para operar contra un proyecto remoto, la Supabase CLI solicita la contraseña de la base al vincular. Las credenciales de staging y producción se guardan únicamente como secretos de GitHub en los entornos `staging` y `production`.

⚠️ Nunca suba cadenas de conexión, contraseñas ni archivos `.dump` o `.backup` al repositorio (ya están incluidos en el `.gitignore`).

## 📁 Organización del proyecto

| Carpeta | Uso |
|---|---|
| `supabase/migrations` | Migraciones versionadas del esquema. |
| `supabase/seed.sql` | Datos semilla idempotentes del catálogo. |
| `tests/sql` | Pruebas SQL ejecutadas en la integración continua. |
| `scripts/ci/supabase_shim.sql` | Emula en CI los roles y el esquema `auth` de Supabase sobre PostgreSQL limpio. |
| `docs/CONVENCIONES.md` | Reglas de modelado, nomenclatura, migraciones y RLS. |

## 🧪 Pruebas y calidad

La integración continua (`calidad / pipeline`) levanta PostgreSQL 16 con PostGIS y:

1. Aplica el shim de Supabase.
2. Aplica todas las migraciones en orden.
3. Carga los seeds.
4. Ejecuta todas las pruebas de `tests/sql`.
5. Re-aplica las migraciones para verificar que sean idempotentes.

Para ejecutar las pruebas en local contra la base de Supabase CLI:

```
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f tests/sql/0001_base_test.sql
```

## 🔀 Flujo de trabajo

1. Crear la rama desde `develop`: `git checkout -b feature/HU-07-trigger-stock-salida`.
2. Crear la migración y su prueba.
3. Abrir un Pull Request hacia `develop`.
4. El PR solo se puede fusionar cuando pasan los checks `politica / pr`, `calidad / pipeline` y `seguridad / scan`, y lo aprueba el equipo de datos.
