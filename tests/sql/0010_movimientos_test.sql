-- ============================================================================
-- D7 · PRUEBAS DE MOVIMIENTOS: SALDO, COSTO PROMEDIO, ANULACIÓN Y RLS
-- El kardex reproduce el ejemplo de la política de costo de A3 (spa-docs,
-- docs/05-contabilidad/politica-costo-inventarios.md, sección 4).
-- Todo corre en una transacción que se revierte al final.
-- ============================================================================

BEGIN;

-- ── Preparación: usuario, productos y una función auxiliar ──────────────────
DO $$
DECLARE
  v_usuario uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_usuario, v_usuario::text || '@d7.test');
  PERFORM set_config('test.d7.usuario', v_usuario::text, true);

  INSERT INTO inventario.producto (codigo, nombre, categoria_id, unidad_medida_id)
  SELECT 'D7-ACETONA', 'Acetona D7', c.id, u.id
  FROM inventario.categoria c, inventario.unidad_medida u
  WHERE c.nombre = 'Removedores' AND u.codigo = 'ML';

  INSERT INTO inventario.producto (codigo, nombre, categoria_id, unidad_medida_id)
  SELECT 'D7-LIMA', 'Lima D7', c.id, u.id
  FROM inventario.categoria c, inventario.unidad_medida u
  WHERE c.nombre = 'Herramientas' AND u.codigo = 'UND';
END;
$$;

CREATE FUNCTION pg_temp.mov(
  p_codigo text, p_tipo text, p_motivo text, p_cantidad numeric,
  p_costo numeric DEFAULT NULL, p_anulado bigint DEFAULT NULL, p_obs text DEFAULT NULL
) RETURNS inventario.movimiento
LANGUAGE plpgsql AS $$
DECLARE
  v_fila inventario.movimiento;
BEGIN
  INSERT INTO inventario.movimiento (
    producto_id, tipo, motivo_id, cantidad, costo_unitario,
    movimiento_anulado_id, observacion, registrado_por, clave_idempotencia
  )
  VALUES (
    (SELECT id FROM inventario.producto WHERE codigo = p_codigo),
    p_tipo,
    (SELECT id FROM inventario.motivo_movimiento WHERE codigo = p_motivo),
    p_cantidad, p_costo, p_anulado, p_obs,
    current_setting('test.d7.usuario')::uuid,
    gen_random_uuid()
  )
  RETURNING * INTO v_fila;
  RETURN v_fila;
END;
$$;

CREATE FUNCTION pg_temp.error_de(p_sql text) RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN 'SIN ERROR';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLERRM;
END;
$$;

-- ============================================================================
-- D7-01: ESTRUCTURA
-- ============================================================================
DO $$
BEGIN
  ASSERT to_regclass('inventario.movimiento') IS NOT NULL, 'D7-01: no existe inventario.movimiento';
  ASSERT (SELECT relrowsecurity FROM pg_class WHERE oid = 'inventario.movimiento'::regclass),
    'D7-01: RLS debe estar habilitado en movimiento';
  ASSERT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_movimiento_aplicar'
                 AND tgrelid = 'inventario.movimiento'::regclass),
    'D7-01: falta trg_movimiento_aplicar';
  ASSERT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_movimiento_inmutable'
                 AND tgrelid = 'inventario.movimiento'::regclass),
    'D7-01: falta trg_movimiento_inmutable';
  ASSERT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'movimiento_clave_uk'),
    'D7-01: clave_idempotencia debe ser única';
  ASSERT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'movimiento_anulado_uk'),
    'D7-01: movimiento_anulado_id debe ser único';
  RAISE NOTICE 'D7-01 OK: estructura';
END;
$$;

-- ============================================================================
-- D7-02: KARDEX DEL EJEMPLO DE A3 (costo promedio ponderado, DEC-11)
-- ============================================================================
DO $$
DECLARE
  m inventario.movimiento;
  p inventario.producto;
