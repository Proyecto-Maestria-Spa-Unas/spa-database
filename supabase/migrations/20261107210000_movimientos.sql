-- ════════════════════════════════════════════════════════════════════════════
--  D7 · Movimientos: libro mayor, trigger de saldo y costo promedio ponderado
--  Idempotente: se puede aplicar dos veces sin error (lo verifica el CI).
--
--  Reglas:
--    · Solo INSERT (ADR-0003, DEC-06). Se corrige con un movimiento ANULACION
--      enlazado al original; nunca con UPDATE ni DELETE.
--    · trg_movimiento_aplicar bloquea el producto (FOR UPDATE), valida y
--      actualiza stock_actual y costo_promedio en la misma transacción (RN-05, RN-06).
--    · Costo promedio ponderado móvil (DEC-11, A3 §3):
--        ENTRADA con costo: (saldo × promedio + cantidad × costo) ÷ saldo nuevo;
--        si el saldo anterior es 0, el promedio pasa a ser el costo de la entrada.
--        ENTRADA sin costo (AJUSTE_CONTEO, SALDO_INICIAL): promedio sin cambio (A3 §5.2).
--        SALIDA: se valora al promedio vigente; el promedio no cambia.
--        ANULACION: efecto inverso con el mismo costo del original (A3 §5.3).
--    · Errores (mensaje = código que traduce el backend):
--        STOCK_INSUFICIENTE, PRODUCTO_DESCONTINUADO, MOVIMIENTO_YA_ANULADO,
--        DATOS_INVALIDOS, RECURSO_NO_EXISTE, MOVIMIENTO_INMUTABLE.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Tabla ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS inventario.movimiento (
  id                        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  producto_id               uuid NOT NULL REFERENCES inventario.producto (id),
  tipo                      varchar(10) NOT NULL,
  motivo_id                 integer REFERENCES inventario.motivo_movimiento (id),
  cantidad                  numeric(14,3) NOT NULL,
  saldo_resultante          numeric(14,3) NOT NULL DEFAULT 0,
  costo_unitario            numeric(14,4),
  costo_promedio_resultante numeric(14,4) NOT NULL DEFAULT 0,
  proveedor_id              uuid REFERENCES inventario.proveedor (id),
  observacion               varchar(280),
  registrado_por            uuid NOT NULL REFERENCES auth.users (id),
  ocurrido_en               timestamptz NOT NULL DEFAULT now(),
  movimiento_anulado_id     bigint REFERENCES inventario.movimiento (id),
  clave_idempotencia        uuid NOT NULL,
  CONSTRAINT movimiento_tipo_valido          CHECK (tipo IN ('ENTRADA', 'SALIDA', 'ANULACION')),
  CONSTRAINT movimiento_cantidad_positiva    CHECK (cantidad > 0),
  CONSTRAINT movimiento_saldo_no_negativo    CHECK (saldo_resultante >= 0),
  CONSTRAINT movimiento_costo_no_negativo    CHECK (costo_unitario IS NULL OR costo_unitario >= 0),
  CONSTRAINT movimiento_anulacion_enlazada   CHECK ((tipo = 'ANULACION') = (movimiento_anulado_id IS NOT NULL)),
  CONSTRAINT movimiento_motivo_segun_tipo    CHECK ((tipo = 'ANULACION') = (motivo_id IS NULL)),
  CONSTRAINT movimiento_anulacion_con_motivo CHECK (tipo <> 'ANULACION' OR char_length(btrim(coalesce(observacion, ''))) >= 5),
  CONSTRAINT movimiento_clave_uk             UNIQUE (clave_idempotencia),
  CONSTRAINT movimiento_anulado_uk           UNIQUE (movimiento_anulado_id)
);

COMMENT ON TABLE inventario.movimiento IS
  'Libro mayor inmutable del inventario (kardex). Solo INSERT; se corrige con ANULACION (ADR-0003)';
COMMENT ON COLUMN inventario.movimiento.saldo_resultante IS 'Stock del producto después del movimiento (lo calcula el trigger)';
COMMENT ON COLUMN inventario.movimiento.costo_promedio_resultante IS 'Costo promedio ponderado después del movimiento (DEC-11, lo calcula el trigger)';
COMMENT ON COLUMN inventario.movimiento.clave_idempotencia IS 'Idempotency-Key de la petición: un reintento no crea otro movimiento';
COMMENT ON COLUMN inventario.movimiento.movimiento_anulado_id IS 'Solo en ANULACION: movimiento que revierte. Único: no se anula dos veces';
COMMENT ON COLUMN inventario.movimiento.observacion IS 'En ANULACION es el motivo obligatorio (mínimo 5 caracteres)';

