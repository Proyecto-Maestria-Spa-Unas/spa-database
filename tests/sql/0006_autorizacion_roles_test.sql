
-- ============================================================================
-- D6 - PRUEBAS FUNCIONALES DE AUTORIZACION POR ROLES
-- Proyecto: Spa de Uñas - Inventario
--
-- Roles evaluados:
--   ADMINISTRADOR
--   MANICURISTA
--   GERENTE
--
-- Todas las operaciones se ejecutan en una transaccion reversible.
-- Entorno: Supabase local Docker.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. CREAR USUARIOS TEMPORALES
-- ============================================================================

INSERT INTO auth.users (
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    is_sso_user,
    is_anonymous
)
VALUES
(
    'd6000000-0000-4000-8000-000000000001',
    'authenticated',
    'authenticated',
    'd6.admin@spa.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now(),
    false,
    false
),
(
    'd6000000-0000-4000-8000-000000000002',
    'authenticated',
    'authenticated',
    'd6.manicurista@spa.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now(),
    false,
    false
),
(
    'd6000000-0000-4000-8000-000000000003',
    'authenticated',
    'authenticated',
    'd6.gerente@spa.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now(),
    false,
    false
);

-- ============================================================================
-- 2. ASIGNAR PERFILES
-- ============================================================================

INSERT INTO seguridad.perfil (usuario_id, rol_id)
SELECT usuarios.usuario_id, roles.id
FROM (
    VALUES
        ('d6000000-0000-4000-8000-000000000001'::uuid, 'ADMINISTRADOR'),
        ('d6000000-0000-4000-8000-000000000002'::uuid, 'MANICURISTA'),
        ('d6000000-0000-4000-8000-000000000003'::uuid, 'GERENTE')
) AS usuarios(usuario_id, rol_codigo)
JOIN seguridad.rol AS roles
    ON roles.codigo = usuarios.rol_codigo;

-- ============================================================================
-- 3. PRUEBAS COMO AUTHENTICATED
-- ============================================================================

SET LOCAL ROLE authenticated;

DO $$
DECLARE
    v_admin uuid := 'd6000000-0000-4000-8000-000000000001';
    v_manicurista uuid := 'd6000000-0000-4000-8000-000000000002';
    v_gerente uuid := 'd6000000-0000-4000-8000-000000000003';

    v_producto_id uuid;
    v_categoria_id integer;
    v_filas integer;
    v_total integer;
