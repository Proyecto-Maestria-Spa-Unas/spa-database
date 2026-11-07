
-- ============================================================================
-- D12: PROVEEDORES GEORREFERENCIADOS CON POSTGIS Y MOTIVOS DE MOVIMIENTO
-- Proyecto: Spa de Uñas
--
-- Componentes:
-- 1. Tabla inventario.proveedor.
-- 2. Ubicacion geography(Point, 4326).
-- 3. Indice espacial GiST.
-- 4. Funcion inventario.proveedores_cercanos().
-- 5. Seguridad mediante RLS y permisos.
-- 6. Cinco proveedores ficticios de Bogota.
-- 7. Seis motivos de movimiento.
-- ============================================================================

-- ============================================================================
-- 1. DETECCION DE POSTGIS Y CREACION DE PROVEEDORES
-- ============================================================================

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
        RAISE EXCEPTION 'La extension PostGIS no esta instalada.';
    END IF;

    EXECUTE format(
        'GRANT USAGE ON SCHEMA %I TO authenticated, service_role',
        v_postgis_schema
    );

    EXECUTE format(
        $ddl$
        CREATE TABLE IF NOT EXISTS inventario.proveedor (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            nit varchar(30) NOT NULL,
            nombre varchar(120) NOT NULL,
            telefono varchar(30),
            correo varchar(254),
            direccion varchar(200),
            ubicacion %1$I.geography(Point, 4326),
            activo boolean NOT NULL DEFAULT true,
            creado_en timestamptz NOT NULL DEFAULT now(),
            CONSTRAINT proveedor_nit_uk UNIQUE (nit)
        );
        $ddl$,
        v_postgis_schema
    );
END;
$migration$;

-- ============================================================================
-- 2. INDICES DE PROVEEDORES
-- ============================================================================

CREATE INDEX IF NOT EXISTS proveedor_ubicacion_gix
    ON inventario.proveedor
    USING GIST (ubicacion);

CREATE INDEX IF NOT EXISTS proveedor_activo_idx
    ON inventario.proveedor (activo);

-- ============================================================================
-- 3. TABLA DE MOTIVOS DE MOVIMIENTO
-- ============================================================================

CREATE TABLE IF NOT EXISTS inventario.motivo_movimiento (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo varchar(30) NOT NULL UNIQUE,
    nombre varchar(150) NOT NULL,
    aplica_a varchar(10) NOT NULL,
    activo boolean NOT NULL DEFAULT true,
    creado_en timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT motivo_movimiento_aplica_a_ck
        CHECK (aplica_a IN ('ENTRADA', 'SALIDA'))
);

-- Actualizacion de instalaciones donde la tabla ya existia.
ALTER TABLE inventario.motivo_movimiento
    ALTER COLUMN id TYPE integer;

-- La secuencia de identidad tambien debe ser integer.
ALTER SEQUENCE inventario.motivo_movimiento_id_seq
    AS integer;

