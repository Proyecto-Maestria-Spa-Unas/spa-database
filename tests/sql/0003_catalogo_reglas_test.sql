-- D4 · Reglas de negocio del catálogo. Todo se deshace al final (ROLLBACK).
BEGIN;
DO $$
DECLARE
  v_cat  integer := (SELECT id FROM inventario.categoria ORDER BY id LIMIT 1);
  v_und  integer := (SELECT id FROM inventario.unidad_medida WHERE codigo = 'UND');
  v_id   uuid;
  v_ok   boolean;
  v_ver  integer;
BEGIN
  INSERT INTO inventario.producto (codigo, nombre, categoria_id, unidad_medida_id, stock_minimo)
  VALUES ('QA-001', 'Producto de prueba', v_cat, v_und, 5) RETURNING id INTO v_id;

  -- RN-01: código único, sin distinguir mayúsculas
  v_ok := false;
  BEGIN
    INSERT INTO inventario.producto (codigo, nombre, categoria_id, unidad_medida_id)
    VALUES ('qa-001', 'Duplicado', v_cat, v_und);
  EXCEPTION WHEN unique_violation THEN v_ok := true;
  END;
  ASSERT v_ok, 'RN-01: debe rechazar un código duplicado (qa-001 = QA-001)';

  -- RN-02: nombre obligatorio
  v_ok := false;
  BEGIN
    INSERT INTO inventario.producto (codigo, nombre, categoria_id, unidad_medida_id)
    VALUES ('QA-002', '   ', v_cat, v_und);
  EXCEPTION WHEN check_violation THEN v_ok := true;
  END;
  ASSERT v_ok, 'RN-02: debe rechazar un nombre vacío';

  -- RN-06: stock nunca negativo
  v_ok := false;
  BEGIN
    UPDATE inventario.producto SET stock_actual = -0.001 WHERE id = v_id;
  EXCEPTION WHEN check_violation THEN v_ok := true;
  END;
  ASSERT v_ok, 'RN-06: debe rechazar stock negativo';

  -- RN-14: stock mínimo negativo no permitido
  v_ok := false;
  BEGIN
    UPDATE inventario.producto SET stock_minimo = -1 WHERE id = v_id;
  EXCEPTION WHEN check_violation THEN v_ok := true;
  END;
  ASSERT v_ok, 'RN-14: debe rechazar stock mínimo negativo';

  -- RN-08..RN-11 en sus fronteras (mínimo = 5)
  ASSERT (SELECT estado FROM inventario.producto WHERE id = v_id) = 'AGOTADO', 'stock 0 → AGOTADO';
  UPDATE inventario.producto SET stock_actual = 4.999 WHERE id = v_id;
  ASSERT (SELECT estado FROM inventario.producto WHERE id = v_id) = 'BAJO_STOCK', '4.999 < 5 → BAJO_STOCK';
  UPDATE inventario.producto SET stock_actual = 5 WHERE id = v_id;
  ASSERT (SELECT estado FROM inventario.producto WHERE id = v_id) = 'BAJO_STOCK', '5 = mínimo → BAJO_STOCK';
  UPDATE inventario.producto SET stock_actual = 5.001 WHERE id = v_id;
  ASSERT (SELECT estado FROM inventario.producto WHERE id = v_id) = 'DISPONIBLE', '5.001 > 5 → DISPONIBLE';
  UPDATE inventario.producto SET stock_minimo = NULL, stock_actual = 1 WHERE id = v_id;
  ASSERT (SELECT estado FROM inventario.producto WHERE id = v_id) = 'DISPONIBLE', 'sin mínimo → DISPONIBLE';
  UPDATE inventario.producto SET stock_actual = 0 WHERE id = v_id;
  ASSERT (SELECT estado FROM inventario.producto WHERE id = v_id) = 'AGOTADO', 'sin mínimo y 0 → AGOTADO';
  UPDATE inventario.producto SET descontinuado = true WHERE id = v_id;
  ASSERT (SELECT estado FROM inventario.producto WHERE id = v_id) = 'DESCONTINUADO', 'descontinuado manda';

  -- Bloqueo optimista: cada UPDATE sube la versión
  SELECT version INTO v_ver FROM inventario.producto WHERE id = v_id;
  ASSERT v_ver = 7, format('version debe subir con cada UPDATE (esperado 7, obtuvo %s)', v_ver);

  -- El estado no se puede escribir a mano
  v_ok := false;
  BEGIN
    UPDATE inventario.producto SET estado = 'DISPONIBLE' WHERE id = v_id;
  EXCEPTION WHEN generated_always THEN v_ok := true;
  END;
  ASSERT v_ok, 'estado es calculado: no se puede escribir';

  RAISE NOTICE '0003_catalogo_reglas_test: OK';
END $$;
ROLLBACK;
