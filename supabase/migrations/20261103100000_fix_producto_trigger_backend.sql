-- B9: permitir actualizaciones administrativas desde el backend.
-- Las restricciones del trigger se aplican únicamente a authenticated.
-- No modifica la migración original de D6.

CREATE OR REPLACE FUNCTION inventario.tg_validar_permiso_producto()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  -- Aplicar las restricciones únicamente a solicitudes de Supabase
  -- que utilizan el rol authenticated.
  IF (SELECT auth.role()) IS DISTINCT FROM 'authenticated' THEN
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