-- ════════════════════════════════════════════════════════════════════════════
--  D9 · Vistas de consumo y kardex valorizado, e índice BRIN por fecha
--  Idempotente: se puede aplicar dos veces sin error (lo verifica el CI).
--
--  · v_kardex: una línea por movimiento con costo promedio y valor del saldo
--    (DEC-11, política de A3). Base de GET /analitica/kardex (X7).
--  · v_consumo_diario: salidas no anuladas por día (hora de Bogotá), producto,
--    categoría y motivo. Base de /analitica/tablero, /consumo y /cobertura (B14).
--  · Las vistas usan security_invoker: aplican el RLS de inventario.movimiento
--    (permiso movimiento.consultar) del usuario que consulta.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Índice BRIN por fecha ───────────────────────────────────────────────────
-- El movimiento solo recibe INSERT con ocurrido_en = now(): la fecha crece con
-- el orden físico de la tabla, que es el caso ideal de BRIN (índice diminuto
-- para filtrar rangos de fechas). El índice btree de D7 se conserva para el
-- historial paginado ORDER BY ocurrido_en DESC.
CREATE INDEX IF NOT EXISTS movimiento_ocurrido_brin
  ON inventario.movimiento USING brin (ocurrido_en);

-- ── Kardex valorizado ───────────────────────────────────────────────────────
CREATE OR REPLACE VIEW inventario.v_kardex
WITH (security_invoker = true)
AS
SELECT
  m.id,
  m.producto_id,
  p.codigo,
  p.nombre,
  m.ocurrido_en,
  m.tipo,
  coalesce(mm.codigo, 'ANULACION')::varchar(30)                    AS motivo_codigo,
  m.cantidad,
  -- Entrada (+) o salida (−) del stock; la anulación tiene el signo contrario al original.
  CASE
    WHEN m.tipo = 'ENTRADA' THEN m.cantidad
    WHEN m.tipo = 'SALIDA'  THEN -m.cantidad
    WHEN o.tipo = 'ENTRADA' THEN -m.cantidad
    ELSE m.cantidad
  END::numeric(14,3)                                               AS cantidad_neta,
  -- Costo registrado: el de la compra; null en salidas (contrato analitica-v1).
  m.costo_unitario,
  -- Costo con que se valora la línea (A3 §3): en salidas, el promedio vigente.
  CASE WHEN m.tipo = 'SALIDA' THEN m.costo_promedio_resultante
       ELSE m.costo_unitario
  END::numeric(14,4)                                               AS costo_valoracion,
  round(m.cantidad * CASE WHEN m.tipo = 'SALIDA' THEN m.costo_promedio_resultante
                          ELSE m.costo_unitario END, 4)::numeric(18,4) AS costo_total,
  m.saldo_resultante                                               AS saldo,
  m.costo_promedio_resultante                                      AS costo_promedio,
  round(m.saldo_resultante * m.costo_promedio_resultante, 4)::numeric(18,4) AS valor_saldo,
  m.movimiento_anulado_id,
  a.id                                                             AS anulado_por_id,
  m.proveedor_id,
  m.registrado_por,
  m.observacion
FROM inventario.movimiento AS m
JOIN inventario.producto AS p ON p.id = m.producto_id
LEFT JOIN inventario.motivo_movimiento AS mm ON mm.id = m.motivo_id
LEFT JOIN inventario.movimiento AS o ON o.id = m.movimiento_anulado_id
LEFT JOIN inventario.movimiento AS a ON a.movimiento_anulado_id = m.id;

COMMENT ON VIEW inventario.v_kardex IS
  'D9: kardex valorizado por costo promedio ponderado (DEC-11, A3). Ordenar por id para la secuencia del producto';
COMMENT ON COLUMN inventario.v_kardex.costo_unitario IS 'Costo registrado en el movimiento; null en salidas';
COMMENT ON COLUMN inventario.v_kardex.costo_valoracion IS 'Costo con que se valora la línea: en salidas, el promedio vigente (A3 §3)';
COMMENT ON COLUMN inventario.v_kardex.costo_total IS 'cantidad × costo_valoracion';
COMMENT ON COLUMN inventario.v_kardex.valor_saldo IS 'saldo × costo_promedio';

-- ── Consumo diario ──────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW inventario.v_consumo_diario
WITH (security_invoker = true)
AS
SELECT
  (m.ocurrido_en AT TIME ZONE 'America/Bogota')::date AS fecha,
  m.producto_id,
  p.codigo,
  p.nombre,
  p.categoria_id,
  c.nombre::text                                      AS categoria,
  mm.codigo                                           AS motivo_codigo,
  sum(m.cantidad)::numeric(14,3)                      AS cantidad,
  sum(round(m.cantidad * m.costo_promedio_resultante, 4))::numeric(18,4) AS costo,
  count(*)::integer                                   AS movimientos
FROM inventario.movimiento AS m
JOIN inventario.producto AS p ON p.id = m.producto_id
JOIN inventario.categoria AS c ON c.id = p.categoria_id
JOIN inventario.motivo_movimiento AS mm ON mm.id = m.motivo_id
WHERE m.tipo = 'SALIDA'
  AND NOT EXISTS (
    SELECT 1 FROM inventario.movimiento AS a WHERE a.movimiento_anulado_id = m.id
  )
GROUP BY 1, m.producto_id, p.codigo, p.nombre, p.categoria_id, c.nombre, mm.codigo;

COMMENT ON VIEW inventario.v_consumo_diario IS
  'D9: salidas no anuladas por día (hora de Bogotá), producto, categoría y motivo, con su costo al promedio vigente';

-- ── Privilegios ─────────────────────────────────────────────────────────────
REVOKE ALL ON inventario.v_kardex, inventario.v_consumo_diario FROM PUBLIC, anon;
GRANT SELECT ON inventario.v_kardex, inventario.v_consumo_diario TO authenticated, service_role;
