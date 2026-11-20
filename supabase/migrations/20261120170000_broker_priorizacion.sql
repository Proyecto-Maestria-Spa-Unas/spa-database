-- ════════════════════════════════════════════════════════════════════════════
--  Broker de trabajos con priorización (spa-backend-api #75)
--  Idempotente: se puede aplicar dos veces sin error (lo verifica el CI).
--
--  · Cola persistente en PostgreSQL, sin extensiones: funciona igual en Supabase,
--    en el CI (postgis/postgis) y en Docker local. No usa pgmq.
--  · Prioridad 1 alta · 2 normal · 3 baja. El consumidor (spa-backend-api,
--    módulo broker) ordena por prioridad efectiva con envejecimiento y toma las
--    filas con FOR UPDATE SKIP LOCKED: dos consumidores nunca toman el mismo trabajo.
--  · Reintentos con espera exponencial; al agotar max_intentos queda FALLIDO.
--  · Outbox: trg_movimiento_encolar_alerta encola la alerta de stock en la MISMA
--    transacción del movimiento. Si el movimiento falla, no queda alerta suelta.
--      AGOTADO    → prioridad 1 (alta)
--      BAJO_STOCK → prioridad 2 (normal), solo al cruzar el mínimo
-- ════════════════════════════════════════════════════════════════════════════

-- ── Esquema ─────────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS broker;
COMMENT ON SCHEMA broker IS 'Cola de trabajos asíncronos con priorización (#75)';

REVOKE ALL ON SCHEMA broker FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA broker TO service_role;

-- ── Trabajos ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS broker.trabajo (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tipo               varchar(60) NOT NULL,
  prioridad          smallint NOT NULL,
  payload            jsonb NOT NULL DEFAULT '{}'::jsonb,
  estado             varchar(12) NOT NULL DEFAULT 'PENDIENTE',
  intentos           integer NOT NULL DEFAULT 0,
  max_intentos       integer NOT NULL DEFAULT 5,
  disponible_en      timestamptz NOT NULL DEFAULT now(),
  clave_idempotencia text NOT NULL,
  ultimo_error       varchar(500),
  creado_en          timestamptz NOT NULL DEFAULT now(),
  procesado_en       timestamptz,
  CONSTRAINT trabajo_prioridad_valida CHECK (prioridad BETWEEN 1 AND 3),
  CONSTRAINT trabajo_estado_valido    CHECK (estado IN ('PENDIENTE', 'HECHO', 'FALLIDO')),
  CONSTRAINT trabajo_intentos_validos CHECK (intentos >= 0 AND max_intentos >= 1),
  CONSTRAINT trabajo_clave_uk         UNIQUE (clave_idempotencia)
);

COMMENT ON TABLE broker.trabajo IS
  'Cola priorizada (#75). PENDIENTE → HECHO, o FALLIDO al agotar max_intentos (cola de fallidos)';
COMMENT ON COLUMN broker.trabajo.prioridad IS '1 alta · 2 normal · 3 baja. La efectiva mejora con la espera (envejecimiento)';
COMMENT ON COLUMN broker.trabajo.disponible_en IS 'No se toma antes de esta hora: espera exponencial entre reintentos';
COMMENT ON COLUMN broker.trabajo.clave_idempotencia IS 'Encolar dos veces con la misma clave no crea otro trabajo';

CREATE INDEX IF NOT EXISTS trabajo_pendiente_idx
  ON broker.trabajo (prioridad, disponible_en, id)
  WHERE estado = 'PENDIENTE';

-- ── Notificaciones (resultado del manejador de alertas) ─────────────────────
CREATE TABLE IF NOT EXISTS broker.notificacion (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  trabajo_id  bigint NOT NULL REFERENCES broker.trabajo (id),
  tipo        varchar(60) NOT NULL,
  prioridad   smallint NOT NULL,
  producto_id uuid REFERENCES inventario.producto (id),
  mensaje     varchar(280) NOT NULL,
  creado_en   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT notificacion_trabajo_uk UNIQUE (trabajo_id)
);

COMMENT ON TABLE broker.notificacion IS
  'Bandeja de notificaciones generadas por el broker. Una por trabajo: reprocesar no duplica';

-- ── Encolar (idempotente) ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION broker.encolar(
  p_tipo      text,
  p_prioridad integer,
  p_payload   jsonb,
  p_clave     text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id bigint;
BEGIN
  INSERT INTO broker.trabajo (tipo, prioridad, payload, clave_idempotencia)
  VALUES (p_tipo, p_prioridad, coalesce(p_payload, '{}'::jsonb), p_clave)
  ON CONFLICT (clave_idempotencia) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT t.id INTO v_id FROM broker.trabajo AS t WHERE t.clave_idempotencia = p_clave;
  END IF;

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION broker.encolar(text, integer, jsonb, text) IS
  'Encola un trabajo; con una clave ya usada devuelve el id existente (idempotente)';

REVOKE ALL ON FUNCTION broker.encolar(text, integer, jsonb, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION broker.encolar(text, integer, jsonb, text) TO service_role;

-- ── Outbox: alerta de stock en la misma transacción del movimiento ──────────
CREATE OR REPLACE FUNCTION broker.tg_movimiento_encolar_alerta()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_baja     boolean;
  v_minimo   numeric(14,3);
  v_descont  boolean;
  v_codigo   text;
  v_nombre   text;
  v_anterior numeric(14,3);
  v_estado   text;
BEGIN
  -- Solo interesan los movimientos que bajan el stock: SALIDA o anulación de una ENTRADA.
  IF NEW.tipo = 'SALIDA' THEN
    v_baja := true;
  ELSIF NEW.tipo = 'ANULACION' THEN
    SELECT o.tipo = 'ENTRADA' INTO v_baja
    FROM inventario.movimiento AS o
    WHERE o.id = NEW.movimiento_anulado_id;
  ELSE
    v_baja := false;
  END IF;

  IF NOT coalesce(v_baja, false) THEN
    RETURN NULL;
  END IF;

  SELECT p.stock_minimo, p.descontinuado, p.codigo::text, p.nombre
  INTO v_minimo, v_descont, v_codigo, v_nombre
  FROM inventario.producto AS p
  WHERE p.id = NEW.producto_id;

  IF coalesce(v_descont, true) THEN
    RETURN NULL;
  END IF;

  v_anterior := NEW.saldo_resultante + NEW.cantidad;

  IF NEW.saldo_resultante <= 0 THEN
    v_estado := 'AGOTADO';
  ELSIF v_minimo IS NOT NULL AND NEW.saldo_resultante <= v_minimo AND v_anterior > v_minimo THEN
    v_estado := 'BAJO_STOCK';
  ELSE
    RETURN NULL;
  END IF;

  PERFORM broker.encolar(
    'alerta_stock',
    CASE v_estado WHEN 'AGOTADO' THEN 1 ELSE 2 END,
    jsonb_build_object(
      'producto_id',   NEW.producto_id,
      'codigo',        v_codigo,
      'nombre',        v_nombre,
      'estado',        v_estado,
      'saldo',         NEW.saldo_resultante,
      'stock_minimo',  v_minimo,
      'movimiento_id', NEW.id
    ),
    format('alerta_stock:%s', NEW.id)
  );

  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION broker.tg_movimiento_encolar_alerta() IS
  '#75 · Outbox: encola alerta_stock (AGOTADO prioridad 1, BAJO_STOCK prioridad 2) en la transacción del movimiento';

REVOKE ALL ON FUNCTION broker.tg_movimiento_encolar_alerta() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_movimiento_encolar_alerta ON inventario.movimiento;
CREATE TRIGGER trg_movimiento_encolar_alerta
AFTER INSERT ON inventario.movimiento
FOR EACH ROW
EXECUTE FUNCTION broker.tg_movimiento_encolar_alerta();

-- ── Privilegios mínimos ─────────────────────────────────────────────────────
REVOKE ALL ON broker.trabajo, broker.notificacion FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON broker.trabajo, broker.notificacion TO service_role;

-- ── RLS: sin políticas para authenticated (Data API desactivada; solo el backend) ──
ALTER TABLE broker.trabajo      ENABLE ROW LEVEL SECURITY;
ALTER TABLE broker.notificacion ENABLE ROW LEVEL SECURITY;