BEGIN
  m := pg_temp.mov('D7-ACETONA', 'ENTRADA', 'SALDO_INICIAL', 350, 38);
  ASSERT m.saldo_resultante = 350 AND m.costo_promedio_resultante = 38.0000,
    format('D7-02: saldo inicial esperado 350 a 38,0000; obtenido %s a %s', m.saldo_resultante, m.costo_promedio_resultante);

  m := pg_temp.mov('D7-ACETONA', 'ENTRADA', 'COMPRA', 150, 42);
  ASSERT m.saldo_resultante = 500 AND m.costo_promedio_resultante = 39.2000,
    format('D7-02: fila 1 esperada 500 a 39,2000; obtenida %s a %s', m.saldo_resultante, m.costo_promedio_resultante);

  m := pg_temp.mov('D7-ACETONA', 'SALIDA', 'CONSUMO_SERVICIO', 15);
  ASSERT m.saldo_resultante = 485 AND m.costo_promedio_resultante = 39.2000 AND m.costo_unitario IS NULL,
    format('D7-02: fila 2 esperada 485 a 39,2000; obtenida %s a %s', m.saldo_resultante, m.costo_promedio_resultante);

  m := pg_temp.mov('D7-ACETONA', 'ENTRADA', 'COMPRA', 100, 45);
  ASSERT m.saldo_resultante = 585 AND m.costo_promedio_resultante = 40.1915,
    format('D7-02: fila 3 esperada 585 a 40,1915; obtenida %s a %s', m.saldo_resultante, m.costo_promedio_resultante);

  m := pg_temp.mov('D7-ACETONA', 'SALIDA', 'MERMA', 85);
  ASSERT m.saldo_resultante = 500 AND m.costo_promedio_resultante = 40.1915,
    format('D7-02: fila 4 esperada 500 a 40,1915; obtenida %s a %s', m.saldo_resultante, m.costo_promedio_resultante);

  SELECT * INTO p FROM inventario.producto WHERE codigo = 'D7-ACETONA';
  ASSERT p.stock_actual = 500 AND p.costo_promedio = 40.1915,
    'D7-02: el producto no quedó con el saldo y el promedio del último movimiento';
  ASSERT p.stock_actual * p.costo_promedio = 20095.7500,
    format('D7-02: valor del saldo esperado 20.095,7500; obtenido %s', p.stock_actual * p.costo_promedio);

  m := pg_temp.mov('D7-ACETONA', 'ENTRADA', 'AJUSTE_CONTEO', 10);
  ASSERT m.saldo_resultante = 510 AND m.costo_promedio_resultante = 40.1915,
    'D7-02: un AJUSTE_CONTEO sin costo no debe cambiar el promedio (A3 §5.2)';

  RAISE NOTICE 'D7-02 OK: kardex de A3 (39,2000 · 40,1915 · 20.095,7500)';
END;
$$;

-- ============================================================================
-- D7-03: VALIDACIONES DEL TRIGGER (el producto no cambia si falla)
-- ============================================================================
DO $$
DECLARE
  v_stock_antes numeric;
  v_err text;
