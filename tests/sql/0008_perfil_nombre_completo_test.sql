
-- ============================================================================
-- B5/B6 - PRUEBAS DE NOMBRE COMPLETO EN SEGURIDAD.PERFIL
-- Proyecto: Spa de Unas - Inventario
--
-- Criterios de aceptacion:
-- 1. La columna nombre_completo existe y es varchar(120).
-- 2. La columna es NOT NULL.
-- 3. Se aceptan nombres con longitud entre 3 y 120 caracteres.
-- 4. Se rechazan nombres vacios o con menos de 3 caracteres.
-- 5. Se rechazan nombres con mas de 120 caracteres.
--
-- Todas las operaciones de prueba se deshacen mediante ROLLBACK.
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_usuario_id uuid;
    v_nombre_valido text;
    v_rechazado boolean;
    v_longitud integer;
BEGIN

    -- =========================================================================
    -- B5/B6-01: Verificar la definicion de la columna.
    -- =========================================================================

    ASSERT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'seguridad'
          AND table_name = 'perfil'
          AND column_name = 'nombre_completo'
          AND data_type = 'character varying'
          AND character_maximum_length = 120
          AND is_nullable = 'NO'
    ), 'B5/B6-01: nombre_completo debe ser varchar(120) NOT NULL';

    -- =========================================================================
    -- B5/B6-02: Verificar la restriccion de longitud minima.
    -- =========================================================================

    ASSERT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'seguridad.perfil'::regclass
          AND conname = 'perfil_nombre_completo_chk'
          AND contype = 'c'
    ), 'B5/B6-02: falta la restriccion de nombre_completo';

    -- =========================================================================
    -- B5/B6-03: Crear un usuario ficticio para las pruebas.
    -- =========================================================================

    v_usuario_id := gen_random_uuid();

    INSERT INTO auth.users (
        id,
        email
    )
    VALUES (
        v_usuario_id,
        v_usuario_id::text || '@b5b6.test'
    );

    -- =========================================================================
    -- B5/B6-04: Aceptar un nombre con la longitud minima de 3 caracteres.
    -- =========================================================================

    INSERT INTO seguridad.perfil (
        usuario_id,
        rol_id,
        nombre_completo
    )
    VALUES (
        v_usuario_id,
        1,
        'Ana'
    );

    SELECT char_length(nombre_completo)
    INTO v_longitud
    FROM seguridad.perfil
    WHERE usuario_id = v_usuario_id;

    ASSERT v_longitud = 3,
        'B5/B6-04: debe aceptar nombres de exactamente 3 caracteres';

    -- =========================================================================
    -- B5/B6-05: Aceptar un nombre con la longitud maxima de 120 caracteres.
    -- =========================================================================

    v_nombre_valido := repeat('A', 120);

    UPDATE seguridad.perfil
    SET nombre_completo = v_nombre_valido
    WHERE usuario_id = v_usuario_id;

    ASSERT (
        SELECT char_length(nombre_completo) = 120
        FROM seguridad.perfil
        WHERE usuario_id = v_usuario_id
    ), 'B5/B6-05: debe aceptar nombres de exactamente 120 caracteres';

    -- =========================================================================
    -- B5/B6-06: Rechazar un nombre vacio.
    -- =========================================================================

    v_rechazado := false;

    BEGIN
        UPDATE seguridad.perfil
        SET nombre_completo = ''
        WHERE usuario_id = v_usuario_id;
    EXCEPTION
        WHEN check_violation THEN
            v_rechazado := true;
    END;

    ASSERT v_rechazado,
        'B5/B6-06: debe rechazar nombres vacios';

    -- =========================================================================
    -- B5/B6-07: Rechazar un nombre compuesto por espacios.
    -- =========================================================================

    v_rechazado := false;

    BEGIN
        UPDATE seguridad.perfil
        SET nombre_completo = '   '
        WHERE usuario_id = v_usuario_id;
    EXCEPTION
        WHEN check_violation THEN
            v_rechazado := true;
    END;

    ASSERT v_rechazado,
        'B5/B6-07: debe rechazar nombres compuestos por espacios';

    -- =========================================================================
    -- B5/B6-08: Rechazar un nombre de menos de 3 caracteres.
    -- =========================================================================

    v_rechazado := false;

    BEGIN
        UPDATE seguridad.perfil
        SET nombre_completo = 'AB'
        WHERE usuario_id = v_usuario_id;
    EXCEPTION
        WHEN check_violation THEN
            v_rechazado := true;
    END;

    ASSERT v_rechazado,
        'B5/B6-08: debe rechazar nombres de menos de 3 caracteres';

    -- =========================================================================
    -- B5/B6-09: Rechazar un nombre de mas de 120 caracteres.
    -- =========================================================================

    v_rechazado := false;

    BEGIN
        UPDATE seguridad.perfil
        SET nombre_completo = repeat('A', 121)
        WHERE usuario_id = v_usuario_id;
    EXCEPTION
        WHEN string_data_right_truncation THEN
            v_rechazado := true;
    END;

    ASSERT v_rechazado,
        'B5/B6-09: debe rechazar nombres de mas de 120 caracteres';

    -- =========================================================================
    -- Resultado final.
    -- =========================================================================

    RAISE NOTICE '==============================================';
    RAISE NOTICE '0008_perfil_nombre_completo_test: TODAS LAS PRUEBAS OK';
    RAISE NOTICE 'Columna varchar(120) NOT NULL: verificada';
    RAISE NOTICE 'Longitud minima de 3 caracteres: verificada';
    RAISE NOTICE 'Nombre de 3 caracteres: aceptado';
    RAISE NOTICE 'Nombre de 120 caracteres: aceptado';
    RAISE NOTICE 'Nombre vacio: rechazado';
    RAISE NOTICE 'Nombre con espacios: rechazado';
    RAISE NOTICE 'Nombre de 2 caracteres: rechazado';
    RAISE NOTICE 'Nombre de 121 caracteres: rechazado';
    RAISE NOTICE '==============================================';

END $$;

ROLLBACK;