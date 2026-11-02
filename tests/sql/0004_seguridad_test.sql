
-- ============================================================================
-- D5 · PRUEBAS DE SEGURIDAD: ROLES, PERMISOS Y PERFILES
-- Proyecto: Spa de Uñas - Inventario
-- Criterios de aceptación:
-- 1. Tres roles y trece permisos.
-- 2. Perfil 1:1 con auth.users y desactivación lógica.
-- 3. Asignación correcta de permisos por rol.
--
-- Todas las operaciones de prueba se deshacen mediante ROLLBACK.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_total integer;
  v_admin integer;
  v_manicurista integer;
  v_gerente integer;
BEGIN

  -- ==========================================================================
  -- D5-01: Verificar los tres roles.
  -- ==========================================================================

  SELECT COUNT(*) INTO v_total
  FROM seguridad.rol;

  ASSERT v_total = 3,
    format('D5-01: se esperaban 3 roles y existen %s', v_total);

  ASSERT NOT EXISTS (
    SELECT codigo
    FROM (VALUES
      ('ADMINISTRADOR'),
      ('MANICURISTA'),
      ('GERENTE')
    ) AS esperados(codigo)
    WHERE NOT EXISTS (
      SELECT 1
      FROM seguridad.rol r
      WHERE r.codigo = esperados.codigo
    )
  ), 'D5-01: los códigos de los roles no coinciden';

  -- ==========================================================================
  -- D5-02: Verificar los trece permisos.
  -- ==========================================================================

  SELECT COUNT(*) INTO v_total
  FROM seguridad.permiso;

  ASSERT v_total = 13,
    format('D5-02: se esperaban 13 permisos y existen %s', v_total);

  ASSERT NOT EXISTS (
    SELECT codigo
    FROM (VALUES
      ('usuario.gestionar'),
      ('producto.consultar'),
      ('producto.crear'),
      ('producto.editar'),
      ('producto.configurar_minimo'),
      ('producto.descontinuar'),
      ('catalogo.administrar'),
      ('movimiento.registrar_entrada'),
      ('movimiento.registrar_salida'),
      ('movimiento.consultar'),
      ('movimiento.anular'),
      ('alerta.consultar'),
      ('analitica.consultar')
    ) AS esperados(codigo)
    WHERE NOT EXISTS (
      SELECT 1
      FROM seguridad.permiso p
      WHERE p.codigo = esperados.codigo
    )
  ), 'D5-02: faltan permisos de la arquitectura';

  -- ==========================================================================
  -- D5-03: Administrador debe tener los trece permisos.
  -- ==========================================================================

  SELECT COUNT(*) INTO v_admin
  FROM seguridad.rol_permiso rp
  JOIN seguridad.rol r ON r.id = rp.rol_id
  WHERE r.codigo = 'ADMINISTRADOR';

  ASSERT v_admin = 13,
    format('D5-03: Administrador tiene %s permisos; se esperaban 13', v_admin);

  ASSERT NOT EXISTS (
    SELECT codigo
    FROM (VALUES
      ('usuario.gestionar'),
      ('producto.consultar'),
      ('producto.crear'),
      ('producto.editar'),
      ('producto.configurar_minimo'),
      ('producto.descontinuar'),
      ('catalogo.administrar'),
      ('movimiento.registrar_entrada'),
      ('movimiento.registrar_salida'),
      ('movimiento.consultar'),
      ('movimiento.anular'),
      ('alerta.consultar'),
      ('analitica.consultar')
    ) AS esperados(codigo)
    WHERE NOT EXISTS (
      SELECT 1
      FROM seguridad.rol_permiso rp
      JOIN seguridad.rol r ON r.id = rp.rol_id
      JOIN seguridad.permiso p ON p.id = rp.permiso_id
      WHERE r.codigo = 'ADMINISTRADOR'
        AND p.codigo = esperados.codigo
    )
  ), 'D5-03: permisos de Administrador incorrectos';

  -- ==========================================================================
  -- D5-04: Manicurista debe tener cuatro permisos.
  -- ==========================================================================

  SELECT COUNT(*) INTO v_manicurista
  FROM seguridad.rol_permiso rp
  JOIN seguridad.rol r ON r.id = rp.rol_id
  WHERE r.codigo = 'MANICURISTA';

  ASSERT v_manicurista = 4,
    format('D5-04: Manicurista tiene %s permisos; se esperaban 4', v_manicurista);

  ASSERT NOT EXISTS (
    SELECT codigo
    FROM (VALUES
      ('producto.consultar'),
      ('movimiento.registrar_salida'),
      ('movimiento.consultar'),
      ('alerta.consultar')
    ) AS esperados(codigo)
    WHERE NOT EXISTS (
      SELECT 1
      FROM seguridad.rol_permiso rp
      JOIN seguridad.rol r ON r.id = rp.rol_id
      JOIN seguridad.permiso p ON p.id = rp.permiso_id
      WHERE r.codigo = 'MANICURISTA'
        AND p.codigo = esperados.codigo
    )
  ), 'D5-04: permisos de Manicurista incorrectos';

  -- ==========================================================================
  -- D5-05: Gerente debe tener cinco permisos.
  -- ==========================================================================

  SELECT COUNT(*) INTO v_gerente
  FROM seguridad.rol_permiso rp
  JOIN seguridad.rol r ON r.id = rp.rol_id
  WHERE r.codigo = 'GERENTE';

  ASSERT v_gerente = 5,
    format('D5-05: Gerente tiene %s permisos; se esperaban 5', v_gerente);

  ASSERT NOT EXISTS (
    SELECT codigo
    FROM (VALUES
      ('usuario.gestionar'),
      ('producto.consultar'),
      ('movimiento.consultar'),
      ('alerta.consultar'),
      ('analitica.consultar')
    ) AS esperados(codigo)
    WHERE NOT EXISTS (
      SELECT 1
      FROM seguridad.rol_permiso rp
      JOIN seguridad.rol r ON r.id = rp.rol_id
      JOIN seguridad.permiso p ON p.id = rp.permiso_id
      WHERE r.codigo = 'GERENTE'
        AND p.codigo = esperados.codigo
    )
  ), 'D5-05: permisos de Gerente incorrectos';

  -- ==========================================================================
  -- D5-06: Verificar las 22 asignaciones.
  -- ==========================================================================

  SELECT COUNT(*) INTO v_total
  FROM seguridad.rol_permiso;

  ASSERT v_total = 22,
    format('D5-06: se esperaban 22 asignaciones y existen %s', v_total);

  -- ==========================================================================
  -- D5-07: Verificar la relación 1:1 del perfil con auth.users.
  -- La clave primaria debe estar formada exclusivamente por usuario_id.
  -- ==========================================================================

  ASSERT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_attribute a
      ON a.attrelid = c.conrelid
     AND a.attname = 'usuario_id'
    WHERE c.conrelid = 'seguridad.perfil'::regclass
      AND c.contype = 'p'
      AND c.conkey = ARRAY[a.attnum]::smallint[]
  ), 'D5-07: usuario_id debe ser la clave primaria de perfil';

  -- Verificar la llave foránea hacia auth.users(id).
  ASSERT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_attribute a
      ON a.attrelid = c.conrelid
     AND a.attname = 'usuario_id'
    JOIN pg_attribute u
      ON u.attrelid = c.confrelid
     AND u.attname = 'id'
    WHERE c.conrelid = 'seguridad.perfil'::regclass
      AND c.confrelid = 'auth.users'::regclass
      AND c.contype = 'f'
      AND c.conkey = ARRAY[a.attnum]::smallint[]
      AND c.confkey = ARRAY[u.attnum]::smallint[]
  ), 'D5-07: falta la relación perfil.usuario_id con auth.users.id';

  -- ==========================================================================
  -- D5-08: Verificar la desactivación lógica.
  -- ==========================================================================

  ASSERT EXISTS (
    SELECT 1
    FROM pg_attribute a
    JOIN pg_attrdef d
      ON d.adrelid = a.attrelid
     AND d.adnum = a.attnum
    WHERE a.attrelid = 'seguridad.perfil'::regclass
      AND a.attname = 'activo'
      AND a.attnotnull
      AND pg_get_expr(d.adbin, d.adrelid) = 'true'
  ), 'D5-08: activo debe ser NOT NULL y tener DEFAULT true';

  -- Verificar que la FK impida eliminar usuarios con perfiles.
  ASSERT EXISTS (
    SELECT 1
    FROM pg_constraint c
    WHERE c.conrelid = 'seguridad.perfil'::regclass
      AND c.confrelid = 'auth.users'::regclass
      AND c.contype = 'f'
      AND c.confdeltype = 'r'
  ), 'D5-08: la FK debe impedir la eliminación del usuario asociado';

  -- Verificar el trigger de protección contra eliminación de perfiles.
  ASSERT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE t.tgrelid = 'seguridad.perfil'::regclass
      AND t.tgname = 'trg_perfil_no_eliminar'
      AND NOT t.tgisinternal
      AND t.tgenabled <> 'D'
      AND (t.tgtype & 2) = 2
      AND (t.tgtype & 1) = 1
      AND (t.tgtype & 8) = 8
      AND n.nspname = 'seguridad'
      AND p.proname = 'tg_impedir_eliminacion_perfil'
  ), 'D5-08: falta el trigger activo que impide eliminar perfiles';

  -- ==========================================================================
  -- Resultado final.
  -- ==========================================================================

  RAISE NOTICE '==============================================';
  RAISE NOTICE '0004_seguridad_test: TODAS LAS PRUEBAS OK';
  RAISE NOTICE 'Roles verificados: 3';
  RAISE NOTICE 'Permisos verificados: 13';
  RAISE NOTICE 'Administrador: % permisos', v_admin;
  RAISE NOTICE 'Manicurista: % permisos', v_manicurista;
  RAISE NOTICE 'Gerente: % permisos', v_gerente;
  RAISE NOTICE 'Asignaciones totales: %', v_total;
  RAISE NOTICE 'Perfil 1:1: verificado';
  RAISE NOTICE 'Desactivacion logica: verificada';
  RAISE NOTICE '==============================================';

END $$;

ROLLBACK;
