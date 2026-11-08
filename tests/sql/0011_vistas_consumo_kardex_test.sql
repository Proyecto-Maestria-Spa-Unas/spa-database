-- ============================================================================
-- D9 · PRUEBAS DE LAS VISTAS DE KARDEX Y CONSUMO
-- El kardex debe cuadrar con el ejemplo de la política de A3 (spa-docs,
-- docs/05-contabilidad/politica-costo-inventarios.md, sección 4).
-- Todo corre en una transacción que se revierte al final.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_usuario uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_usuario, v_usuario::text || '@d9.test');
  PERFORM set_config('test.d9.usuario', v_usuario::text, true);

  INSERT INTO inventario.producto (codigo, nombre, categoria_id, unidad_medida_id)
  SELECT 'D9-ACETONA', 'Acetona D9', c.id, u.id
  FROM inventario.categoria c, inventario.unidad_medida u
  WHERE c.nombre = 'Removedores' AND u.codigo = 'ML';
END;
$$;

CREATE FUNCTION pg_temp.mov(
  p_tipo text, p_motivo text, p_cantidad numeric,
  p_costo numeric DEFAULT NULL, p_anulado bigint DEFAULT NULL, p_obs text DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
  v_id bigint;
BEGIN
  INSERT INTO inventario.movimiento (
    producto_id, tipo, motivo_id, cantidad, costo_unitario,
    movimiento_anulado_id, observacion, registrado_por, clave_idempotencia
  )
  VALUES (
    (SELECT id FROM inventario.producto WHERE codigo = 'D9-ACETONA'),
    p_tipo,
    (SELECT id FROM inventario.motivo_movimiento WHERE codigo = p_motivo),
    p_cantidad, p_costo, p_anulado, p_obs,
    current_setting('test.d9.usuario')::uuid,
    gen_random_uuid()
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ============================================================================
-- D9-01: ESTRUCTURA (vistas con security_invoker e índice BRIN)
-- ============================================================================
DO $$
BEGIN
  ASSERT to_regclass('inventario.v_kardex') IS NOT NULL, 'D9-01: no existe inventario.v_kardex';
  ASSERT to_regclass('inventario.v_consumo_diario') IS NOT NULL, 'D9-01: no existe inventario.v_consumo_diario';
  ASSERT (SELECT reloptions @> ARRAY['security_invoker=true'] FROM pg_class
          WHERE oid = 'inventario.v_kardex'::regclass),
    'D9-01: v_kardex debe usar security_invoker';
  ASSERT (SELECT reloptions @> ARRAY['security_invoker=true'] FROM pg_class
          WHERE oid = 'inventario.v_consumo_diario'::regclass),
    'D9-01: v_consumo_diario debe usar security_invoker';
  ASSERT EXISTS (
    SELECT 1 FROM pg_index i
    JOIN pg_class ix ON ix.oid = i.indexrelid
    JOIN pg_am am ON am.oid = ix.relam
    WHERE i.indrelid = 'inventario.movimiento'::regclass AND am.amname = 'brin'
  ), 'D9-01: falta el índice BRIN por fecha en movimiento';
  RAISE NOTICE 'D9-01 OK: estructura';
END;
$$;

-- ============================================================================
-- D9-02: KARDEX DEL EJEMPLO DE A3
-- ============================================================================
DO $$
DECLARE
  v_lineas record;
  v_n integer := 0;
  -- saldo, promedio, valor del saldo, costo total de la línea (A3 §4, filas 0 a 4)
  v_esperado numeric[][] := ARRAY[
    [350, 38.0000, 13300.0000, 13300.0000],
    [500, 39.2000, 19600.0000,  6300.0000],
    [485, 39.2000, 19012.0000,   588.0000],
    [585, 40.1915, 23512.0275,  4500.0000],
    [500, 40.1915, 20095.7500,  3416.2775]
  ];
BEGIN
  PERFORM pg_temp.mov('ENTRADA', 'SALDO_INICIAL', 350, 38);
  PERFORM pg_temp.mov('ENTRADA', 'COMPRA', 150, 42);
  PERFORM pg_temp.mov('SALIDA', 'CONSUMO_SERVICIO', 15);
  PERFORM pg_temp.mov('ENTRADA', 'COMPRA', 100, 45);
  PERFORM pg_temp.mov('SALIDA', 'MERMA', 85);

  FOR v_lineas IN
    SELECT * FROM inventario.v_kardex WHERE codigo = 'D9-ACETONA' ORDER BY id
  LOOP
    v_n := v_n + 1;
    ASSERT v_lineas.saldo = v_esperado[v_n][1]
       AND v_lineas.costo_promedio = v_esperado[v_n][2]
       AND v_lineas.valor_saldo = v_esperado[v_n][3]
       AND v_lineas.costo_total = v_esperado[v_n][4],
      format('D9-02: fila %s esperada saldo %s, promedio %s, valor %s, costo total %s; obtenida %s, %s, %s, %s',
             v_n - 1, v_esperado[v_n][1], v_esperado[v_n][2], v_esperado[v_n][3], v_esperado[v_n][4],
             v_lineas.saldo, v_lineas.costo_promedio, v_lineas.valor_saldo, v_lineas.costo_total);
  END LOOP;
  ASSERT v_n = 5, format('D9-02: se esperaban 5 líneas de kardex; hubo %s', v_n);

  ASSERT (SELECT costo_unitario IS NULL AND costo_valoracion = 39.2000 AND cantidad_neta = -15
          FROM inventario.v_kardex WHERE codigo = 'D9-ACETONA' AND motivo_codigo = 'CONSUMO_SERVICIO'),
    'D9-02: la salida debe tener costo_unitario null, valorarse a 39,2000 y restar 15';

  RAISE NOTICE 'D9-02 OK: kardex de A3 (13.300 · 19.600 · 19.012 · 23.512,0275 · 20.095,7500)';
END;
$$;

-- ============================================================================
-- D9-03: CONSUMO DIARIO (solo salidas no anuladas)
-- ============================================================================
DO $$
DECLARE
  v_merma bigint;
  v_anulacion bigint;
BEGIN
  ASSERT (SELECT sum(cantidad) FROM inventario.v_consumo_diario WHERE codigo = 'D9-ACETONA') = 100,
    'D9-03: el consumo debe ser 15 + 85 = 100';
  ASSERT (SELECT count(*) FROM inventario.v_consumo_diario WHERE codigo = 'D9-ACETONA') = 2,
    'D9-03: debe haber una fila por motivo (CONSUMO_SERVICIO y MERMA)';
  ASSERT (SELECT categoria FROM inventario.v_consumo_diario WHERE codigo = 'D9-ACETONA' LIMIT 1) = 'Removedores',
    'D9-03: la categoría debe ser Removedores';
  ASSERT (SELECT fecha FROM inventario.v_consumo_diario WHERE codigo = 'D9-ACETONA' LIMIT 1)
         = (now() AT TIME ZONE 'America/Bogota')::date,
    'D9-03: la fecha debe ser la de Bogotá';
  ASSERT (SELECT costo FROM inventario.v_consumo_diario
          WHERE codigo = 'D9-ACETONA' AND motivo_codigo = 'MERMA') = 3416.2775,
    'D9-03: el costo de la merma debe ser 85 × 40,1915 = 3.416,2775';

  SELECT id INTO v_merma FROM inventario.v_kardex WHERE codigo = 'D9-ACETONA' AND motivo_codigo = 'MERMA';
  v_anulacion := pg_temp.mov('ANULACION', NULL, 1, NULL, v_merma, 'Merma registrada por error');

  ASSERT (SELECT sum(cantidad) FROM inventario.v_consumo_diario WHERE codigo = 'D9-ACETONA') = 15,
    'D9-03: al anular la merma, el consumo debe quedar en 15';
  ASSERT (SELECT anulado_por_id FROM inventario.v_kardex WHERE id = v_merma) = v_anulacion,
    'D9-03: el kardex debe mostrar qué anulación revirtió la merma';
  ASSERT (SELECT cantidad_neta = 85 AND motivo_codigo = 'ANULACION' AND saldo = 585
          FROM inventario.v_kardex WHERE id = v_anulacion),
    'D9-03: la anulación de una salida debe sumar 85 y dejar el saldo en 585';

  RAISE NOTICE 'D9-03 OK: consumo diario';
END;
$$;

-- ============================================================================
-- D9-04: RLS A TRAVÉS DE LAS VISTAS (sin movimiento.consultar no se ve nada)
-- ============================================================================
DO $$
DECLARE
  v_rol seguridad.rol.id%TYPE;
  v_usuario uuid := gen_random_uuid();
BEGIN
  INSERT INTO seguridad.rol (codigo, nombre, descripcion)
  VALUES ('PRUEBA_DNUEVE', 'Rol temporal D9', 'Sin permisos de movimientos')
  RETURNING id INTO v_rol;
  INSERT INTO auth.users (id, email) VALUES (v_usuario, v_usuario::text || '@d9rls.test');
  INSERT INTO seguridad.perfil (usuario_id, rol_id, nombre_completo, activo)
  VALUES (v_usuario, v_rol, 'Usuario temporal D9', true);
  PERFORM set_config('test.d9.rls', v_usuario::text, true);
END;
$$;

SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', current_setting('test.d9.rls'), true);
SET LOCAL ROLE authenticated;

DO $$
BEGIN
  ASSERT (SELECT count(*) FROM inventario.v_kardex) = 0,
    'D9-04: sin movimiento.consultar no debe ver el kardex';
  ASSERT (SELECT count(*) FROM inventario.v_consumo_diario) = 0,
    'D9-04: sin movimiento.consultar no debe ver el consumo';
  RAISE NOTICE 'D9-04 OK: RLS a través de las vistas';
END;
$$;

RESET ROLE;

ROLLBACK;
