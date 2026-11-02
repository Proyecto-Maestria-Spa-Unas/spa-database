
-- ============================================================================
-- D6 · AUTORIZACIÓN Y POLÍTICAS RLS
-- Proyecto: Spa de Uñas - Inventario
-- ============================================================================

-- ============================================================================
-- 1. FUNCIÓN CENTRAL DE AUTORIZACIÓN POR PERMISOS
-- ============================================================================

CREATE OR REPLACE FUNCTION seguridad.tiene_permiso(p_permiso text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM seguridad.perfil AS pe
    JOIN seguridad.rol AS r
      ON r.id = pe.rol_id
    JOIN seguridad.rol_permiso AS rp
      ON rp.rol_id = r.id
    JOIN seguridad.permiso AS p
      ON p.id = rp.permiso_id
    WHERE pe.usuario_id = (SELECT auth.uid())
      AND pe.activo = true
      AND r.activo = true
      AND p.activo = true
      AND p.codigo = p_permiso
  );
$$;

COMMENT ON FUNCTION seguridad.tiene_permiso(text) IS
  'Verifica si el usuario autenticado tiene un permiso activo según su perfil y rol';

REVOKE ALL ON FUNCTION seguridad.tiene_permiso(text)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION seguridad.tiene_permiso(text)
TO authenticated, service_role;


-- ============================================================================
-- 2. POLÍTICAS RLS PARA CATEGORÍAS
-- ============================================================================

DROP POLICY IF EXISTS categoria_crear
ON inventario.categoria;

DROP POLICY IF EXISTS categoria_actualizar
ON inventario.categoria;

DROP POLICY IF EXISTS categoria_lectura
ON inventario.categoria;

CREATE POLICY categoria_lectura
ON inventario.categoria
FOR SELECT
TO authenticated
USING (
  seguridad.tiene_permiso('producto.consultar')
);

CREATE POLICY categoria_crear
ON inventario.categoria
FOR INSERT
TO authenticated
WITH CHECK (
  seguridad.tiene_permiso('catalogo.administrar')
);

CREATE POLICY categoria_actualizar
ON inventario.categoria
FOR UPDATE
TO authenticated
USING (
  seguridad.tiene_permiso('catalogo.administrar')
)
WITH CHECK (
  seguridad.tiene_permiso('catalogo.administrar')
);


-- ============================================================================
-- 3. POLÍTICAS RLS PARA PRODUCTOS
-- ============================================================================

DROP POLICY IF EXISTS producto_lectura
ON inventario.producto;

DROP POLICY IF EXISTS producto_crear
ON inventario.producto;

DROP POLICY IF EXISTS producto_actualizar
ON inventario.producto;

CREATE POLICY producto_lectura
ON inventario.producto
FOR SELECT
TO authenticated
USING (
  seguridad.tiene_permiso('producto.consultar')
);

CREATE POLICY producto_crear
ON inventario.producto
FOR INSERT
TO authenticated
WITH CHECK (
  seguridad.tiene_permiso('producto.crear')
);

CREATE POLICY producto_actualizar
ON inventario.producto
FOR UPDATE
TO authenticated
USING (
  seguridad.tiene_permiso('producto.editar')
  OR seguridad.tiene_permiso('producto.configurar_minimo')
  OR seguridad.tiene_permiso('producto.descontinuar')
)
WITH CHECK (
  seguridad.tiene_permiso('producto.editar')
  OR seguridad.tiene_permiso('producto.configurar_minimo')
  OR seguridad.tiene_permiso('producto.descontinuar')
);


-- ============================================================================
-- 4. POLÍTICAS RLS PARA UNIDADES DE MEDIDA
-- ============================================================================

DROP POLICY IF EXISTS unidad_medida_lectura
ON inventario.unidad_medida;

CREATE POLICY unidad_medida_lectura
ON inventario.unidad_medida
FOR SELECT
TO authenticated
USING (
  seguridad.tiene_permiso('producto.consultar')
);


-- ============================================================================
-- 5. FUNCIÓN DE VALIDACIÓN DE PERMISOS POR COLUMNA
-- ============================================================================

