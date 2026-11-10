
-- ============================================================
-- D13: Roles de base de datos por servicio con privilegios mínimos
-- Archivo: 20261109100000_roles_servicios.sql
--
-- Alcance:
--   - Crear/configurar roles técnicos NOLOGIN.
--   - Conceder privilegios declarativos mínimos por servicio.
--   - Retirar privilegios directos previos de estos roles.
--   - No modifica políticas RLS.
--   - No crea usuarios ni contraseñas.
--   - No integra todavía los roles con el backend.
-- ============================================================

BEGIN;

-- 1. Creación idempotente de roles técnicos.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'svc_identidad') THEN
        CREATE ROLE svc_identidad;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'svc_catalogo') THEN
        CREATE ROLE svc_catalogo;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'svc_movimientos') THEN
        CREATE ROLE svc_movimientos;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'svc_analitica') THEN
        CREATE ROLE svc_analitica;
    END IF;
END;
$$;

-- 2. Configuración segura.
ALTER ROLE svc_identidad
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOINHERIT NOREPLICATION NOBYPASSRLS;

ALTER ROLE svc_catalogo
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOINHERIT NOREPLICATION NOBYPASSRLS;

ALTER ROLE svc_movimientos
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOINHERIT NOREPLICATION NOBYPASSRLS;

ALTER ROLE svc_analitica
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOINHERIT NOREPLICATION NOBYPASSRLS;

COMMENT ON ROLE svc_identidad IS
    'Rol técnico declarativo para operaciones del módulo de identidad.';

COMMENT ON ROLE svc_catalogo IS
    'Rol técnico declarativo para operaciones del módulo de catálogo.';

COMMENT ON ROLE svc_movimientos IS
    'Rol técnico declarativo para operaciones del módulo de movimientos.';

COMMENT ON ROLE svc_analitica IS
    'Rol técnico declarativo de solo lectura para consultas analíticas.';

-- 3. Retirar membresías previas relacionadas con estos roles.
-- Se eliminan tanto las membresías que tengan estos roles como
-- miembros, como aquellas en las que estos roles hayan sido concedidos.

DO $$
DECLARE
    v_membresia record;
BEGIN
    FOR v_membresia IN
        SELECT DISTINCT
            granted.rolname AS rol_concedido,
            member_role.rolname AS miembro
        FROM pg_catalog.pg_auth_members m
        JOIN pg_catalog.pg_roles granted
            ON granted.oid = m.roleid
        JOIN pg_catalog.pg_roles member_role
            ON member_role.oid = m.member
        WHERE granted.rolname IN (
            'svc_identidad',
            'svc_catalogo',
            'svc_movimientos',
            'svc_analitica'
        )
        OR member_role.rolname IN (
            'svc_identidad',
            'svc_catalogo',
            'svc_movimientos',
            'svc_analitica'
        )
    LOOP
        EXECUTE pg_catalog.format(
            'REVOKE %I FROM %I',
            v_membresia.rol_concedido,
            v_membresia.miembro
        );
    END LOOP;
END;
$$;

-- 4. Retirar privilegios directos previos sobre esquemas.
-- No se modifican privilegios de PUBLIC ni de otros roles.

REVOKE ALL ON SCHEMA inventario, seguridad, auditoria
FROM svc_identidad, svc_catalogo, svc_movimientos, svc_analitica;

-- 5. Retirar privilegios directos previos sobre tablas y vistas.

REVOKE ALL ON ALL TABLES IN SCHEMA inventario, seguridad, auditoria
FROM svc_identidad, svc_catalogo, svc_movimientos, svc_analitica;

-- 6. Retirar privilegios directos previos sobre secuencias.

REVOKE ALL ON ALL SEQUENCES IN SCHEMA inventario, seguridad, auditoria
FROM svc_identidad, svc_catalogo, svc_movimientos, svc_analitica;

-- 7. Retirar privilegios directos previos por columna.
-- Se revisan únicamente concesiones cuyo destinatario sea uno
-- de los cuatro roles técnicos.

DO $$
DECLARE
    v_columna record;
BEGIN
    FOR v_columna IN
        SELECT DISTINCT
            table_schema,
            table_name,
            column_name,
            privilege_type,
            grantee
        FROM information_schema.column_privileges
        WHERE table_schema IN ('inventario', 'seguridad', 'auditoria')
          AND grantee IN (
              'svc_identidad',
              'svc_catalogo',
              'svc_movimientos',
              'svc_analitica'
          )
    LOOP
        EXECUTE pg_catalog.format(
            'REVOKE %s (%I) ON TABLE %I.%I FROM %I',
            v_columna.privilege_type,
            v_columna.column_name,
            v_columna.table_schema,
            v_columna.table_name,
            v_columna.grantee
        );
    END LOOP;
END;
$$;