CREATE INDEX IF NOT EXISTS movimiento_producto_idx   ON inventario.movimiento (producto_id, id);
CREATE INDEX IF NOT EXISTS movimiento_ocurrido_idx   ON inventario.movimiento (ocurrido_en DESC);
CREATE INDEX IF NOT EXISTS movimiento_registrado_idx ON inventario.movimiento (registrado_por);

-- ── Trigger de aplicación: saldo y costo promedio ───────────────────────────
CREATE OR REPLACE FUNCTION inventario.tg_movimiento_aplicar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_stock     numeric(14,3);
  v_promedio  numeric(14,4);
  v_descont   boolean;
  v_decimales boolean;
  v_motivo    text;
  v_aplica    text;
  v_original  inventario.movimiento%ROWTYPE;
  v_saldo     numeric(14,3);
  v_costo     numeric(14,4);
BEGIN
  -- ANULACION: se toma todo del movimiento original.
  IF NEW.tipo = 'ANULACION' THEN
    SELECT * INTO v_original
    FROM inventario.movimiento
    WHERE id = NEW.movimiento_anulado_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'RECURSO_NO_EXISTE' USING DETAIL = 'El movimiento a anular no existe';
    END IF;
    IF v_original.tipo = 'ANULACION' THEN
      RAISE EXCEPTION 'DATOS_INVALIDOS' USING DETAIL = 'Una anulación no se puede anular';
    END IF;
    IF EXISTS (SELECT 1 FROM inventario.movimiento WHERE movimiento_anulado_id = v_original.id) THEN
      RAISE EXCEPTION 'MOVIMIENTO_YA_ANULADO' USING DETAIL = 'El movimiento ya fue anulado';
    END IF;
    IF NEW.producto_id IS DISTINCT FROM v_original.producto_id THEN
      RAISE EXCEPTION 'DATOS_INVALIDOS' USING DETAIL = 'La anulación debe ser del mismo producto';
    END IF;
    NEW.cantidad := v_original.cantidad;
  END IF;

  -- Bloqueo del producto: serializa movimientos concurrentes del mismo producto.
  SELECT p.stock_actual, p.costo_promedio, p.descontinuado, um.admite_decimales
  INTO v_stock, v_promedio, v_descont, v_decimales
  FROM inventario.producto AS p
  JOIN inventario.unidad_medida AS um ON um.id = p.unidad_medida_id
  WHERE p.id = NEW.producto_id
  FOR UPDATE OF p;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'RECURSO_NO_EXISTE' USING DETAIL = 'El producto no existe';
  END IF;

  IF NEW.tipo IN ('ENTRADA', 'SALIDA') THEN
    -- Producto descontinuado: no admite entradas ni salidas (HU-12). La anulación sí,
    -- porque corrige un registro anterior.
    IF v_descont THEN
      RAISE EXCEPTION 'PRODUCTO_DESCONTINUADO' USING DETAIL = 'El producto está descontinuado';
    END IF;

    SELECT m.codigo, m.aplica_a INTO v_motivo, v_aplica
    FROM inventario.motivo_movimiento AS m
    WHERE m.id = NEW.motivo_id AND m.activo;

    IF NOT FOUND OR v_aplica <> NEW.tipo THEN
      RAISE EXCEPTION 'DATOS_INVALIDOS' USING DETAIL = 'El motivo no existe o no aplica a este tipo de movimiento';
    END IF;

    -- RN-04: cantidades enteras si la unidad no admite decimales.
    IF NOT v_decimales AND NEW.cantidad <> trunc(NEW.cantidad) THEN
      RAISE EXCEPTION 'DATOS_INVALIDOS' USING DETAIL = 'La unidad del producto no admite decimales';
    END IF;
  END IF;

  IF NEW.tipo = 'ENTRADA' THEN
    IF v_motivo = 'COMPRA' AND NEW.costo_unitario IS NULL THEN
      RAISE EXCEPTION 'DATOS_INVALIDOS' USING DETAIL = 'La COMPRA exige costo_unitario (DEC-11)';
    END IF;
    v_saldo := v_stock + NEW.cantidad;
    IF NEW.costo_unitario IS NOT NULL THEN
      IF v_stock <= 0 THEN
        v_promedio := NEW.costo_unitario;
      ELSE
        v_promedio := round((v_stock * v_promedio + NEW.cantidad * NEW.costo_unitario) / v_saldo, 4);
      END IF;
    END IF;

  ELSIF NEW.tipo = 'SALIDA' THEN
    IF NEW.cantidad > v_stock THEN
      RAISE EXCEPTION 'STOCK_INSUFICIENTE'
        USING DETAIL = format('Disponible %s, solicitado %s', v_stock, NEW.cantidad);
    END IF;
    NEW.costo_unitario := NULL;
    v_saldo := v_stock - NEW.cantidad;

  ELSE  -- ANULACION: efecto inverso del original
    IF v_original.tipo = 'ENTRADA' THEN
      IF NEW.cantidad > v_stock THEN
        RAISE EXCEPTION 'STOCK_INSUFICIENTE'
          USING DETAIL = 'No se puede anular la entrada: parte de ese stock ya salió';
      END IF;
      v_saldo := v_stock - NEW.cantidad;
      v_costo := v_original.costo_unitario;
      IF v_costo IS NOT NULL AND v_saldo > 0 THEN
        v_promedio := greatest(round((v_stock * v_promedio - NEW.cantidad * v_costo) / v_saldo, 4), 0);
      END IF;
    ELSE  -- se anula una SALIDA: el stock vuelve con el costo con que salió
      v_saldo := v_stock + NEW.cantidad;
      v_costo := v_original.costo_promedio_resultante;
      IF v_stock <= 0 THEN
        v_promedio := v_costo;
      ELSE
        v_promedio := round((v_stock * v_promedio + NEW.cantidad * v_costo) / v_saldo, 4);
      END IF;
    END IF;
    NEW.costo_unitario := v_costo;
  END IF;

  NEW.saldo_resultante := v_saldo;
  NEW.costo_promedio_resultante := v_promedio;

  UPDATE inventario.producto
  SET stock_actual = v_saldo,
      costo_promedio = v_promedio
  WHERE id = NEW.producto_id;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION inventario.tg_movimiento_aplicar() IS
  'D7: valida el movimiento, bloquea el producto y actualiza stock y costo promedio (DEC-11) en la misma transacción';

