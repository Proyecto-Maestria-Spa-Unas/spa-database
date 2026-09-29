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

## 🌿 Cómo contribuir

### 1️⃣ Clonar el repositorio (solo la primera vez)

Use **Git Bash** en Windows o la terminal en Linux/Mac:

```
git config --global core.autocrlf input
git clone https://github.com/Proyecto-Maestria-Spa-Unas/spa-database.git
cd spa-database
git switch develop
```

### 2️⃣ Crear la rama de su tarea

Nunca se trabaja directamente sobre `main` ni `develop`: GitHub rechaza esos push. Cada tarea tiene su rama, creada desde `develop` actualizada:

```
git switch develop
git pull
git switch -c feature/D2-migracion-catalogo
```

Formato obligatorio: **`tipo/ID-descripcion-corta`**. El `ID` es el de la tarea del sprint en mayúscula (D1, B2, F3, Q1…) y la descripción va en minúsculas, con guiones y sin espacios ni tildes.

| Tipo | Úselo para |
|---|---|
| `feature/` | Funcionalidad nueva |
| `fix/` | Corrección de un defecto |
| `docs/` | Documentación |
| `test/` | Pruebas |
| `refactor/` | Mejora interna sin cambio funcional |
| `chore/` · `ci/` | Mantenimiento y automatización |

### 3️⃣ Guardar y subir los cambios

```
git add .
git commit -s -m "feat(catalogo): migración de categoria, unidad_medida y producto (D2)"
git push -u origin feature/D2-migracion-catalogo
```

El mensaje sigue **Conventional Commits**: `tipo(alcance): descripción (ID)`. La opción `-s` firma el commit.

### 4️⃣ Abrir el Pull Request

```
gh pr create --base develop --fill
```

O desde GitHub con el botón **Compare & pull request**. En la descripción escriba `Closes Proyecto-Maestria-Spa-Unas/spa-database#<número de la tarea>`. El PR se fusiona cuando los checks obligatorios están en verde.

### 5️⃣ Mantener su rama al día

Si `develop` avanzó mientras usted trabajaba:

```
git switch develop
git pull
git switch -
git rebase develop
git push --force-with-lease
```

`--force-with-lease` solo se usa sobre **su propia rama**, nunca sobre `main` ni `develop`.

### ❌ Qué no hacer

* No subir archivos `.env`, contraseñas ni llaves: el escaneo de seguridad bloqueará el PR.
* No mezclar varias tareas en una misma rama: una rama, una tarea, un PR.