BEGIN
  SELECT stock_actual INTO v_stock_antes FROM inventario.producto WHERE codigo = 'D7-ACETONA';

  v_err := pg_temp.error_de($q$SELECT pg_temp.mov('D7-ACETONA', 'SALIDA', 'CONSUMO_SERVICIO', 10000)$q$);
  ASSERT v_err = 'STOCK_INSUFICIENTE', 'D7-03: salida mayor al stock debe dar STOCK_INSUFICIENTE; dio ' || v_err;

  v_err := pg_temp.error_de($q$SELECT pg_temp.mov('D7-ACETONA', 'ENTRADA', 'COMPRA', 5)$q$);
  ASSERT v_err = 'DATOS_INVALIDOS', 'D7-03: COMPRA sin costo debe dar DATOS_INVALIDOS; dio ' || v_err;

  v_err := pg_temp.error_de($q$SELECT pg_temp.mov('D7-ACETONA', 'SALIDA', 'COMPRA', 5)$q$);
  ASSERT v_err = 'DATOS_INVALIDOS', 'D7-03: motivo de entrada en una salida debe dar DATOS_INVALIDOS; dio ' || v_err;

  v_err := pg_temp.error_de($q$SELECT pg_temp.mov('D7-LIMA', 'ENTRADA', 'SALDO_INICIAL', 2.5)$q$);
  ASSERT v_err = 'DATOS_INVALIDOS', 'D7-03: decimales en unidad UND deben dar DATOS_INVALIDOS (RN-04); dio ' || v_err;

  v_err := pg_temp.error_de($q$SELECT pg_temp.mov('D7-ACETONA', 'SALIDA', 'MERMA', 0)$q$);
  ASSERT v_err LIKE '%movimiento_cantidad_positiva%', 'D7-03: cantidad 0 debe violar el CHECK; dio ' || v_err;

  UPDATE inventario.producto SET descontinuado = true WHERE codigo = 'D7-LIMA';
  v_err := pg_temp.error_de($q$SELECT pg_temp.mov('D7-LIMA', 'ENTRADA', 'SALDO_INICIAL', 3)$q$);
  ASSERT v_err = 'PRODUCTO_DESCONTINUADO', 'D7-03: producto descontinuado debe dar PRODUCTO_DESCONTINUADO; dio ' || v_err;
  UPDATE inventario.producto SET descontinuado = false WHERE codigo = 'D7-LIMA';

  ASSERT (SELECT stock_actual FROM inventario.producto WHERE codigo = 'D7-ACETONA') = v_stock_antes,
    'D7-03: un movimiento rechazado no debe cambiar el stock';

  RAISE NOTICE 'D7-03 OK: validaciones';
END;
$$;

-- ============================================================================
-- D7-04: IDEMPOTENCIA (la misma clave no crea dos movimientos)
-- ============================================================================
DO $$
DECLARE
  v_clave uuid := gen_random_uuid();
  v_rechazado boolean := false;
  v_producto uuid := (SELECT id FROM inventario.producto WHERE codigo = 'D7-LIMA');
  v_motivo integer := (SELECT id FROM inventario.motivo_movimiento WHERE codigo = 'SALDO_INICIAL');
BEGIN
  INSERT INTO inventario.movimiento (producto_id, tipo, motivo_id, cantidad, registrado_por, clave_idempotencia)
  VALUES (v_producto, 'ENTRADA', v_motivo, 4, current_setting('test.d7.usuario')::uuid, v_clave);
  BEGIN
    INSERT INTO inventario.movimiento (producto_id, tipo, motivo_id, cantidad, registrado_por, clave_idempotencia)
    VALUES (v_producto, 'ENTRADA', v_motivo, 4, current_setting('test.d7.usuario')::uuid, v_clave);
  EXCEPTION WHEN unique_violation THEN
    v_rechazado := true;
  END;
  ASSERT v_rechazado, 'D7-04: una clave_idempotencia repetida debe rechazarse';
  ASSERT (SELECT stock_actual FROM inventario.producto WHERE id = v_producto) = 4,
    'D7-04: el reintento no debe sumar stock otra vez';
  RAISE NOTICE 'D7-04 OK: idempotencia';
END;
$$;

-- ============================================================================
-- D7-05: ANULACIÓN ENLAZADA (ADR-0003)
-- ============================================================================
DO $$
DECLARE
  v_salida  inventario.movimiento;
  v_compra  inventario.movimiento;
  v_anul    inventario.movimiento;
  v_err     text;