REVOKE ALL ON FUNCTION inventario.tg_movimiento_aplicar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_movimiento_aplicar ON inventario.movimiento;
CREATE TRIGGER trg_movimiento_aplicar
BEFORE INSERT ON inventario.movimiento
FOR EACH ROW
EXECUTE FUNCTION inventario.tg_movimiento_aplicar();

-- ── Inmutabilidad: ni UPDATE ni DELETE ──────────────────────────────────────
CREATE OR REPLACE FUNCTION inventario.tg_movimiento_inmutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'MOVIMIENTO_INMUTABLE'
    USING DETAIL = 'Los movimientos no se modifican ni se borran: registre una ANULACION (ADR-0003)';
END;
$$;

DROP TRIGGER IF EXISTS trg_movimiento_inmutable ON inventario.movimiento;
CREATE TRIGGER trg_movimiento_inmutable
BEFORE UPDATE OR DELETE ON inventario.movimiento
FOR EACH ROW
EXECUTE FUNCTION inventario.tg_movimiento_inmutable();

DROP TRIGGER IF EXISTS trg_movimiento_sin_truncate ON inventario.movimiento;
CREATE TRIGGER trg_movimiento_sin_truncate
BEFORE TRUNCATE ON inventario.movimiento
FOR EACH STATEMENT
EXECUTE FUNCTION inventario.tg_movimiento_inmutable();

-- ── Privilegios mínimos ─────────────────────────────────────────────────────
REVOKE ALL ON inventario.movimiento FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT ON inventario.movimiento TO authenticated, service_role;

-- ── RLS ─────────────────────────────────────────────────────────────────────
ALTER TABLE inventario.movimiento ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS movimiento_consultar ON inventario.movimiento;
CREATE POLICY movimiento_consultar
ON inventario.movimiento
FOR SELECT
TO authenticated
USING (seguridad.tiene_permiso('movimiento.consultar'));

DROP POLICY IF EXISTS movimiento_registrar ON inventario.movimiento;
CREATE POLICY movimiento_registrar
ON inventario.movimiento
FOR INSERT
TO authenticated
WITH CHECK (
  registrado_por = (SELECT auth.uid())
  AND CASE tipo
        WHEN 'ENTRADA'   THEN seguridad.tiene_permiso('movimiento.registrar_entrada')
        WHEN 'SALIDA'    THEN seguridad.tiene_permiso('movimiento.registrar_salida')
        WHEN 'ANULACION' THEN seguridad.tiene_permiso('movimiento.anular')
        ELSE false
      END
);
