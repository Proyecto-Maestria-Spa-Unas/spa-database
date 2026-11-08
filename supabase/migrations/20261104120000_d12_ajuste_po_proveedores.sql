-- ============================================================================
-- D12 · Ajuste por revisión de QA y decisión de PO (07-nov), PR #33
--
-- No modifica la migración 20261104110000 ya aplicada en staging.
--   1. motivo_movimiento.id pasa de smallint a integer (y su secuencia).
--      Es seguro hoy: ninguna tabla referencia todavía motivo_movimiento (D7).
--   2. Proveedores de prueba según la decisión de PO del 04-nov:
--      Ghem y Masglo (distribuidoras tienda a tienda) sin datos de contacto
--      ni ubicación; tres proveedores de zona con ubicación aproximada.
--      Todos los datos son ficticios y están marcados (PRUEBA).
--
-- Idempotente: se puede volver a ejecutar sin cambiar el resultado.
-- ============================================================================

-- 1. IDENTIFICADOR DE MOTIVO COMO INTEGER --------------------------------------

-- Solo si todavía es smallint: con vistas que ya usan la columna (D9), un ALTER
-- al mismo tipo falla, y el CI vuelve a aplicar todas las migraciones.
DO $migration$
BEGIN
    IF (SELECT data_type FROM information_schema.columns
        WHERE table_schema = 'inventario' AND table_name = 'motivo_movimiento'
          AND column_name = 'id') <> 'integer' THEN
        ALTER TABLE inventario.motivo_movimiento ALTER COLUMN id TYPE integer;
    END IF;
END;
$migration$;

DO $migration$
DECLARE
    v_secuencia text := pg_get_serial_sequence('inventario.motivo_movimiento', 'id');
BEGIN
    IF v_secuencia IS NULL THEN
        RAISE EXCEPTION 'No se encontró la secuencia de identidad de inventario.motivo_movimiento.id';
    END IF;
    EXECUTE format('ALTER SEQUENCE %s AS integer', v_secuencia);
END;
$migration$;

-- 2. PROVEEDORES DE PRUEBA (DECISIÓN DE PO DEL 04-NOV) -------------------------
-- ST_MakePoint recibe LONGITUD primero y LATITUD después.

DO $migration$
DECLARE
    v_postgis_schema text;
BEGIN
    SELECT n.nspname
    INTO v_postgis_schema
    FROM pg_extension e
    JOIN pg_namespace n ON n.oid = e.extnamespace
    WHERE e.extname = 'postgis';

    IF v_postgis_schema IS NULL THEN
        RAISE EXCEPTION 'La extensión PostGIS no está instalada.';
    END IF;

    EXECUTE format(
        $datos$
        INSERT INTO inventario.proveedor (nit, nombre, telefono, correo, direccion, ubicacion)
        SELECT
            d.nit,
            d.nombre,
            d.telefono,
            d.correo,
            d.direccion,
            CASE
                WHEN d.longitud IS NULL OR d.latitud IS NULL THEN NULL::%1$I.geography
                ELSE %1$I.st_setsrid(%1$I.st_makepoint(d.longitud, d.latitud), 4326)::%1$I.geography
            END
        FROM (
            VALUES
            ('NIT-PRUEBA-001', 'Ghem (PRUEBA)',
             NULL::varchar(30), NULL::varchar(254), NULL::varchar(200),
             NULL::double precision, NULL::double precision),
            ('NIT-PRUEBA-002', 'Masglo (PRUEBA)',
             NULL::varchar(30), NULL::varchar(254), NULL::varchar(200),
             NULL::double precision, NULL::double precision),
            ('NIT-PRUEBA-003', 'Proveedor insumos Plaza España (PRUEBA)',
             '3000000003', 'plaza.espana@example.test',
             'Zona Plaza España, Bogotá D.C. (dirección ficticia)',
             -74.0875::double precision, 4.6038::double precision),
            ('NIT-PRUEBA-004', 'Proveedor insumos San Andresito de la 38 (PRUEBA)',
             '3000000004', 'sanandresito38@example.test',
             'Zona San Andresito de la 38, Bogotá D.C. (dirección ficticia)',
             -74.1010::double precision, 4.6095::double precision),
            ('NIT-PRUEBA-005', 'Proveedor insumos San Andresito de la 18 (PRUEBA)',
             '3000000005', 'sanandresito18@example.test',
             'Zona San Andresito de la 18, Bogotá D.C. (dirección ficticia)',
             -74.0855::double precision, 4.6060::double precision)
        ) AS d (nit, nombre, telefono, correo, direccion, longitud, latitud)
        ON CONFLICT (nit) DO UPDATE SET
            nombre = EXCLUDED.nombre,
            telefono = EXCLUDED.telefono,
            correo = EXCLUDED.correo,
            direccion = EXCLUDED.direccion,
            ubicacion = EXCLUDED.ubicacion
        $datos$,
        v_postgis_schema
    );
END;
$migration$;