BEGIN

    RAISE NOTICE '==========================================';
    RAISE NOTICE 'INICIO DE PRUEBAS FUNCIONALES D6';
    RAISE NOTICE '==========================================';

    -- ------------------------------------------------------------------------
    -- D6-F01: ADMINISTRADOR - PERMISOS
    -- ------------------------------------------------------------------------

    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object(
            'sub', v_admin,
            'role', 'authenticated'
        )::text,
        true
    );

    IF NOT seguridad.tiene_permiso('producto.consultar')
       OR NOT seguridad.tiene_permiso('producto.crear')
       OR NOT seguridad.tiene_permiso('producto.editar')
       OR NOT seguridad.tiene_permiso('producto.configurar_minimo')
       OR NOT seguridad.tiene_permiso('producto.descontinuar')
       OR NOT seguridad.tiene_permiso('catalogo.administrar')
    THEN
        RAISE EXCEPTION 'D6-F01: permisos del ADMINISTRADOR incorrectos';
    END IF;

    RAISE NOTICE 'D6-F01 OK: permisos del ADMINISTRADOR';

    -- ------------------------------------------------------------------------
    -- D6-F02: ADMINISTRADOR - CREAR PRODUCTO
    -- ------------------------------------------------------------------------

    INSERT INTO inventario.producto (
        codigo,
        nombre,
        descripcion,
        categoria_id,
        unidad_medida_id,
        stock_actual,
        stock_minimo,
        costo_promedio
    )
    VALUES (
        'D6-ROLES-001',
        'Producto temporal D6 roles',
        'Producto para pruebas funcionales de autorizacion',
        1,
        1,
        10,
        3,
        2500
    )
    RETURNING id INTO v_producto_id;

    IF v_producto_id IS NULL THEN
        RAISE EXCEPTION 'D6-F02: no se pudo crear el producto';
    END IF;

    RAISE NOTICE 'D6-F02 OK: ADMINISTRADOR crea productos';

    -- ------------------------------------------------------------------------
    -- D6-F03: ADMINISTRADOR - MODIFICAR INFORMACION
    -- ------------------------------------------------------------------------

    UPDATE inventario.producto
    SET nombre = 'Producto temporal D6 actualizado'
    WHERE id = v_producto_id;

    GET DIAGNOSTICS v_filas = ROW_COUNT;

    IF v_filas <> 1 THEN
        RAISE EXCEPTION 'D6-F03: administrador no pudo editar producto';
    END IF;

    RAISE NOTICE 'D6-F03 OK: edicion de producto';

    -- ------------------------------------------------------------------------
    -- D6-F04: ADMINISTRADOR - CONFIGURAR STOCK MINIMO
    -- ------------------------------------------------------------------------

    UPDATE inventario.producto
    SET stock_minimo = 5
    WHERE id = v_producto_id;

    GET DIAGNOSTICS v_filas = ROW_COUNT;

    IF v_filas <> 1 THEN
        RAISE EXCEPTION 'D6-F04: administrador no pudo configurar minimo';
    END IF;

    RAISE NOTICE 'D6-F04 OK: configuracion de stock minimo';

    -- ------------------------------------------------------------------------
    -- D6-F05: ADMINISTRADOR - DESCONTINUAR PRODUCTO
    -- ------------------------------------------------------------------------

    UPDATE inventario.producto
    SET descontinuado = true
    WHERE id = v_producto_id;

    GET DIAGNOSTICS v_filas = ROW_COUNT;

    IF v_filas <> 1 THEN
        RAISE EXCEPTION 'D6-F05: administrador no pudo descontinuar';
    END IF;

    -- Restablecer el estado para las siguientes pruebas.
    UPDATE inventario.producto
    SET descontinuado = false
    WHERE id = v_producto_id;

    RAISE NOTICE 'D6-F05 OK: descontinuacion de producto';

    -- ------------------------------------------------------------------------
    -- D6-F06: ADMINISTRADOR - CREAR CATEGORIA
    -- ------------------------------------------------------------------------

    INSERT INTO inventario.categoria (
        nombre,
        descripcion,
        orden,
        activa
    )
    VALUES (
        'D6 Roles temporal',
        'Categoria temporal para pruebas D6',
        99,
        true
    )
    RETURNING id INTO v_categoria_id;

    IF v_categoria_id IS NULL THEN
        RAISE EXCEPTION 'D6-F06: administrador no pudo crear categoria';
    END IF;

    RAISE NOTICE 'D6-F06 OK: creacion de categoria';

    -- ------------------------------------------------------------------------
    -- D6-F07: MANICURISTA - CONSULTAR PRODUCTOS
    -- ------------------------------------------------------------------------

    PERFORM set_config('request.jwt.claim.sub', v_manicurista::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object(
            'sub', v_manicurista,
            'role', 'authenticated'
        )::text,
        true
    );

    IF NOT seguridad.tiene_permiso('producto.consultar') THEN
        RAISE EXCEPTION 'D6-F07: manicurista no puede consultar';
    END IF;

    SELECT COUNT(*) INTO v_total
    FROM inventario.producto
    WHERE id = v_producto_id;

    IF v_total <> 1 THEN
        RAISE EXCEPTION 'D6-F07: manicurista no ve el producto';
    END IF;

    RAISE NOTICE 'D6-F07 OK: consulta del MANICURISTA';

    -- ------------------------------------------------------------------------
    -- D6-F08: MANICURISTA - NO CREAR PRODUCTOS
    -- ------------------------------------------------------------------------

    IF seguridad.tiene_permiso('producto.crear') THEN
        RAISE EXCEPTION 'D6-F08: manicurista tiene permiso de creacion';
    END IF;

    BEGIN
        INSERT INTO inventario.producto (
            codigo,
            nombre,
            categoria_id,
            unidad_medida_id
        )
        VALUES (
            'D6-ROLES-002',
            'Producto no autorizado',
            1,
            1
        );

        RAISE EXCEPTION 'D6-F08: manicurista pudo crear producto';

    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE 'D6-F08 OK: creacion de producto denegada';
    END;

    -- ------------------------------------------------------------------------
    -- D6-F09: MANICURISTA - NO EDITAR PRODUCTOS
    -- ------------------------------------------------------------------------

    IF seguridad.tiene_permiso('producto.editar') THEN
        RAISE EXCEPTION 'D6-F09: permiso de edicion incorrecto';
    END IF;

    UPDATE inventario.producto
    SET nombre = 'Cambio no autorizado'
    WHERE id = v_producto_id;

    GET DIAGNOSTICS v_filas = ROW_COUNT;

    IF v_filas <> 0 THEN
        RAISE EXCEPTION 'D6-F09: manicurista modifico el producto';
    END IF;

    RAISE NOTICE 'D6-F09 OK: edicion denegada';

    -- ------------------------------------------------------------------------
    -- D6-F10: MANICURISTA - NO CONFIGURAR STOCK MINIMO
    -- ------------------------------------------------------------------------

    IF seguridad.tiene_permiso('producto.configurar_minimo') THEN
        RAISE EXCEPTION 'D6-F10: permiso de stock minimo incorrecto';
    END IF;

    UPDATE inventario.producto
    SET stock_minimo = 8
    WHERE id = v_producto_id;

    GET DIAGNOSTICS v_filas = ROW_COUNT;

    IF v_filas <> 0 THEN
        RAISE EXCEPTION 'D6-F10: manicurista modifico stock minimo';
    END IF;

    RAISE NOTICE 'D6-F10 OK: configuracion de stock denegada';

    -- ------------------------------------------------------------------------
    -- D6-F11: MANICURISTA - NO DESCONTINUAR PRODUCTOS
    -- ------------------------------------------------------------------------

    IF seguridad.tiene_permiso('producto.descontinuar') THEN
        RAISE EXCEPTION 'D6-F11: permiso de descontinuacion incorrecto';
    END IF;

    UPDATE inventario.producto
    SET descontinuado = true
    WHERE id = v_producto_id;

    GET DIAGNOSTICS v_filas = ROW_COUNT;

    IF v_filas <> 0 THEN
        RAISE EXCEPTION 'D6-F11: manicurista descontinuo producto';
    END IF;

    RAISE NOTICE 'D6-F11 OK: descontinuacion denegada';

    -- ------------------------------------------------------------------------
    -- D6-F12: MANICURISTA - NO ADMINISTRAR CATEGORIAS
    -- ------------------------------------------------------------------------

    IF seguridad.tiene_permiso('catalogo.administrar') THEN
        RAISE EXCEPTION 'D6-F12: permiso de catalogo incorrecto';
    END IF;

    BEGIN
        INSERT INTO inventario.categoria (nombre, orden)
        VALUES ('D6 Manicurista no autorizado', 100);

        RAISE EXCEPTION 'D6-F12: manicurista creo categoria';

    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE 'D6-F12 OK: administracion de categorias denegada';
    END;

    -- ------------------------------------------------------------------------
    -- D6-F13: GERENTE - PERMISOS DE CONSULTA
    -- ------------------------------------------------------------------------

    PERFORM set_config('request.jwt.claim.sub', v_gerente::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object(
            'sub', v_gerente,
            'role', 'authenticated'
        )::text,
        true
    );

    IF NOT seguridad.tiene_permiso('producto.consultar') THEN
        RAISE EXCEPTION 'D6-F13: gerente no puede consultar';
    END IF;

    SELECT COUNT(*) INTO v_total
    FROM inventario.producto
    WHERE id = v_producto_id;

    IF v_total <> 1 THEN
        RAISE EXCEPTION 'D6-F13: gerente no ve el producto';
    END IF;

    RAISE NOTICE 'D6-F13 OK: consulta del GERENTE';

    -- ------------------------------------------------------------------------
    -- D6-F14: GERENTE - NO CREAR PRODUCTOS
    -- ------------------------------------------------------------------------

    IF seguridad.tiene_permiso('producto.crear') THEN
        RAISE EXCEPTION 'D6-F14: gerente tiene permiso de creacion';
    END IF;

    BEGIN
        INSERT INTO inventario.producto (
            codigo,
            nombre,
            categoria_id,
            unidad_medida_id
        )
        VALUES (
            'D6-ROLES-003',
            'Producto gerente no autorizado',
            1,
            1
        );

        RAISE EXCEPTION 'D6-F14: gerente pudo crear producto';

    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE 'D6-F14 OK: creacion denegada al GERENTE';
    END;

    -- ------------------------------------------------------------------------
    -- D6-F15: GERENTE - NO MODIFICAR PRODUCTOS
    -- ------------------------------------------------------------------------

    IF seguridad.tiene_permiso('producto.editar') THEN
        RAISE EXCEPTION 'D6-F15: gerente tiene permiso de edicion';
    END IF;

    UPDATE inventario.producto
    SET nombre = 'Cambio gerente no autorizado'
    WHERE id = v_producto_id;

    GET DIAGNOSTICS v_filas = ROW_COUNT;

    IF v_filas <> 0 THEN
        RAISE EXCEPTION 'D6-F15: gerente modifico producto';
    END IF;

    RAISE NOTICE 'D6-F15 OK: edicion denegada al GERENTE';

    -- ------------------------------------------------------------------------
    -- D6-F16: GERENTE - NO CONFIGURAR STOCK MINIMO
    -- ------------------------------------------------------------------------

    IF seguridad.tiene_permiso('producto.configurar_minimo') THEN
        RAISE EXCEPTION 'D6-F16: gerente tiene permiso de stock minimo';
    END IF;

    UPDATE inventario.producto
    SET stock_minimo = 9
    WHERE id = v_producto_id;

    GET DIAGNOSTICS v_filas = ROW_COUNT;

    IF v_filas <> 0 THEN
        RAISE EXCEPTION 'D6-F16: gerente modifico stock minimo';
    END IF;

    RAISE NOTICE 'D6-F16 OK: stock minimo denegado al GERENTE';

    -- ------------------------------------------------------------------------
    -- D6-F17: GERENTE - NO DESCONTINUAR PRODUCTOS
    -- ------------------------------------------------------------------------

    IF seguridad.tiene_permiso('producto.descontinuar') THEN
        RAISE EXCEPTION 'D6-F17: gerente tiene permiso de descontinuacion';
    END IF;

    UPDATE inventario.producto
    SET descontinuado = true
    WHERE id = v_producto_id;

    GET DIAGNOSTICS v_filas = ROW_COUNT;

    IF v_filas <> 0 THEN
        RAISE EXCEPTION 'D6-F17: gerente descontinuo producto';
    END IF;

    RAISE NOTICE 'D6-F17 OK: descontinuacion denegada al GERENTE';

    -- ------------------------------------------------------------------------
    -- D6-F18: GERENTE - NO ADMINISTRAR CATEGORIAS
    -- ------------------------------------------------------------------------

    IF seguridad.tiene_permiso('catalogo.administrar') THEN
        RAISE EXCEPTION 'D6-F18: gerente tiene permiso de catalogo';
    END IF;

    BEGIN
        INSERT INTO inventario.categoria (nombre, orden)
        VALUES ('D6 Gerente no autorizado', 101);

        RAISE EXCEPTION 'D6-F18: gerente creo categoria';

    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE 'D6-F18 OK: administracion de categorias denegada';
    END;

    -- ------------------------------------------------------------------------
    -- D6-F19: GERENTE - CONSULTAR VISTAS
    -- ------------------------------------------------------------------------

    SELECT COUNT(*) INTO v_total
    FROM inventario.v_inventario
    WHERE id = v_producto_id;

    IF v_total <> 1 THEN
        RAISE EXCEPTION 'D6-F19: gerente no puede consultar v_inventario';
    END IF;

    RAISE NOTICE 'D6-F19 OK: consulta de vista de inventario';

    RAISE NOTICE '==========================================';
    RAISE NOTICE '0006_autorizacion_roles_test: TODAS LAS PRUEBAS OK';
    RAISE NOTICE 'Administrador: permisos de escritura verificados';
    RAISE NOTICE 'Manicurista: consulta y restricciones verificadas';
    RAISE NOTICE 'Gerente: consulta y restricciones verificadas';
    RAISE NOTICE '==========================================';

END $$;

-- ============================================================================
-- 4. REVERTIR TODOS LOS DATOS TEMPORALES
-- ============================================================================

RESET ROLE;

ROLLBACK;
