-- ============================================================================
-- D6 · PRUEBAS DE AUTORIZACIÓN Y POLÍTICAS RLS
-- Proyecto: Spa de Uñas - Inventario
--
-- Criterios de aceptación:
-- 1. Función central de autorización por permisos.
-- 2. Políticas RLS para categorías y productos.
-- 3. Vistas de inventario con security_invoker.
-- 4. Restricciones de escritura mediante trigger.
--
-- Todas las operaciones de prueba se deshacen mediante ROLLBACK.
-- ============================================================================

BEGIN;

DO $$
BEGIN

  RAISE NOTICE 'Iniciando pruebas D6: autorización y políticas RLS';

  -- ==========================================================================
  -- D6-01: Verificar existencia de la función de autorización.
  -- ==========================================================================

  ASSERT to_regprocedure('seguridad.tiene_permiso(text)') IS NOT NULL,
    'D6-01: no existe seguridad.tiene_permiso(text)';

  -- ==========================================================================
  -- D6-02: Verificar SECURITY DEFINER y estabilidad de la función.
  -- ==========================================================================

  ASSERT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'seguridad'
      AND p.proname = 'tiene_permiso'
      AND p.prosecdef = true
      AND p.provolatile = 's'
  ), 'D6-02: la función debe ser SECURITY DEFINER y STABLE';

  -- Verificar que PUBLIC y anon no tengan EXECUTE.
  ASSERT NOT has_function_privilege(
    'anon',
    'seguridad.tiene_permiso(text)',
    'EXECUTE'
  ), 'D6-02: anon no debe ejecutar la función';

  -- ==========================================================================
  -- D6-03: Verificar que RLS está habilitado en las tres tablas.
  -- ==========================================================================

  ASSERT (
    SELECT COUNT(*) = 3
    FROM pg_class
    WHERE oid IN (
      'inventario.categoria'::regclass,
      'inventario.unidad_medida'::regclass,
      'inventario.producto'::regclass
    )
      AND relrowsecurity = true
  ), 'D6-03: RLS debe estar habilitado en las tres tablas';

  -- ==========================================================================
  -- D6-04: Verificar políticas de lectura basadas en permisos.
  -- ==========================================================================

  ASSERT (
    SELECT COUNT(*) = 3
    FROM pg_policies
    WHERE schemaname = 'inventario'
      AND (
        (tablename = 'categoria'
          AND policyname = 'categoria_lectura')
        OR
        (tablename = 'unidad_medida'
          AND policyname = 'unidad_medida_lectura')
        OR
        (tablename = 'producto'
          AND policyname = 'producto_lectura')
      )
      AND cmd = 'SELECT'
      AND roles @> ARRAY['authenticated']::name[]
      AND qual LIKE '%tiene_permiso%'
  ), 'D6-04: faltan políticas de lectura basadas en permisos';

  -- ==========================================================================
  -- D6-05: Verificar políticas de escritura.
  -- ==========================================================================

  -- Creación de categorías.
  ASSERT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'inventario'
      AND tablename = 'categoria'
      AND policyname = 'categoria_crear'
      AND cmd = 'INSERT'
      AND roles @> ARRAY['authenticated']::name[]
      AND with_check LIKE '%tiene_permiso%'
  ), 'D6-05: falta categoria_crear';

  -- Actualización de categorías.
  ASSERT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'inventario'
      AND tablename = 'categoria'
      AND policyname = 'categoria_actualizar'
      AND cmd = 'UPDATE'
      AND roles @> ARRAY['authenticated']::name[]
      AND qual LIKE '%tiene_permiso%'
      AND with_check LIKE '%tiene_permiso%'
  ), 'D6-05: falta categoria_actualizar';

  -- Creación de productos.
  ASSERT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'inventario'
      AND tablename = 'producto'
      AND policyname = 'producto_crear'
      AND cmd = 'INSERT'
      AND roles @> ARRAY['authenticated']::name[]
      AND with_check LIKE '%tiene_permiso%'
  ), 'D6-05: falta producto_crear';

  -- Actualización de productos.
  ASSERT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'inventario'
      AND tablename = 'producto'
      AND policyname = 'producto_actualizar'
      AND cmd = 'UPDATE'
      AND roles @> ARRAY['authenticated']::name[]
      AND qual LIKE '%tiene_permiso%'
      AND with_check LIKE '%tiene_permiso%'
  ), 'D6-05: falta producto_actualizar';

  -- ==========================================================================
  -- D6-06: Verificar existencia de las vistas.
  -- ==========================================================================

  ASSERT to_regclass('inventario.v_inventario') IS NOT NULL,
    'D6-06: no existe inventario.v_inventario';

  ASSERT to_regclass('inventario.v_alerta_stock') IS NOT NULL,
    'D6-06: no existe inventario.v_alerta_stock';

  -- ==========================================================================
  -- D6-07: Verificar security_invoker en las dos vistas.
  -- ==========================================================================

  ASSERT (
    SELECT COUNT(*) = 2
    FROM pg_class
    WHERE oid IN (
      'inventario.v_inventario'::regclass,
      'inventario.v_alerta_stock'::regclass
    )
      AND reloptions @> ARRAY['security_invoker=true']
  ), 'D6-07: las dos vistas deben tener security_invoker=true';

  -- ==========================================================================
  -- D6-08: Verificar permisos SELECT sobre las vistas.
  -- ==========================================================================

  ASSERT has_table_privilege(
    'authenticated',
    'inventario.v_inventario',
    'SELECT'
  ), 'D6-08: authenticated no tiene SELECT sobre v_inventario';

  ASSERT has_table_privilege(
    'authenticated',
    'inventario.v_alerta_stock',
    'SELECT'
  ), 'D6-08: authenticated no tiene SELECT sobre v_alerta_stock';

  -- ==========================================================================
  -- D6-09: Verificar trigger de autorización de productos.
  -- ==========================================================================

  ASSERT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE t.tgrelid = 'inventario.producto'::regclass
      AND t.tgname = 'trg_validar_permiso_producto'
      AND NOT t.tgisinternal
      AND t.tgenabled <> 'D'
      AND (t.tgtype & 2) = 2
      AND (t.tgtype & 16) = 16
      AND n.nspname = 'inventario'
      AND p.proname = 'tg_validar_permiso_producto'
  ), 'D6-09: falta el trigger BEFORE UPDATE de autorización de productos';

  -- ==========================================================================
  -- D6-10: Verificar que la función del trigger existe.
  -- ==========================================================================

  ASSERT to_regprocedure(
    'inventario.tg_validar_permiso_producto()'
  ) IS NOT NULL,
    'D6-10: no existe la función de validación de permisos de productos';

  -- ==========================================================================
  -- Resultado final.
  -- ==========================================================================

  RAISE NOTICE '==============================================';
  RAISE NOTICE '0005_autorizacion_rls_test: VALIDACIONES OK';
  RAISE NOTICE 'D6-01 y D6-02: función de autorización';
  RAISE NOTICE 'D6-03: RLS habilitado';
  RAISE NOTICE 'D6-04 y D6-05: políticas RLS';
  RAISE NOTICE 'D6-06 y D6-07: vistas y security_invoker';
  RAISE NOTICE 'D6-08: permisos de consulta';
  RAISE NOTICE 'D6-09 y D6-10: trigger de autorización';
  RAISE NOTICE '==============================================';

END $$;

ROLLBACK;