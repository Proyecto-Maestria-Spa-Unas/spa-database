-- ============================================================================
-- D12: PRUEBAS DE PROVEEDORES GEORREFERENCIADOS Y MOTIVOS DE MOVIMIENTO
-- Proyecto: Spa de Uñas - Inventario
--
-- Criterios:
-- 1. Estructura y restricciones de proveedores.
-- 2. Unicidad del NIT y campos opcionales.
-- 3. Búsqueda georreferenciada y validación de parámetros.
-- 4. Seguridad RLS y permisos de proveedores.
-- 5. Motivos de movimiento y clasificación ENTRADA/SALIDA.
--
-- Todas las operaciones se revierten mediante ROLLBACK.
-- ============================================================================

BEGIN;

-- ============================================================================
-- PRUEBA 1: ESTRUCTURA DE LAS TABLAS Y POLÍTICAS RLS
-- ============================================================================

DO $$
BEGIN

    ASSERT to_regclass('inventario.proveedor') IS NOT NULL,
        'D12-01: no existe inventario.proveedor';

    ASSERT to_regclass('inventario.motivo_movimiento') IS NOT NULL,
        'D12-01: no existe inventario.motivo_movimiento';

    ASSERT (
        SELECT COUNT(*) = 2
        FROM pg_class
        WHERE oid IN (
            'inventario.proveedor'::regclass,
            'inventario.motivo_movimiento'::regclass
        )
        AND relrowsecurity = true
    ), 'D12-01: RLS debe estar habilitado en ambas tablas';

    ASSERT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'inventario'
          AND table_name = 'motivo_movimiento'
          AND column_name = 'id'
    ), 'D12-01: falta columna id en motivo_movimiento';

    ASSERT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'inventario'
          AND table_name = 'motivo_movimiento'
          AND column_name = 'nombre'
    ), 'D12-01: falta columna nombre';

    ASSERT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'inventario'
          AND table_name = 'motivo_movimiento'
          AND column_name = 'aplica_a'
    ), 'D12-01: falta columna aplica_a';

    ASSERT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'inventario'
          AND table_name = 'proveedor'
          AND column_name = 'direccion'
          AND is_nullable = 'YES'
    ), 'D12-01: direccion debe aceptar NULL';

    ASSERT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'inventario'
          AND table_name = 'proveedor'
          AND column_name = 'ubicacion'
          AND is_nullable = 'YES'
    ), 'D12-01: ubicacion debe aceptar NULL';

    ASSERT (
        SELECT COUNT(*) = 4
        FROM pg_policies
        WHERE schemaname = 'inventario'
          AND (
              policyname = 'proveedor_consultar'
              OR policyname = 'proveedor_crear'
              OR policyname = 'proveedor_actualizar'
              OR policyname = 'motivo_movimiento_consultar'
          )
    ), 'D12-01: faltan políticas RLS de D12';

    RAISE NOTICE 'D12-01 OK: estructura y políticas RLS';

END;
$$;


-- ============================================================================
-- PRUEBA 2: UNICIDAD DEL NIT Y CAMPOS OPCIONALES
-- ============================================================================

DO $$
DECLARE
    v_nit text;
    v_duplicado boolean := false;
BEGIN

    ASSERT current_user = 'postgres',
        'D12-02: ejecutar como postgres';

    v_nit := 'D12-' || substr(gen_random_uuid()::text, 1, 20);

    -- Crear proveedor sin dirección ni ubicación.
    INSERT INTO inventario.proveedor (
        nit,
        nombre
    )
    VALUES (
        v_nit,
        'Proveedor prueba D12'
    );

    ASSERT EXISTS (
        SELECT 1
        FROM inventario.proveedor
        WHERE nit = v_nit
          AND direccion IS NULL
          AND ubicacion IS NULL
    ), 'D12-02: el proveedor debe aceptar direccion y ubicacion NULL';

    -- Intentar registrar el mismo NIT.
    BEGIN

        INSERT INTO inventario.proveedor (
            nit,
            nombre
        )
        VALUES (
            v_nit,
            'Proveedor duplicado D12'
        );

    EXCEPTION
        WHEN unique_violation THEN
            v_duplicado := true;
    END;

    ASSERT v_duplicado,
        'D12-02: debe rechazarse un NIT duplicado';

    RAISE NOTICE 'D12-02 OK: NIT único y campos opcionales';