-- ============================================================================
-- 4. FUNCION DE PROVEEDORES CERCANOS
-- ============================================================================

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
        RAISE EXCEPTION 'La extension PostGIS no esta instalada.';
    END IF;

    EXECUTE format(
        $ddl$
        CREATE OR REPLACE FUNCTION inventario.proveedores_cercanos(
            p_latitud double precision,
            p_longitud double precision,
            p_radio_km double precision
        )
        RETURNS TABLE (
            id uuid,
            nit varchar,
            nombre varchar,
            direccion varchar,
            distancia_km double precision
        )
        LANGUAGE plpgsql
        STABLE
        SET search_path = ''
        AS $fn$
        BEGIN
            IF p_latitud IS NULL
               OR p_latitud NOT BETWEEN -90 AND 90 THEN
                RAISE EXCEPTION
                    'La latitud debe estar entre -90 y 90.';
            END IF;

            IF p_longitud IS NULL
               OR p_longitud NOT BETWEEN -180 AND 180 THEN
                RAISE EXCEPTION
                    'La longitud debe estar entre -180 y 180.';
            END IF;

            IF p_radio_km IS NULL OR p_radio_km <= 0 THEN
                RAISE EXCEPTION
                    'El radio debe ser mayor que cero.';
            END IF;

            RETURN QUERY
            SELECT
                pr.id,
                pr.nit,
                pr.nombre,
                pr.direccion,
                (
                    %1$I.st_distance(
                        pr.ubicacion,
                        %1$I.st_setsrid(
                            %1$I.st_makepoint(
                                p_longitud,
                                p_latitud
                            ),
                            4326
                        )::%1$I.geography,
                        true
                    ) / 1000.0
                )::double precision AS distancia_km
            FROM inventario.proveedor AS pr
            WHERE pr.activo = true
              AND pr.ubicacion IS NOT NULL
              AND %1$I.st_dwithin(
                    pr.ubicacion,
                    %1$I.st_setsrid(
                        %1$I.st_makepoint(
                            p_longitud,
                            p_latitud
                        ),
                        4326
                    )::%1$I.geography,
                    p_radio_km * 1000.0,
                    true
              )
            ORDER BY distancia_km ASC;
        END;
        $fn$;
        $ddl$,
        v_postgis_schema
    );
END;
$migration$;

-- ============================================================================
-- 5. PERMISOS DE EJECUCION DE LA FUNCION
-- ============================================================================

