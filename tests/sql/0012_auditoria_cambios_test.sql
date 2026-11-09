-- ============================================================================
-- D8 - AUDIT TESTS
-- Issue #17
-- File: tests/sql/0012_auditoria_cambios_test.sql
--
-- IMPORTANT:
-- This file only executes tests.
-- It does not create or modify the audit schema or its objects.
-- Migration 20261108090000_auditoria_cambios.sql must be applied.
-- All test data is rolled back at the end.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. VALIDATE STRUCTURE AND PRIVILEGES
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('auditoria.registro_cambio') IS NULL THEN
    RAISE EXCEPTION 'D8: auditoria.registro_cambio does not exist';
  END IF;

  IF NOT has_table_privilege(
    'service_role',
    'auditoria.registro_cambio',
    'SELECT'
  ) THEN
    RAISE EXCEPTION 'D8: service_role must have SELECT';
  END IF;

  IF has_table_privilege(
    'authenticated',
    'auditoria.registro_cambio',
    'SELECT'
  ) THEN
    RAISE EXCEPTION 'D8: authenticated must not have SELECT';
  END IF;

  IF has_table_privilege(
    'authenticated',
    'auditoria.registro_cambio',
    'INSERT'
  ) THEN
    RAISE EXCEPTION 'D8: authenticated must not have INSERT';
  END IF;

  IF has_table_privilege(
    'service_role',
    'auditoria.registro_cambio',
    'INSERT'
  ) THEN
    RAISE EXCEPTION 'D8: service_role must not have INSERT';
  END IF;

  IF has_table_privilege(
    'service_role',
    'auditoria.registro_cambio',
    'UPDATE'
  ) THEN
    RAISE EXCEPTION 'D8: service_role must not have UPDATE';
  END IF;

  IF has_table_privilege(
    'service_role',
    'auditoria.registro_cambio',
    'DELETE'
  ) THEN
    RAISE EXCEPTION 'D8: service_role must not have DELETE';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'trg_auditoria_producto'
      AND NOT tgisinternal
      AND tgenabled <> 'D'
  ) THEN
    RAISE EXCEPTION 'D8: product audit trigger is missing or disabled';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'trg_auditoria_proveedor'
      AND NOT tgisinternal
      AND tgenabled <> 'D'
  ) THEN
    RAISE EXCEPTION 'D8: provider audit trigger is missing or disabled';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'trg_auditoria_perfil'
      AND NOT tgisinternal
      AND tgenabled <> 'D'
  ) THEN
    RAISE EXCEPTION 'D8: profile audit trigger is missing or disabled';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'trg_auditoria_categoria'
      AND NOT tgisinternal
      AND tgenabled <> 'D'
  ) THEN
    RAISE EXCEPTION 'D8: category audit trigger is missing or disabled';
  END IF;

  RAISE NOTICE 'D8: structure, triggers and privileges verified.';
END;
$$;


-- ============================================================================
-- 2. PREPARE TEST DATA
-- ============================================================================

DO $$
DECLARE
  v_usuario uuid := gen_random_uuid();
  v_rol smallint;
  v_categoria integer;
  v_categoria_prueba integer;
  v_categoria_backend integer;
  v_producto uuid := gen_random_uuid();
  v_proveedor uuid := gen_random_uuid();
  v_codigo text :=
    'D8-' || substr(gen_random_uuid()::text, 1, 12);
  v_nit text :=
    'D8-' || substr(gen_random_uuid()::text, 1, 12);
  v_nombre_categoria text :=
    'D8-' || substr(gen_random_uuid()::text, 1, 12);
  v_total integer;
  v_usuario_auditoria uuid;