BEGIN
  -- Estado de partida: 510 a 40,1915 (después de D7-02).
  SELECT * INTO v_salida FROM inventario.movimiento m
  WHERE m.producto_id = (SELECT id FROM inventario.producto WHERE codigo = 'D7-ACETONA')
    AND m.motivo_id = (SELECT id FROM inventario.motivo_movimiento WHERE codigo = 'MERMA');

  v_anul := pg_temp.mov('D7-ACETONA', 'ANULACION', NULL, 1, NULL, v_salida.id, 'Merma registrada por error');
  ASSERT v_anul.cantidad = 85 AND v_anul.saldo_resultante = 595,
    format('D7-05: anular la merma de 85 debe devolver el stock a 595; obtenido %s', v_anul.saldo_resultante);
  ASSERT v_anul.costo_promedio_resultante = 40.1915,
    'D7-05: anular una salida valorada al promedio no debe cambiar el promedio';

  v_err := pg_temp.error_de(format($q$SELECT pg_temp.mov('D7-ACETONA', 'ANULACION', NULL, 1, NULL, %s, 'Segundo intento')$q$, v_salida.id));
  ASSERT v_err = 'MOVIMIENTO_YA_ANULADO', 'D7-05: anular dos veces debe dar MOVIMIENTO_YA_ANULADO; dio ' || v_err;

  v_err := pg_temp.error_de(format($q$SELECT pg_temp.mov('D7-ACETONA', 'ANULACION', NULL, 1, NULL, %s, 'Anular la anulación')$q$, v_anul.id));
  ASSERT v_err = 'DATOS_INVALIDOS', 'D7-05: una anulación no se anula; dio ' || v_err;

  v_err := pg_temp.error_de(format($q$SELECT pg_temp.mov('D7-ACETONA', 'ANULACION', NULL, 1, NULL, %s, NULL)$q$, v_salida.id));
  ASSERT v_err LIKE '%movimiento_anulacion_con_motivo%' OR v_err = 'MOVIMIENTO_YA_ANULADO',
    'D7-05: la anulación exige motivo; dio ' || v_err;

  -- Anular la COMPRA de 100 a 45: efecto inverso con el mismo costo (A3 §5.3).
  SELECT * INTO v_compra FROM inventario.movimiento m
  WHERE m.producto_id = (SELECT id FROM inventario.producto WHERE codigo = 'D7-ACETONA')
    AND m.costo_unitario = 45 AND m.tipo = 'ENTRADA';
  v_anul := pg_temp.mov('D7-ACETONA', 'ANULACION', NULL, 1, NULL, v_compra.id, 'Factura duplicada');
  ASSERT v_anul.saldo_resultante = 495 AND v_anul.costo_unitario = 45,
    format('D7-05: anular la compra de 100 debe dejar 495 con costo 45; obtenido %s / %s', v_anul.saldo_resultante, v_anul.costo_unitario);
  -- (595 × 40,1915 − 100 × 45) ÷ 495 = 39,2048 (4 decimales)
  ASSERT v_anul.costo_promedio_resultante = round((595 * 40.1915 - 100 * 45) / 495.0, 4),
    format('D7-05: promedio tras anular la compra; obtenido %s', v_anul.costo_promedio_resultante);

  RAISE NOTICE 'D7-05 OK: anulación enlazada';
END;
$$;

-- ============================================================================
-- D7-06: INMUTABILIDAD (solo INSERT)
-- ============================================================================
DO $$
DECLARE
  v_err text;
BEGIN
  v_err := pg_temp.error_de($q$UPDATE inventario.movimiento SET cantidad = 1$q$);
  ASSERT v_err = 'MOVIMIENTO_INMUTABLE', 'D7-06: UPDATE debe dar MOVIMIENTO_INMUTABLE; dio ' || v_err;
  v_err := pg_temp.error_de($q$DELETE FROM inventario.movimiento$q$);
  ASSERT v_err = 'MOVIMIENTO_INMUTABLE', 'D7-06: DELETE debe dar MOVIMIENTO_INMUTABLE; dio ' || v_err;
  RAISE NOTICE 'D7-06 OK: inmutable';