CREATE OR REPLACE FUNCTION inventario.tg_validar_permiso_producto()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  -- El backend de confianza puede realizar operaciones administrativas.
  IF (SELECT auth.role()) = 'service_role' THEN
    RETURN NEW;
  END IF;

  -- Validar cambios en la información general del producto.
  IF (
    NEW.nombre IS DISTINCT FROM OLD.nombre
    OR NEW.descripcion IS DISTINCT FROM OLD.descripcion
    OR NEW.categoria_id IS DISTINCT FROM OLD.categoria_id
    OR NEW.unidad_medida_id IS DISTINCT FROM OLD.unidad_medida_id
  ) AND NOT seguridad.tiene_permiso('producto.editar') THEN
    RAISE EXCEPTION
      'No tiene permiso para editar la información del producto';
  END IF;

  -- Validar cambios en el stock mínimo.
  IF NEW.stock_minimo IS DISTINCT FROM OLD.stock_minimo
     AND NOT seguridad.tiene_permiso('producto.configurar_minimo') THEN
    RAISE EXCEPTION
      'No tiene permiso para configurar el stock mínimo';
  END IF;

  -- Validar la descontinuación del producto.
  IF NEW.descontinuado IS DISTINCT FROM OLD.descontinuado
     AND NOT seguridad.tiene_permiso('producto.descontinuar') THEN
    RAISE EXCEPTION
      'No tiene permiso para descontinuar productos';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION inventario.tg_validar_permiso_producto() IS
  'Valida los permisos específicos antes de modificar campos de productos';

DROP TRIGGER IF EXISTS trg_validar_permiso_producto
ON inventario.producto;

CREATE TRIGGER trg_validar_permiso_producto
BEFORE UPDATE ON inventario.producto
FOR EACH ROW
EXECUTE FUNCTION inventario.tg_validar_permiso_producto();


-- ============================================================================
-- 6. VISTA GENERAL DEL INVENTARIO
-- ============================================================================

CREATE OR REPLACE VIEW inventario.v_inventario
WITH (security_invoker = true)
AS
SELECT
  p.id,
  p.codigo,
  p.nombre,
  p.descripcion,
  c.nombre AS categoria,
  um.codigo AS unidad_medida,
  p.stock_actual,
  p.stock_minimo,
  p.costo_promedio,
  (p.stock_actual * p.costo_promedio) AS valor_inventario,
  p.estado,
  p.descontinuado,
  p.actualizado_en
FROM inventario.producto AS p
JOIN inventario.categoria AS c
  ON c.id = p.categoria_id
JOIN inventario.unidad_medida AS um
  ON um.id = p.unidad_medida_id;

COMMENT ON VIEW inventario.v_inventario IS
  'Vista de consulta general del inventario con seguridad del usuario invocador';


-- ============================================================================
-- 7. VISTA DE ALERTAS DE STOCK
-- ============================================================================

CREATE OR REPLACE VIEW inventario.v_alerta_stock
WITH (security_invoker = true)
AS
SELECT
  p.id,
  p.codigo,
  p.nombre,
  c.nombre AS categoria,
  um.codigo AS unidad_medida,
  p.stock_actual,
  p.stock_minimo,
  p.estado,
  p.actualizado_en
FROM inventario.producto AS p
JOIN inventario.categoria AS c
  ON c.id = p.categoria_id
JOIN inventario.unidad_medida AS um
  ON um.id = p.unidad_medida_id
WHERE p.stock_minimo IS NOT NULL
  AND p.stock_actual <= p.stock_minimo
  AND p.descontinuado = false;

COMMENT ON VIEW inventario.v_alerta_stock IS
  'Vista de productos que alcanzaron o están por debajo del stock mínimo';


-- ============================================================================
-- 8. PRIVILEGIOS DE CONSULTA SOBRE LAS VISTAS
-- ============================================================================

GRANT SELECT ON inventario.v_inventario,
                inventario.v_alerta_stock
TO authenticated, service_role;


-- ============================================================================
-- FIN DE LA MIGRACIÓN D6
-- ============================================================================
