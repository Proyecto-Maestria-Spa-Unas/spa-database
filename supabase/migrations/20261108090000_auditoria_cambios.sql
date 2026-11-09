-- ============================================================================
-- D8 · Auditoría de cambios · Spa de Uñas
-- Issue #17
-- Operaciones auditadas: INSERT, UPDATE y DELETE.
-- Consulta exclusiva para service_role.
-- Registros inmutables.
-- ============================================================================

-- 1. Esquema
CREATE SCHEMA IF NOT EXISTS auditoria;

COMMENT ON SCHEMA auditoria IS
  'Registro inmutable de cambios realizados sobre las entidades del sistema.';

REVOKE ALL ON SCHEMA auditoria FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA auditoria TO service_role;


-- 2. Tabla de auditoría
CREATE TABLE IF NOT EXISTS auditoria.registro_cambio (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  esquema_tabla text NOT NULL,
  nombre_tabla text NOT NULL,
  operacion text NOT NULL
    CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE')),
  registro_id jsonb NOT NULL,
  usuario_id uuid,
  datos_anteriores jsonb,
  datos_nuevos jsonb,
  ocurrido_en timestamptz NOT NULL DEFAULT clock_timestamp(),

  CONSTRAINT registro_cambio_operacion_datos_chk CHECK (
    (operacion = 'INSERT'
      AND datos_anteriores IS NULL
      AND datos_nuevos IS NOT NULL)
    OR
    (operacion = 'UPDATE'
      AND datos_anteriores IS NOT NULL
      AND datos_nuevos IS NOT NULL)
    OR
    (operacion = 'DELETE'
      AND datos_anteriores IS NOT NULL
      AND datos_nuevos IS NULL)
  )
);

COMMENT ON TABLE auditoria.registro_cambio IS
  'Historial inmutable de cambios sobre entidades de negocio.';

COMMENT ON COLUMN auditoria.registro_cambio.registro_id IS
  'Identificador de la fila afectada, representado como JSONB.';

COMMENT ON COLUMN auditoria.registro_cambio.usuario_id IS
  'Usuario autenticado que ejecutó la operación; NULL si no existe contexto JWT.';


-- 3. Privilegios mínimos
REVOKE ALL ON TABLE auditoria.registro_cambio
FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE auditoria.registro_cambio TO service_role;

REVOKE ALL ON SEQUENCE auditoria.registro_cambio_id_seq
FROM PUBLIC, anon, authenticated, service_role;

-- La función SECURITY DEFINER utiliza los privilegios de su propietario.
-- No se concede INSERT ni acceso a la secuencia a los roles de aplicación.


-- 4. Función de auditoría
CREATE OR REPLACE FUNCTION auditoria.tg_registrar_cambio()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_anterior jsonb;
  v_nuevo jsonb;
  v_datos jsonb;
  v_id jsonb;
  v_usuario uuid;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_nuevo := to_jsonb(NEW);
    v_datos := v_nuevo;

  ELSIF TG_OP = 'UPDATE' THEN
    v_anterior := to_jsonb(OLD);
    v_nuevo := to_jsonb(NEW);
    v_datos := v_nuevo;

  ELSIF TG_OP = 'DELETE' THEN
    v_anterior := to_jsonb(OLD);
    v_datos := v_anterior;
  END IF;

  CASE TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME
    WHEN 'inventario.producto' THEN
      v_id := jsonb_build_object('id', v_datos -> 'id');

    WHEN 'inventario.proveedor' THEN
      v_id := jsonb_build_object('id', v_datos -> 'id');

    WHEN 'inventario.categoria' THEN
      v_id := jsonb_build_object('id', v_datos -> 'id');

    WHEN 'seguridad.perfil' THEN
      v_id := jsonb_build_object('usuario_id', v_datos -> 'usuario_id');

    ELSE
      RAISE EXCEPTION 'Tabla no habilitada para auditoría: %.%',
        TG_TABLE_SCHEMA, TG_TABLE_NAME;
  END CASE;

  v_usuario := auth.uid();

  INSERT INTO auditoria.registro_cambio (
    esquema_tabla,
    nombre_tabla,
    operacion,
    registro_id,
    usuario_id,
    datos_anteriores,
    datos_nuevos
  )
  VALUES (
    TG_TABLE_SCHEMA,
    TG_TABLE_NAME,
    TG_OP,
    v_id,
    v_usuario,
    v_anterior,
    v_nuevo
  );

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION auditoria.tg_registrar_cambio() IS
  'D8: registra INSERT, UPDATE y DELETE de las entidades habilitadas.';