END;
$$;


-- ============================================================================
-- PRUEBA 3: FUNCIÓN DE PROVEEDORES CERCANOS
-- ============================================================================

DO $$
DECLARE
    v_total integer;
    v_distancia double precision;
    v_anterior double precision := -1;
    v_bloqueado boolean;
BEGIN

    -- Verificar resultados dentro de un radio de 3 km en Bogotá.
    SELECT COUNT(*)
    INTO v_total
    FROM inventario.proveedores_cercanos(
        4.648,
        -74.062,
        3
    );

    ASSERT v_total >= 2,
        'D12-03: se esperaban al menos dos proveedores cercanos en los datos de prueba';

    -- Verificar orden ascendente por distancia.
    FOR v_distancia IN
        SELECT distancia_km
        FROM inventario.proveedores_cercanos(
            4.648,
            -74.062,
            3
        )
    LOOP

        ASSERT v_distancia >= v_anterior,
            'D12-03: los proveedores no están ordenados por distancia';

        v_anterior := v_distancia;

    END LOOP;

    -- Latitud fuera de rango.
    v_bloqueado := false;

    BEGIN
        PERFORM *
        FROM inventario.proveedores_cercanos(
            91,
            -74.062,
            3
        );
    EXCEPTION
        WHEN raise_exception THEN
            v_bloqueado := true;
    END;

    ASSERT v_bloqueado,
        'D12-03: debe rechazarse una latitud inválida';

    -- Longitud fuera de rango.
    v_bloqueado := false;

    BEGIN
        PERFORM *
        FROM inventario.proveedores_cercanos(
            4.648,
            181,
            3
        );
    EXCEPTION
        WHEN raise_exception THEN
            v_bloqueado := true;
    END;

    ASSERT v_bloqueado,
        'D12-03: debe rechazarse una longitud inválida';

    -- Radio igual a cero.
    v_bloqueado := false;

    BEGIN
        PERFORM *
        FROM inventario.proveedores_cercanos(
            4.648,
            -74.062,
            0
        );
    EXCEPTION
        WHEN raise_exception THEN
            v_bloqueado := true;
    END;

    ASSERT v_bloqueado,
        'D12-03: debe rechazarse un radio igual a cero';

    -- Radio negativo.
    v_bloqueado := false;

    BEGIN
        PERFORM *
        FROM inventario.proveedores_cercanos(
            4.648,
            -74.062,
            -1
        );
    EXCEPTION
        WHEN raise_exception THEN
            v_bloqueado := true;
    END;

    ASSERT v_bloqueado,
        'D12-03: debe rechazarse un radio negativo';

    RAISE NOTICE 'D12-03 OK: búsqueda, distancia y validaciones';

END;
$$;


-- ============================================================================
-- PREPARACIÓN: USUARIO TEMPORAL SIN PERMISOS
-- ============================================================================

DO $$
DECLARE
    v_rol_id seguridad.rol.id%TYPE;
    v_usuario_id uuid;
BEGIN

    INSERT INTO seguridad.rol (
        codigo,
        nombre,
        descripcion
    )
    VALUES (
        'DTEST_ROLE',
        'Rol temporal prueba D12',
        'Rol sin permisos para validar RLS de proveedores'
    )
    ON CONFLICT (codigo) DO NOTHING;

    SELECT id
    INTO v_rol_id
    FROM seguridad.rol
    WHERE codigo = 'DTEST_ROLE';

    ASSERT v_rol_id IS NOT NULL,
        'D12-04: no se pudo crear el rol temporal';

    -- Crear usuario temporal.
    v_usuario_id := gen_random_uuid();

    INSERT INTO auth.users (
        id,
        email
    )
    VALUES (
        v_usuario_id,
        v_usuario_id::text || '@d12.test'
    );

    INSERT INTO seguridad.perfil (
        usuario_id,
        rol_id,
        nombre_completo,
        activo
    )
    VALUES (
        v_usuario_id,
        v_rol_id,
        'Usuario temporal D12',
        true
    );

    PERFORM set_config(
        'test.d12.user_id',
        v_usuario_id::text,
        true
    );

    RAISE NOTICE 'D12-04: usuario temporal preparado';