BEGIN

  -- Set an empty JWT context.
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config(
    'request.jwt.claims',
    '{}',
    true
  );

  -- Create test role.
  -- The code follows rol_codigo_formato: ^[A-Z_]{2,30}$
  INSERT INTO seguridad.rol (
    codigo,
    nombre,
    descripcion
  )
  VALUES (
    'D_PRUEBA',
    'Rol de prueba D8',
    'Rol temporal para pruebas de auditoria'
  )
  RETURNING id INTO v_rol;

  -- Create test user.
  INSERT INTO auth.users (
    id,
    email
  )
  VALUES (
    v_usuario,
    'd8-' || v_usuario::text || '@example.test'
  );

  -- Set authenticated user context.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_usuario::text,
      'role', 'authenticated'
    )::text,
    true
  );

  PERFORM set_config('request.jwt.claim.sub', v_usuario::text, true);

  -- Create profile.
  INSERT INTO seguridad.perfil (
    usuario_id,
    rol_id,
    nombre_completo
  )
  VALUES (
    v_usuario,
    v_rol,
    'Usuario de prueba D8'
  );

  -- Verify auth.uid() was recorded.
  SELECT usuario_id
  INTO v_usuario_auditoria
  FROM auditoria.registro_cambio
  WHERE esquema_tabla = 'seguridad'
    AND nombre_tabla = 'perfil'
    AND operacion = 'INSERT'
    AND registro_id ->> 'usuario_id' = v_usuario::text
  ORDER BY id DESC
  LIMIT 1;

  IF v_usuario_auditoria IS DISTINCT FROM v_usuario THEN
    RAISE EXCEPTION
      'D8: auth.uid() was not recorded correctly for profile';
  END IF;

  -- Clear the authenticated JWT context before backend inventory tests.
  PERFORM set_config('request.jwt.claim.sub', '', true);
  -- This avoids invoking product permission checks for the temporary user.
  PERFORM set_config(
    'request.jwt.claims',
    '{}',
    true
  );

  -- ========================================================================
  -- 3. PRODUCT: INSERT, UPDATE AND DELETE
  -- ========================================================================

  SELECT id
  INTO v_categoria
  FROM inventario.categoria
  LIMIT 1;

  IF v_categoria IS NULL THEN
    RAISE EXCEPTION
      'D8: an existing category is required for product testing';
  END IF;

  INSERT INTO inventario.producto (
    id,
    codigo,
    nombre,
    categoria_id,
    unidad_medida_id
  )
  VALUES (
    v_producto,
    v_codigo,
    'Producto de prueba D8',
    v_categoria,
    (
      SELECT id
      FROM inventario.unidad_medida
      WHERE codigo = 'UND'
      LIMIT 1
    )
  );

  UPDATE inventario.producto
  SET nombre = 'Producto D8 modificado'
  WHERE id = v_producto;

  DELETE FROM inventario.producto
  WHERE id = v_producto;

  IF (
    SELECT count(*)
    FROM auditoria.registro_cambio
    WHERE nombre_tabla = 'producto'
      AND registro_id ->> 'id' = v_producto::text
  ) <> 3 THEN
    RAISE EXCEPTION
      'D8: product must record INSERT, UPDATE and DELETE';
  END IF;


  -- ========================================================================
  -- 4. PROVIDER: INSERT, UPDATE AND DELETE
  -- ========================================================================

  INSERT INTO inventario.proveedor (
    id,
    nit,
    nombre
  )
  VALUES (
    v_proveedor,
    v_nit,
    'Proveedor de prueba D8'
  );

  UPDATE inventario.proveedor
  SET nombre = 'Proveedor D8 modificado'
  WHERE id = v_proveedor;

  DELETE FROM inventario.proveedor
  WHERE id = v_proveedor;

  IF (
    SELECT count(*)
    FROM auditoria.registro_cambio
    WHERE nombre_tabla = 'proveedor'
      AND registro_id ->> 'id' = v_proveedor::text
  ) <> 3 THEN
    RAISE EXCEPTION
      'D8: provider must record INSERT, UPDATE and DELETE';
  END IF;


  -- ========================================================================
  -- 5. CATEGORY: INSERT, UPDATE AND DELETE
  -- ========================================================================

  INSERT INTO inventario.categoria (
    nombre,
    descripcion,
    orden
  )
  VALUES (
    v_nombre_categoria,
    'Categoria temporal para pruebas D8',
    999
  )
  RETURNING id INTO v_categoria_prueba;

  UPDATE inventario.categoria
  SET descripcion = 'Categoria D8 modificada'
  WHERE id = v_categoria_prueba;

  DELETE FROM inventario.categoria
  WHERE id = v_categoria_prueba;

  IF (
    SELECT count(*)
    FROM auditoria.registro_cambio
    WHERE nombre_tabla = 'categoria'
      AND registro_id ->> 'id' = v_categoria_prueba::text
  ) <> 3 THEN
    RAISE EXCEPTION
      'D8: category must record INSERT, UPDATE and DELETE';
  END IF;


  -- ========================================================================
  -- 6. PROFILE: INSERT, UPDATE AND BLOCKED DELETE
  -- ========================================================================

  UPDATE seguridad.perfil
  SET nombre_completo = 'Usuario D8 actualizado'
  WHERE usuario_id = v_usuario;

  IF (
    SELECT count(*)
    FROM auditoria.registro_cambio
    WHERE nombre_tabla = 'perfil'
      AND registro_id ->> 'usuario_id' = v_usuario::text
      AND operacion IN ('INSERT', 'UPDATE')
  ) <> 2 THEN
    RAISE EXCEPTION
      'D8: profile must record INSERT and UPDATE';
  END IF;

  -- Physical profile deletion must remain blocked.
  BEGIN
    DELETE FROM seguridad.perfil
    WHERE usuario_id = v_usuario;

    RAISE EXCEPTION
      'D8_TEST: physical profile deletion was allowed';

  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM =
        'D8_TEST: physical profile deletion was allowed' THEN
        RAISE;
      END IF;

      RAISE NOTICE
        'D8: physical profile deletion was blocked correctly.';
  END;


  -- ========================================================================
  -- 7. OPERATION WITHOUT JWT: NULL USER
  -- ========================================================================

  PERFORM set_config(
    'request.jwt.claims',
    '{}',
    true
  );

  INSERT INTO inventario.categoria (
    nombre,
    descripcion,
    orden
  )
  VALUES (
    'D8-BACKEND-' || substr(gen_random_uuid()::text, 1, 8),
    'Registro generado sin JWT',
    998
  )
  RETURNING id INTO v_categoria_backend;

  SELECT usuario_id
  INTO v_usuario_auditoria
  FROM auditoria.registro_cambio
  WHERE nombre_tabla = 'categoria'
    AND registro_id ->> 'id' = v_categoria_backend::text
    AND operacion = 'INSERT';

  IF v_usuario_auditoria IS NOT NULL THEN
    RAISE EXCEPTION
      'D8: operation without JWT must retain NULL user_id';
  END IF;


  -- ========================================================================
  -- 8. AUDIT IMMUTABILITY
  -- ========================================================================

  BEGIN
    UPDATE auditoria.registro_cambio
    SET ocurrido_en = now()
    WHERE id = (
      SELECT min(id)
      FROM auditoria.registro_cambio
    );

    RAISE EXCEPTION
      'D8_TEST: audit UPDATE was allowed';

  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM = 'D8_TEST: audit UPDATE was allowed' THEN
        RAISE;
      END IF;

      RAISE NOTICE
        'D8: audit UPDATE was blocked correctly.';
  END;


  BEGIN
    DELETE FROM auditoria.registro_cambio
    WHERE id = (
      SELECT min(id)
      FROM auditoria.registro_cambio
    );

    RAISE EXCEPTION
      'D8_TEST: audit DELETE was allowed';

  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM = 'D8_TEST: audit DELETE was allowed' THEN
        RAISE;
      END IF;

      RAISE NOTICE
        'D8: audit DELETE was blocked correctly.';
  END;


  BEGIN
    EXECUTE 'TRUNCATE TABLE auditoria.registro_cambio';

    RAISE EXCEPTION
      'D8_TEST: audit TRUNCATE was allowed';

  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM = 'D8_TEST: audit TRUNCATE was allowed' THEN
        RAISE;
      END IF;

      RAISE NOTICE
        'D8: audit TRUNCATE was blocked correctly.';
  END;


  -- ========================================================================
  -- 9. FINAL EVENT COUNT
  -- ========================================================================

  SELECT count(*)
  INTO v_total
  FROM auditoria.registro_cambio
  WHERE (
    (
      nombre_tabla = 'perfil'
      AND registro_id ->> 'usuario_id' = v_usuario::text
    )
    OR
    (
      nombre_tabla = 'producto'
      AND registro_id ->> 'id' = v_producto::text
    )
    OR
    (
      nombre_tabla = 'proveedor'
      AND registro_id ->> 'id' = v_proveedor::text
    )
    OR
    (
      nombre_tabla = 'categoria'
      AND registro_id ->> 'id' = v_categoria_prueba::text
    )
    OR
    (
      nombre_tabla = 'categoria'
      AND registro_id ->> 'id' = v_categoria_backend::text
    )
  );

  IF v_total < 12 THEN
    RAISE EXCEPTION
      'D8: expected at least 12 events; found %',
      v_total;
  END IF;

  RAISE NOTICE
    'D8: all validations completed. Events recorded: %',
    v_total;

END;
$$;


-- ============================================================================
-- 10. ROLLBACK TEST DATA
-- ============================================================================

ROLLBACK;

-- ============================================================================
-- END D8 AUDIT TESTS
-- ============================================================================