-- 8. Retirar privilegios EXECUTE previos sobre funciones
-- de los esquemas de la aplicación.

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA inventario, seguridad, auditoria
FROM svc_identidad, svc_catalogo, svc_movimientos, svc_analitica;

-- 9. Uso de esquemas.

GRANT USAGE ON SCHEMA seguridad TO svc_identidad;

GRANT USAGE ON SCHEMA inventario
TO svc_catalogo, svc_movimientos, svc_analitica;

-- 10. Servicio de identidad.

GRANT SELECT ON TABLE
    seguridad.rol,
    seguridad.permiso,
    seguridad.rol_permiso
TO svc_identidad;

GRANT SELECT, INSERT, UPDATE
ON TABLE seguridad.perfil
TO svc_identidad;

-- No se concede acceso a auth.users.
-- El repositorio actual consulta auth.users para obtener email.
-- Ese acceso debe resolverse en una fase posterior mediante
-- un mecanismo explícito de mínimo privilegio.

-- 11. Servicio de catálogo.

GRANT SELECT, INSERT, UPDATE
ON TABLE inventario.categoria
TO svc_catalogo;

GRANT SELECT
ON TABLE inventario.unidad_medida
TO svc_catalogo;

GRANT SELECT
ON TABLE inventario.producto
TO svc_catalogo;

GRANT INSERT (
    codigo,
    nombre,
    descripcion,
    categoria_id,
    unidad_medida_id,
    stock_minimo
)
ON TABLE inventario.producto
TO svc_catalogo;

GRANT UPDATE (
    nombre,
    descripcion,
    categoria_id,
    unidad_medida_id,
    stock_minimo,
    descontinuado
)
ON TABLE inventario.producto
TO svc_catalogo;

GRANT SELECT
ON TABLE inventario.motivo_movimiento
TO svc_catalogo;

-- El módulo de catálogo gestiona proveedores.
GRANT SELECT, INSERT, UPDATE
ON TABLE inventario.proveedor
TO svc_catalogo;

-- No se concede DELETE sobre proveedor ni INSERT sobre movimiento.
-- El registro de saldo inicial debe delegarse al módulo de movimientos.

-- Conceder USAGE y SELECT sobre la secuencia de categoria
-- únicamente si existe.

DO $$
DECLARE
    v_secuencia text;
BEGIN
    v_secuencia := pg_catalog.pg_get_serial_sequence(
        'inventario.categoria',
        'id'
    );

    IF v_secuencia IS NOT NULL THEN
        EXECUTE pg_catalog.format(
            'GRANT USAGE, SELECT ON SEQUENCE %s TO svc_catalogo',
            v_secuencia::regclass
        );
    END IF;
END;
$$;

-- 12. Servicio de movimientos.

GRANT SELECT
ON TABLE inventario.producto, inventario.motivo_movimiento
TO svc_movimientos;

GRANT SELECT
ON TABLE inventario.movimiento
TO svc_movimientos;

GRANT INSERT (
    producto_id,
    tipo,
    motivo_id,
    cantidad,
    costo_unitario,
    proveedor_id,
    observacion,
    registrado_por,
    movimiento_anulado_id,
    clave_idempotencia
)
ON TABLE inventario.movimiento
TO svc_movimientos;

-- No se conceden UPDATE, DELETE ni TRUNCATE sobre movimiento.
-- No se concede SELECT sobre proveedor: el repositorio utiliza
-- proveedor_id en el INSERT, sin consulta directa de esa tabla.

-- 13. Servicio de analítica: solo lectura.

GRANT SELECT
ON TABLE
    inventario.v_inventario,
    inventario.v_alerta_stock,
    inventario.v_kardex,
    inventario.v_consumo_diario
TO svc_analitica;

GRANT SELECT
ON TABLE
    inventario.producto,
    inventario.categoria,
    inventario.unidad_medida,
    inventario.movimiento,
    inventario.motivo_movimiento,
    inventario.proveedor
TO svc_analitica;

-- Localizar dinámicamente el esquema de PostGIS.

DO $$
DECLARE
    v_esquema_postgis name;
BEGIN
    SELECT n.nspname
      INTO v_esquema_postgis
      FROM pg_catalog.pg_extension e
      JOIN pg_catalog.pg_namespace n
        ON n.oid = e.extnamespace
     WHERE e.extname = 'postgis';

    IF v_esquema_postgis IS NOT NULL THEN
        EXECUTE pg_catalog.format(
            'GRANT USAGE ON SCHEMA %I TO svc_analitica',
            v_esquema_postgis
        );
    END IF;
END;
$$;

-- Permiso de ejecución de la función espacial propia de D12.

GRANT EXECUTE
ON FUNCTION inventario.proveedores_cercanos(
    double precision,
    double precision,
    double precision
)
TO svc_analitica;

COMMIT;