END;
$$;


-- ============================================================================
-- PRUEBA 4: RLS PARA CONSULTA Y CREACIÃ“N DE PROVEEDORES
-- ============================================================================

SELECT set_config(
    'request.jwt.claim.role',
    'authenticated',
    true
);

SELECT set_config(
    'request.jwt.claim.sub',
    current_setting('test.d12.user_id'),
    true
);

SET LOCAL ROLE authenticated;

DO $$
DECLARE
    v_total integer;
    v_bloqueado boolean := false;
BEGIN

    ASSERT auth.role() = 'authenticated',
        'D12-04: el rol debe ser authenticated';

    ASSERT auth.uid() IS NOT NULL,
        'D12-04: debe existir un usuario autenticado';

    ASSERT NOT seguridad.tiene_permiso('producto.consultar'),
        'D12-04: el usuario no debe tener producto.consultar';

    ASSERT NOT seguridad.tiene_permiso('catalogo.administrar'),
        'D12-04: el usuario no debe tener catalogo.administrar';

    -- Sin permiso de consulta no debe visualizar proveedores.
    SELECT COUNT(*)
    INTO v_total
    FROM inventario.proveedor;

    ASSERT v_total = 0,
        'D12-04: RLS permitió consultar proveedores sin permiso';

    -- Sin permiso administrativo no debe crear proveedores.
    BEGIN

        INSERT INTO inventario.proveedor (
            nit,
            nombre
        )
        VALUES (
            'D12-BLOQUEADO',
            'Proveedor no autorizado'
        );

    EXCEPTION
        WHEN insufficient_privilege THEN
            v_bloqueado := true;
    END;

    ASSERT v_bloqueado,
        'D12-04: RLS permitió crear proveedor sin catalogo.administrar';

    RAISE NOTICE 'D12-04 OK: restricciones RLS de proveedores';

END;
$$;

RESET ROLE;


-- ============================================================================
-- PRUEBA 5: SEIS MOTIVOS DE MOVIMIENTO Y SU CLASIFICACIÓN
-- ============================================================================

DO $$
DECLARE
    v_total integer;
BEGIN

    SELECT COUNT(*)
    INTO v_total
    FROM inventario.motivo_movimiento;

    ASSERT v_total = 6,
        'D12-05: deben existir exactamente seis motivos de movimiento';

    ASSERT (
        SELECT COUNT(*) = 3
        FROM inventario.motivo_movimiento
        WHERE aplica_a = 'ENTRADA'
          AND codigo IN (
              'COMPRA',
              'AJUSTE_CONTEO',
              'SALDO_INICIAL'
          )
    ), 'D12-05: clasificación incorrecta de motivos de entrada';

    ASSERT (
        SELECT COUNT(*) = 3
        FROM inventario.motivo_movimiento
        WHERE aplica_a = 'SALIDA'
          AND codigo IN (
              'CONSUMO_SERVICIO',
              'MERMA',
              'VENCIMIENTO'
          )
    ), 'D12-05: clasificación incorrecta de motivos de salida';

    ASSERT (
        SELECT COUNT(*) = 6
        FROM inventario.motivo_movimiento
        WHERE nombre IS NOT NULL
          AND aplica_a IN ('ENTRADA', 'SALIDA')
    ), 'D12-05: existen motivos sin nombre o clasificación válida';

    RAISE NOTICE 'D12-05 OK: seis motivos y clasificación correcta';

END;
$$;


-- ============================================================================
-- RESULTADO FINAL
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '==============================================';
    RAISE NOTICE '0009_proveedores_motivos_test: VALIDACIONES OK';
    RAISE NOTICE 'D12-01: estructura y politicas RLS';
    RAISE NOTICE 'D12-02: NIT unico y campos opcionales';
    RAISE NOTICE 'D12-03: busqueda georreferenciada';
    RAISE NOTICE 'D12-04: permisos de proveedores';
    RAISE NOTICE 'D12-05: motivos de movimiento';
    RAISE NOTICE '==============================================';
END;
$$;

ROLLBACK;