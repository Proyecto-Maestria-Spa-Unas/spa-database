-- ============================================================
-- D13: Pruebas de privilegios declarativos por servicio
-- Archivo: tests/sql/test_d13_roles_servicios.sql
--
-- Alcance:
--   - Verificar existencia y configuración segura de los roles.
--   - Verificar privilegios efectivos requeridos.
--   - Verificar ausencia de privilegios directos no autorizados.
--   - Verificar ausencia de membresías relacionadas.
--
-- Estas pruebas verifican ACL.
-- No simulan RLS ni demuestran que el backend utilice los roles.
-- Las pruebas negativas inspeccionan ACL directas del rol; no
-- sustituyen una evaluación completa de privilegios heredados/PUBLIC.
-- ============================================================

BEGIN;

-- 1. Existencia, configuración segura y membresías.
DO $$
DECLARE
    v_roles text[] := ARRAY[
        'svc_identidad',
        'svc_catalogo',
        'svc_movimientos',
        'svc_analitica'
    ];
    v_rol text;
    v_cantidad integer;
BEGIN
    SELECT count(*)
      INTO v_cantidad
      FROM pg_catalog.pg_roles
     WHERE rolname = ANY (v_roles);

    IF v_cantidad <> 4 THEN
        RAISE EXCEPTION
            'D13: se esperaban 4 roles técnicos y se encontraron %',
            v_cantidad;
    END IF;

    FOREACH v_rol IN ARRAY v_roles LOOP

        IF NOT EXISTS (
            SELECT 1
              FROM pg_catalog.pg_roles
             WHERE rolname = v_rol
               AND NOT rolsuper
               AND NOT rolcreatedb
               AND NOT rolcreaterole
               AND NOT rolcanlogin
               AND NOT rolreplication
               AND NOT rolbypassrls
               AND NOT rolinherit
        ) THEN
            RAISE EXCEPTION
                'D13: configuración insegura o incompleta para %',
                v_rol;
        END IF;

        -- El rol no debe ser miembro de otro rol.
        IF EXISTS (
            SELECT 1
              FROM pg_catalog.pg_auth_members m
              JOIN pg_catalog.pg_roles r
                ON r.oid = m.member
             WHERE r.rolname = v_rol
        ) THEN
            RAISE EXCEPTION
                'D13: % es miembro de otro rol',
                v_rol;
        END IF;

        -- El rol tampoco debe estar concedido a otros roles.
        IF EXISTS (
            SELECT 1
              FROM pg_catalog.pg_auth_members m
              JOIN pg_catalog.pg_roles r
                ON r.oid = m.roleid
             WHERE r.rolname = v_rol
        ) THEN
            RAISE EXCEPTION
                'D13: % está concedido como membresía a otro rol',
                v_rol;
        END IF;

    END LOOP;
END;
$$;