END;
$$;

-- ============================================================================
-- D7-07: RLS POR PERMISO (rol temporal solo con registrar_salida)
-- ============================================================================
DO $$
DECLARE
  v_rol seguridad.rol.id%TYPE;
  v_usuario uuid := gen_random_uuid();
BEGIN
  INSERT INTO seguridad.rol (codigo, nombre, descripcion)
  VALUES ('PRUEBA_DSIETE', 'Rol temporal D7', 'Solo registrar salidas')
  RETURNING id INTO v_rol;

  INSERT INTO seguridad.rol_permiso (rol_id, permiso_id)
  SELECT v_rol, id FROM seguridad.permiso WHERE codigo = 'movimiento.registrar_salida';

  INSERT INTO auth.users (id, email) VALUES (v_usuario, v_usuario::text || '@d7rls.test');
  INSERT INTO seguridad.perfil (usuario_id, rol_id, nombre_completo, activo)
  VALUES (v_usuario, v_rol, 'Usuario temporal D7', true);

  PERFORM set_config('test.d7.rls', v_usuario::text, true);
  -- Ids que el rol temporal no puede leer por RLS (no tiene producto.consultar ni movimiento.consultar).
  PERFORM set_config('test.d7.producto', (SELECT id FROM inventario.producto WHERE codigo = 'D7-LIMA')::text, true);
  PERFORM set_config('test.d7.ajuste', (SELECT id FROM inventario.motivo_movimiento WHERE codigo = 'AJUSTE_CONTEO')::text, true);
  PERFORM set_config('test.d7.merma', (SELECT id FROM inventario.motivo_movimiento WHERE codigo = 'MERMA')::text, true);
END;
$$;

SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', current_setting('test.d7.rls'), true);
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  v_producto uuid := current_setting('test.d7.producto')::uuid;
  v_ajuste integer := current_setting('test.d7.ajuste')::integer;
  v_merma integer := current_setting('test.d7.merma')::integer;
  v_usuario uuid := current_setting('test.d7.rls')::uuid;
  v_otro uuid := current_setting('test.d7.usuario')::uuid;
  v_bloqueado boolean;
  v_total integer;
BEGIN
  ASSERT auth.uid() = v_usuario, 'D7-07: debe existir un usuario autenticado';

  SELECT count(*) INTO v_total FROM inventario.movimiento;
  ASSERT v_total = 0, 'D7-07: sin movimiento.consultar no debe ver movimientos';

  v_bloqueado := false;
  BEGIN
    INSERT INTO inventario.movimiento (producto_id, tipo, motivo_id, cantidad, registrado_por, clave_idempotencia)
    VALUES (v_producto, 'ENTRADA', v_ajuste,
            1, v_usuario, gen_random_uuid());
  EXCEPTION WHEN insufficient_privilege THEN
    v_bloqueado := true;
  END;
  ASSERT v_bloqueado, 'D7-07: sin registrar_entrada no debe poder registrar una entrada';

  v_bloqueado := false;
  BEGIN
    INSERT INTO inventario.movimiento (producto_id, tipo, motivo_id, cantidad, registrado_por, clave_idempotencia)
    VALUES (v_producto, 'SALIDA', v_merma,
            1, v_otro, gen_random_uuid());
  EXCEPTION WHEN insufficient_privilege THEN
    v_bloqueado := true;
  END;
  ASSERT v_bloqueado, 'D7-07: no debe poder registrar a nombre de otro usuario (RN-07)';

  INSERT INTO inventario.movimiento (producto_id, tipo, motivo_id, cantidad, registrado_por, clave_idempotencia)
  VALUES (v_producto, 'SALIDA', v_merma,
          1, v_usuario, gen_random_uuid());

  RAISE NOTICE 'D7-07 OK: RLS por permiso';
END;
$$;

RESET ROLE;

ROLLBACK;