REVOKE ALL ON FUNCTION auditoria.tg_registrar_cambio()
FROM PUBLIC, anon, authenticated, service_role;


-- 5. Función de inmutabilidad
CREATE OR REPLACE FUNCTION auditoria.tg_impedir_modificacion()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION
    'AUDITORIA_INMUTABLE: no se permite modificar ni eliminar registros de auditoría.';
END;
$$;

REVOKE ALL ON FUNCTION auditoria.tg_impedir_modificacion()
FROM PUBLIC, anon, authenticated, service_role;


-- 6. Protección contra UPDATE, DELETE y TRUNCATE
DROP TRIGGER IF EXISTS trg_registro_cambio_inmutable ON auditoria.registro_cambio;

CREATE TRIGGER trg_registro_cambio_inmutable
BEFORE UPDATE OR DELETE ON auditoria.registro_cambio
FOR EACH ROW
EXECUTE FUNCTION auditoria.tg_impedir_modificacion();

DROP TRIGGER IF EXISTS trg_registro_cambio_no_truncate ON auditoria.registro_cambio;

CREATE TRIGGER trg_registro_cambio_no_truncate
BEFORE TRUNCATE ON auditoria.registro_cambio
FOR EACH STATEMENT
EXECUTE FUNCTION auditoria.tg_impedir_modificacion();


-- 7. Auditoría de producto
DROP TRIGGER IF EXISTS trg_auditoria_producto ON inventario.producto;

CREATE TRIGGER trg_auditoria_producto
AFTER INSERT OR UPDATE OR DELETE ON inventario.producto
FOR EACH ROW
EXECUTE FUNCTION auditoria.tg_registrar_cambio();


-- 8. Auditoría de proveedor
DROP TRIGGER IF EXISTS trg_auditoria_proveedor ON inventario.proveedor;

CREATE TRIGGER trg_auditoria_proveedor
AFTER INSERT OR UPDATE OR DELETE ON inventario.proveedor
FOR EACH ROW
EXECUTE FUNCTION auditoria.tg_registrar_cambio();


-- 9. Auditoría de perfil
DROP TRIGGER IF EXISTS trg_auditoria_perfil ON seguridad.perfil;

CREATE TRIGGER trg_auditoria_perfil
AFTER INSERT OR UPDATE OR DELETE ON seguridad.perfil
FOR EACH ROW
EXECUTE FUNCTION auditoria.tg_registrar_cambio();


-- 10. Auditoría de categoría
DROP TRIGGER IF EXISTS trg_auditoria_categoria ON inventario.categoria;

CREATE TRIGGER trg_auditoria_categoria
AFTER INSERT OR UPDATE OR DELETE ON inventario.categoria
FOR EACH ROW
EXECUTE FUNCTION auditoria.tg_registrar_cambio();


-- 11. Seguridad y RLS
ALTER TABLE auditoria.registro_cambio ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS registro_cambio_service_role_select ON auditoria.registro_cambio;

CREATE POLICY registro_cambio_service_role_select
ON auditoria.registro_cambio
FOR SELECT
TO service_role
USING (true);


-- ============================================================================
-- FIN D8 · Auditoría de cambios
-- ============================================================================