-- 2. Pruebas positivas: privilegios efectivos requeridos.
DO $$
BEGIN
    -- IDENTIDAD.
    IF NOT has_schema_privilege(
        'svc_identidad', 'seguridad', 'USAGE'
    ) THEN
        RAISE EXCEPTION
            'svc_identidad debe tener USAGE en seguridad';
    END IF;

    IF NOT has_table_privilege(
        'svc_identidad', 'seguridad.perfil', 'SELECT'
    )
    OR NOT has_table_privilege(
        'svc_identidad', 'seguridad.perfil', 'INSERT'
    )
    OR NOT has_table_privilege(
        'svc_identidad', 'seguridad.perfil', 'UPDATE'
    ) THEN
        RAISE EXCEPTION
            'Privilegios de perfil incompletos para svc_identidad';
    END IF;

    IF NOT has_table_privilege(
        'svc_identidad', 'seguridad.rol', 'SELECT'
    )
    OR NOT has_table_privilege(
        'svc_identidad', 'seguridad.permiso', 'SELECT'
    )
    OR NOT has_table_privilege(
        'svc_identidad', 'seguridad.rol_permiso', 'SELECT'
    ) THEN
        RAISE EXCEPTION
            'Privilegios de consulta de seguridad incompletos';
    END IF;

    -- CATÁLOGO.
    IF NOT has_schema_privilege(
        'svc_catalogo', 'inventario', 'USAGE'
    ) THEN
        RAISE EXCEPTION
            'svc_catalogo debe tener USAGE en inventario';
    END IF;

    IF NOT has_table_privilege(
        'svc_catalogo', 'inventario.categoria', 'SELECT'
    )
    OR NOT has_table_privilege(
        'svc_catalogo', 'inventario.categoria', 'INSERT'
    )
    OR NOT has_table_privilege(
        'svc_catalogo', 'inventario.categoria', 'UPDATE'
    ) THEN
        RAISE EXCEPTION
            'Privilegios de categoria incompletos para svc_catalogo';
    END IF;

    IF NOT has_table_privilege(
        'svc_catalogo', 'inventario.unidad_medida', 'SELECT'
    )
    OR NOT has_table_privilege(
        'svc_catalogo', 'inventario.producto', 'SELECT'
    ) THEN
        RAISE EXCEPTION
            'Privilegios de consulta del catálogo incompletos';
    END IF;

    IF NOT has_column_privilege(
        'svc_catalogo',
        'inventario.producto',
        'stock_minimo',
        'UPDATE'
    ) THEN
        RAISE EXCEPTION
            'svc_catalogo debe poder actualizar stock_minimo';
    END IF;

    -- MOVIMIENTOS.
    IF NOT has_table_privilege(
        'svc_movimientos', 'inventario.movimiento', 'SELECT'
    )
    OR NOT has_column_privilege(
        'svc_movimientos',
        'inventario.movimiento',
        'cantidad',
        'INSERT'
    ) THEN
        RAISE EXCEPTION
            'Privilegios de movimiento incompletos';
    END IF;

    IF NOT has_table_privilege(
        'svc_movimientos', 'inventario.producto', 'SELECT'
    )
    OR NOT has_table_privilege(
        'svc_movimientos', 'inventario.motivo_movimiento', 'SELECT'
    ) THEN
        RAISE EXCEPTION
            'Privilegios de consulta para movimientos incompletos';
    END IF;

    -- ANALÍTICA.
    IF NOT has_table_privilege(
        'svc_analitica', 'inventario.v_inventario', 'SELECT'
    )
    OR NOT has_table_privilege(
        'svc_analitica', 'inventario.v_alerta_stock', 'SELECT'
    )
    OR NOT has_table_privilege(
        'svc_analitica', 'inventario.v_kardex', 'SELECT'
    )
    OR NOT has_table_privilege(
        'svc_analitica', 'inventario.v_consumo_diario', 'SELECT'
    ) THEN
        RAISE EXCEPTION
            'Faltan privilegios SELECT sobre vistas analíticas';
    END IF;

    -- Las vistas usan security_invoker=true: el rol consultante
    -- también requiere SELECT en las tablas base referenciadas.
    IF NOT has_table_privilege(
        'svc_analitica', 'inventario.producto', 'SELECT'
    )
    OR NOT has_table_privilege(
        'svc_analitica', 'inventario.categoria', 'SELECT'
    )
    OR NOT has_table_privilege(
        'svc_analitica', 'inventario.unidad_medida', 'SELECT'
    )
    OR NOT has_table_privilege(
        'svc_analitica', 'inventario.movimiento', 'SELECT'
    )
    OR NOT has_table_privilege(
        'svc_analitica', 'inventario.motivo_movimiento', 'SELECT'
    ) THEN
        RAISE EXCEPTION
            'Faltan privilegios SELECT sobre tablas base de vistas analíticas';
    END IF;

    IF NOT has_table_privilege(
        'svc_analitica', 'inventario.proveedor', 'SELECT'
    ) THEN
        RAISE EXCEPTION
            'svc_analitica debe poder consultar proveedor';
    END IF;

    IF NOT has_function_privilege(
        'svc_analitica',
        'inventario.proveedores_cercanos(double precision,double precision,double precision)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'svc_analitica debe ejecutar proveedores_cercanos';
    END IF;
END;
$$;

-- 3. Pruebas negativas: privilegios directos no autorizados.
-- Se inspeccionan ACL de tabla y de columna. Una concesión a nivel
-- de tabla también permite la operación sobre sus columnas, por lo
-- que revisar únicamente attacl no sería suficiente.

DO $$
DECLARE
    v_rol_identidad oid;
    v_rol_catalogo oid;
    v_rol_movimientos oid;
    v_rol_analitica oid;
BEGIN
    SELECT oid INTO v_rol_identidad
    FROM pg_catalog.pg_roles
    WHERE rolname = 'svc_identidad';

    SELECT oid INTO v_rol_catalogo
    FROM pg_catalog.pg_roles
    WHERE rolname = 'svc_catalogo';

    SELECT oid INTO v_rol_movimientos
    FROM pg_catalog.pg_roles
    WHERE rolname = 'svc_movimientos';

    SELECT oid INTO v_rol_analitica
    FROM pg_catalog.pg_roles
    WHERE rolname = 'svc_analitica';

    -- IDENTIDAD no debe recibir SELECT directo sobre producto,
    -- ni a nivel de tabla ni mediante ACL de columna.
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class c
        CROSS JOIN LATERAL pg_catalog.aclexplode(c.relacl) a
        WHERE c.oid = 'inventario.producto'::regclass
          AND a.grantee = v_rol_identidad
          AND a.privilege_type = 'SELECT'
    )
    OR EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_attribute att
          ON att.attrelid = c.oid
        CROSS JOIN LATERAL pg_catalog.aclexplode(att.attacl) a
        WHERE c.oid = 'inventario.producto'::regclass
          AND att.attnum > 0
          AND NOT att.attisdropped
          AND a.grantee = v_rol_identidad
          AND a.privilege_type = 'SELECT'
    ) THEN
        RAISE EXCEPTION
            'svc_identidad no debe tener SELECT directo sobre producto';
    END IF;

    -- CATÁLOGO no debe actualizar stock_actual ni costo_promedio.
    -- Se comprueba UPDATE de tabla y UPDATE específico de columna.
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class c
        CROSS JOIN LATERAL pg_catalog.aclexplode(c.relacl) a
        WHERE c.oid = 'inventario.producto'::regclass
          AND a.grantee = v_rol_catalogo
          AND a.privilege_type = 'UPDATE'
    )
    OR EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_attribute att
          ON att.attrelid = c.oid
        CROSS JOIN LATERAL pg_catalog.aclexplode(att.attacl) a
        WHERE c.oid = 'inventario.producto'::regclass
          AND att.attname IN ('stock_actual', 'costo_promedio')
          AND att.attnum > 0
          AND NOT att.attisdropped
          AND a.grantee = v_rol_catalogo
          AND a.privilege_type = 'UPDATE'
    ) THEN
        RAISE EXCEPTION
            'svc_catalogo no debe actualizar stock_actual ni costo_promedio';
    END IF;

    -- CATÁLOGO no debe insertar movimientos, ni por ACL de tabla
    -- ni mediante privilegios INSERT concedidos por columna.
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class c
        CROSS JOIN LATERAL pg_catalog.aclexplode(c.relacl) a
        WHERE c.oid = 'inventario.movimiento'::regclass
          AND a.grantee = v_rol_catalogo
          AND a.privilege_type = 'INSERT'
    )
    OR EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_attribute att
          ON att.attrelid = c.oid
        CROSS JOIN LATERAL pg_catalog.aclexplode(att.attacl) a
        WHERE c.oid = 'inventario.movimiento'::regclass
          AND att.attnum > 0
          AND NOT att.attisdropped
          AND a.grantee = v_rol_catalogo
          AND a.privilege_type = 'INSERT'
    ) THEN
        RAISE EXCEPTION
            'svc_catalogo no debe insertar movimientos';
    END IF;

    -- CATÁLOGO no debe consultar proveedores, ni a nivel de tabla
    -- ni mediante privilegios SELECT por columna.
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class c
        CROSS JOIN LATERAL pg_catalog.aclexplode(c.relacl) a
        WHERE c.oid = 'inventario.proveedor'::regclass
          AND a.grantee = v_rol_catalogo
          AND a.privilege_type = 'SELECT'
    )
    OR EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_attribute att
          ON att.attrelid = c.oid
        CROSS JOIN LATERAL pg_catalog.aclexplode(att.attacl) a
        WHERE c.oid = 'inventario.proveedor'::regclass
          AND att.attnum > 0
          AND NOT att.attisdropped
          AND a.grantee = v_rol_catalogo
          AND a.privilege_type = 'SELECT'
    ) THEN
        RAISE EXCEPTION
            'svc_catalogo no debe consultar proveedor';
    END IF;

    -- MOVIMIENTOS no debe tener UPDATE sobre la tabla ni columnas,
    -- ni DELETE o TRUNCATE a nivel de tabla.
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class c
        CROSS JOIN LATERAL pg_catalog.aclexplode(c.relacl) a
        WHERE c.oid = 'inventario.movimiento'::regclass
          AND a.grantee = v_rol_movimientos
          AND a.privilege_type IN ('UPDATE', 'DELETE', 'TRUNCATE')
    )
    OR EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_attribute att
          ON att.attrelid = c.oid
        CROSS JOIN LATERAL pg_catalog.aclexplode(att.attacl) a
        WHERE c.oid = 'inventario.movimiento'::regclass
          AND att.attnum > 0
          AND NOT att.attisdropped
          AND a.grantee = v_rol_movimientos
          AND a.privilege_type = 'UPDATE'
    ) THEN
        RAISE EXCEPTION
            'svc_movimientos no debe modificar ni eliminar movimientos';
    END IF;

    -- ANALÍTICA no debe recibir privilegios de escritura sobre
    -- producto, ni a nivel de tabla ni mediante ACL por columna.
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class c
        CROSS JOIN LATERAL pg_catalog.aclexplode(c.relacl) a
        WHERE c.oid = 'inventario.producto'::regclass
          AND a.grantee = v_rol_analitica
          AND a.privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
    )
    OR EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_attribute att
          ON att.attrelid = c.oid
        CROSS JOIN LATERAL pg_catalog.aclexplode(att.attacl) a
        WHERE c.oid = 'inventario.producto'::regclass
          AND att.attnum > 0
          AND NOT att.attisdropped
          AND a.grantee = v_rol_analitica
          AND a.privilege_type IN ('INSERT', 'UPDATE')
    ) THEN
        RAISE EXCEPTION
            'svc_analitica debe ser de solo lectura sobre producto';
    END IF;

    -- Ningún rol de servicio debe tener USAGE directo en auditoria.
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_namespace n
        CROSS JOIN LATERAL pg_catalog.aclexplode(n.nspacl) a
        WHERE n.nspname = 'auditoria'
          AND a.grantee IN (
              v_rol_identidad,
              v_rol_catalogo,
              v_rol_movimientos,
              v_rol_analitica
          )
          AND a.privilege_type = 'USAGE'
    ) THEN
        RAISE EXCEPTION
            'Los roles de servicio no deben tener USAGE directo en auditoria';
    END IF;
END;
$$;

-- 4. Las pruebas son de solo verificación.
-- Se revierten al finalizar.

ROLLBACK;