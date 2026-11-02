
-- B9: validar actualizaciones administrativas del backend
-- y conservar los controles de permisos para authenticated.
-- Todos los cambios se revierten mediante ROLLBACK.

BEGIN;

-- =========================================================
-- PRUEBA 1: postgres sin claims JWT puede actualizar
-- =========================================================

DO $$
DECLARE
  v_cat       integer;
  v_und       integer;
  v_id        uuid;
  v_stock     numeric;
  v_rows      integer;
  v_codigo    text;
BEGIN
  ASSERT current_user = 'postgres',
    'B9: la prueba debe ejecutarse como postgres';

  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  ASSERT auth.role() IS NULL,
    'B9: auth.role() debe ser NULL sin claims JWT';

  SELECT id INTO v_cat
  FROM inventario.categoria
  ORDER BY id
  LIMIT 1;

  SELECT id INTO v_und
  FROM inventario.unidad_medida
  WHERE codigo = 'UND'
  LIMIT 1;

  ASSERT v_cat IS NOT NULL,
    'B9: se requiere una categoria';

  ASSERT v_und IS NOT NULL,
    'B9: se requiere la unidad UND';

  v_codigo := 'B9-' || substr(gen_random_uuid()::text, 1, 8);

  INSERT INTO inventario.producto (
    codigo,
    nombre,
    categoria_id,
    unidad_medida_id,
    stock_minimo
  )
  VALUES (
    v_codigo,
    'Producto prueba backend',
    v_cat,
    v_und,
    1
  )
  RETURNING id INTO v_id;

  PERFORM set_config('test.b9.product_id', v_id::text, true);

  UPDATE inventario.producto
  SET stock_minimo = 5
  WHERE id = v_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  ASSERT v_rows = 1,
    'B9: postgres debe poder actualizar el producto';

  SELECT stock_minimo INTO v_stock
  FROM inventario.producto
  WHERE id = v_id;

  ASSERT v_stock = 5,
    'B9: el stock minimo debe quedar actualizado en 5';

  RAISE NOTICE
    'PRUEBA 1 OK: postgres actualiza sin claims JWT';
END;
$$;

-- =========================================================
-- PREPARACION: usuario y rol temporal de pruebas
-- =========================================================

DO $$
DECLARE
  v_rol_id      smallint;
  v_usuario_id  uuid;
BEGIN
  -- Crear rol temporal.
  INSERT INTO seguridad.rol (
    codigo,
    nombre,
    descripcion
  )
  VALUES (
    'BTEST_ROLE',
    'Rol temporal prueba B9',
    'Rol temporal para validar permisos del trigger'
  )
  ON CONFLICT (codigo) DO NOTHING;

  SELECT id INTO v_rol_id
  FROM seguridad.rol
  WHERE codigo = 'BTEST_ROLE';

  ASSERT v_rol_id IS NOT NULL,
    'B9: no se pudo obtener el rol temporal';

  -- Asignar únicamente consulta y edición general.
  INSERT INTO seguridad.rol_permiso (rol_id, permiso_id)
  SELECT v_rol_id, p.id
  FROM seguridad.permiso p
  WHERE p.codigo IN (
    'producto.consultar',
    'producto.editar'
  )
  ON CONFLICT (rol_id, permiso_id) DO NOTHING;

  -- Crear usuario temporal.
  v_usuario_id := gen_random_uuid();

  INSERT INTO auth.users (
    id,
    email
  )
  VALUES (
    v_usuario_id,
    v_usuario_id::text || '@b9.test'
  );

  -- Crear perfil asociado al rol temporal.
  INSERT INTO seguridad.perfil (
    usuario_id,
    rol_id,
    activo
  )
  VALUES (
    v_usuario_id,
    v_rol_id,
    true
  );

  PERFORM set_config(
    'test.b9.user_id',
    v_usuario_id::text,
    true
  );

  ASSERT EXISTS (
    SELECT 1
    FROM seguridad.rol_permiso rp
    JOIN seguridad.permiso p ON p.id = rp.permiso_id
    WHERE rp.rol_id = v_rol_id
      AND p.codigo = 'producto.editar'
  ), 'B9: falta asignar producto.editar';

  ASSERT NOT EXISTS (
    SELECT 1
    FROM seguridad.rol_permiso rp
    JOIN seguridad.permiso p ON p.id = rp.permiso_id
    WHERE rp.rol_id = v_rol_id
      AND p.codigo = 'producto.configurar_minimo'
  ), 'B9: el rol temporal no debe tener configurar_minimo';

END;
$$;

-- =========================================================
-- PRUEBA 2: authenticated no puede cambiar stock minimo
-- sin el permiso especifico
-- =========================================================

SELECT set_config(
  'request.jwt.claim.role',
  'authenticated',
  true
);

SELECT set_config(
  'request.jwt.claim.sub',
  current_setting('test.b9.user_id'),
  true
);

SET LOCAL ROLE authenticated;

DO $$
DECLARE
  v_id         uuid;
  v_rows       integer := 0;
  v_bloqueado  boolean := false;
BEGIN
  ASSERT auth.role() = 'authenticated',
    'B9: el rol debe ser authenticated';

  ASSERT auth.uid() IS NOT NULL,
    'B9: debe existir un usuario autenticado';

  ASSERT seguridad.tiene_permiso('producto.consultar'),
    'B9: falta el permiso de consulta';

  ASSERT seguridad.tiene_permiso('producto.editar'),
    'B9: falta el permiso de edicion';

  ASSERT NOT seguridad.tiene_permiso('producto.configurar_minimo'),
    'B9: el usuario no debe tener permiso para configurar minimo';

  v_id := current_setting('test.b9.product_id')::uuid;

  -- La politica RLS permite el intento por producto.editar.
  -- El trigger debe rechazar el cambio de stock_minimo.
  BEGIN
    UPDATE inventario.producto
    SET stock_minimo = 10
    WHERE id = v_id;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

  EXCEPTION
    WHEN raise_exception THEN
      v_bloqueado := true;
  END;

  ASSERT v_bloqueado OR v_rows = 0,
    'B9: authenticated sin permiso no debe modificar stock_minimo';

  RAISE NOTICE
    'PRUEBA 2 OK: authenticated sin configurar_minimo no actualiza stock';
END;
$$;

RESET ROLE;

ROLLBACK;