REVOKE ALL ON FUNCTION inventario.proveedores_cercanos(
    double precision,
    double precision,
    double precision
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION inventario.proveedores_cercanos(
    double precision,
    double precision,
    double precision
) TO authenticated, service_role;

-- ============================================================================
-- 6. SEGURIDAD RLS PARA PROVEEDORES
-- ============================================================================

ALTER TABLE inventario.proveedor ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON inventario.proveedor FROM PUBLIC, anon;

GRANT SELECT, INSERT, UPDATE
    ON inventario.proveedor TO authenticated;

GRANT ALL
    ON inventario.proveedor TO service_role;

DROP POLICY IF EXISTS proveedor_consultar
    ON inventario.proveedor;

CREATE POLICY proveedor_consultar
    ON inventario.proveedor
    FOR SELECT
    TO authenticated
    USING (
        seguridad.tiene_permiso('producto.consultar')
    );

DROP POLICY IF EXISTS proveedor_crear
    ON inventario.proveedor;

CREATE POLICY proveedor_crear
    ON inventario.proveedor
    FOR INSERT
    TO authenticated
    WITH CHECK (
        seguridad.tiene_permiso('catalogo.administrar')
    );

DROP POLICY IF EXISTS proveedor_actualizar
    ON inventario.proveedor;

CREATE POLICY proveedor_actualizar
    ON inventario.proveedor
    FOR UPDATE
    TO authenticated
    USING (
        seguridad.tiene_permiso('catalogo.administrar')
    )
    WITH CHECK (
        seguridad.tiene_permiso('catalogo.administrar')
    );

-- ============================================================================
-- 7. SEGURIDAD RLS PARA MOTIVOS DE MOVIMIENTO
-- ============================================================================

ALTER TABLE inventario.motivo_movimiento ENABLE ROW LEVEL SECURITY;

REVOKE ALL
    ON inventario.motivo_movimiento
    FROM PUBLIC, anon;

GRANT SELECT
    ON inventario.motivo_movimiento
    TO authenticated;

GRANT ALL
    ON inventario.motivo_movimiento
    TO service_role;

DROP POLICY IF EXISTS motivo_movimiento_consultar
    ON inventario.motivo_movimiento;

CREATE POLICY motivo_movimiento_consultar
    ON inventario.motivo_movimiento
    FOR SELECT
    TO authenticated
    USING (
        seguridad.tiene_permiso('movimiento.consultar')
    );

-- ============================================================================
-- 8. CINCO PROVEEDORES FICTICIOS DE BOGOTA
-- ============================================================================

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
        RAISE EXCEPTION 'La extension PostGIS no esta instalada.';
    END IF;

    EXECUTE format(
        $seed$
        INSERT INTO inventario.proveedor (
            nit,
            nombre,
            telefono,
            correo,
            direccion,
            ubicacion
        )
        SELECT
            datos.nit,
            datos.nombre,
            datos.telefono,
            datos.correo,
            datos.direccion,
            CASE
                WHEN datos.longitud IS NULL OR datos.latitud IS NULL
                    THEN NULL::%1$I.geography
                ELSE
                    %1$I.st_setsrid(
                        %1$I.st_makepoint(
                            datos.longitud,
                            datos.latitud
                        ),
                        4326
                    )::%1$I.geography
            END
        FROM (
            VALUES
            (
                'NIT-PRUEBA-001',
                'Ghem (PRUEBA)',
                NULL::varchar(30),
                NULL::varchar(254),
                NULL::varchar(200),
                NULL::double precision,
                NULL::double precision
            ),
            (
                'NIT-PRUEBA-002',
                'Masglo (PRUEBA)',
                NULL::varchar(30),
                NULL::varchar(254),
                NULL::varchar(200),
                NULL::double precision,
                NULL::double precision
            ),
            (
                'NIT-PRUEBA-003',
                'Proveedor insumos Plaza España (PRUEBA)',
                '3000000003',
                'plaza.espana@example.test',
                'Zona Plaza España, Bogotá D.C. (direccion ficticia)',
                -74.0875::double precision,
                4.6038::double precision
            ),
            (
                'NIT-PRUEBA-004',
                'Proveedor insumos San Andresito de la 38 (PRUEBA)',
                '3000000004',
                'sanandresito38@example.test',
                'Zona San Andresito de la 38, Bogotá D.C. (direccion ficticia)',
                -74.1010::double precision,
                4.6095::double precision
            ),
            (
                'NIT-PRUEBA-005',
                'Proveedor insumos San Andresito de la 18 (PRUEBA)',
                '3000000005',
                'sanandresito18@example.test',
                'Zona San Andresito de la 18, Bogotá D.C. (direccion ficticia)',
                -74.0855::double precision,
                4.6060::double precision
            )
        ) AS datos (
            nit,
            nombre,
            telefono,
            correo,
            direccion,
            longitud,
            latitud
        )
        ON CONFLICT (nit) DO UPDATE SET
            nombre = EXCLUDED.nombre,
            telefono = EXCLUDED.telefono,
            correo = EXCLUDED.correo,
            direccion = EXCLUDED.direccion,
            ubicacion = EXCLUDED.ubicacion;
        $seed$,
        v_postgis_schema
    );
END;
$migration$;

-- ============================================================================
-- 9. SEIS MOTIVOS DE MOVIMIENTO
-- ============================================================================

INSERT INTO inventario.motivo_movimiento (
    codigo,
    nombre,
    aplica_a
)
VALUES
    (
        'COMPRA',
        'Ingreso de productos por compra a proveedor',
        'ENTRADA'
    ),
    (
        'CONSUMO_SERVICIO',
        'Salida de productos para prestacion de servicios',
        'SALIDA'
    ),
    (
        'MERMA',
        'Disminucion de inventario por merma',
        'SALIDA'
    ),
    (
        'VENCIMIENTO',
        'Retiro de productos vencidos',
        'SALIDA'
    ),
    (
        'AJUSTE_CONTEO',
        'Ajuste por diferencia en conteo fisico',
        'ENTRADA'
    ),
    (
        'SALDO_INICIAL',
        'Registro del saldo inicial del inventario',
        'ENTRADA'
    )
ON CONFLICT (codigo) DO UPDATE SET
    nombre = EXCLUDED.nombre,
    aplica_a = EXCLUDED.aplica_a;

-- ============================================================================
-- FIN DE LA MIGRACION D12
-- ============================================================================
