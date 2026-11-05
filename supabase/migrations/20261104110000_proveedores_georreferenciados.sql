
-- ============================================================================
-- D12: PROVEEDORES GEORREFERENCIADOS CON POSTGIS Y MOTIVOS DE MOVIMIENTO
-- Proyecto: Spa de Uñas
--
-- Componentes:
--   1. Tabla inventario.proveedor.
--   2. Ubicación geográfica geography(Point, 4326).
--   3. Índice espacial GiST.
--   4. Función inventario.proveedores_cercanos().
--   5. Seguridad mediante RLS y permisos.
--   6. Cinco proveedores ficticios de Bogotá.
--   7. Seis motivos de movimiento.
--
-- Compatibilidad:
--   Detecta automáticamente el esquema de instalación de PostGIS.
--
-- Idempotencia:
--   IF NOT EXISTS, CREATE OR REPLACE, DROP POLICY IF EXISTS
--   y ON CONFLICT DO UPDATE.
-- ============================================================================


-- ============================================================================
-- 1. DETECCIÓN DE POSTGIS Y CREACIÓN DE PROVEEDORES
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
        RAISE EXCEPTION 'La extensión PostGIS no está instalada.';
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
            direccion varchar(200) NOT NULL,
            ubicacion %1$I.geography(Point, 4326) NOT NULL,
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
-- 2. ÍNDICES DE PROVEEDORES
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
    codigo varchar(30) PRIMARY KEY,
    descripcion varchar(150) NOT NULL,
    activo boolean NOT NULL DEFAULT true,
    creado_en timestamptz NOT NULL DEFAULT now()
);


-- ============================================================================
-- 4. FUNCIÓN DE PROVEEDORES CERCANOS
--
-- Parámetros:
--   p_latitud: latitud del punto de búsqueda.
--   p_longitud: longitud del punto de búsqueda.
--   p_radio_km: radio de búsqueda en kilómetros.
--
-- Resultado:
--   id, NIT, nombre, dirección y distancia en kilómetros.
--
-- ST_DWithin recibe metros para geography.
-- ST_Distance devuelve la distancia en metros.
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
        RAISE EXCEPTION 'La extensión PostGIS no está instalada.';
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
-- 5. PERMISOS DE EJECUCIÓN DE LA FUNCIÓN
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

REVOKE ALL
    ON inventario.proveedor
    FROM PUBLIC, anon;

GRANT SELECT, INSERT, UPDATE
    ON inventario.proveedor
    TO authenticated;

GRANT ALL
    ON inventario.proveedor
    TO service_role;


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
-- 8. DATOS FICTICIOS DE PROVEEDORES EN BOGOTÁ
--
-- IMPORTANTE:
-- Los nombres, NIT, teléfonos, correos, direcciones y coordenadas
-- son ficticios y se utilizan exclusivamente para pruebas.
--
-- ST_MakePoint recibe LONGITUD primero y LATITUD después.
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
        RAISE EXCEPTION 'La extensión PostGIS no está instalada.';
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

            %1$I.st_setsrid(
                %1$I.st_makepoint(
                    datos.longitud,
                    datos.latitud
                ),
                4326
            )::%1$I.geography

        FROM (
            VALUES
            (
                'NIT-PRUEBA-001',
                'Suministros Belleza Andina (PRUEBA)',
                '3000000001',
                'andina@example.test',
                'Ubicación ficticia de prueba - Chapinero, Bogotá D.C.',
                -74.0620::double precision,
                4.6480::double precision
            ),
            (
                'NIT-PRUEBA-002',
                'Distribuidora Uñas y Estilo (PRUEBA)',
                '3000000002',
                'estilo@example.test',
                'Ubicación ficticia de prueba - Teusaquillo, Bogotá D.C.',
                -74.0750::double precision,
                4.6380::double precision
            ),
            (
                'NIT-PRUEBA-003',
                'Cosméticos Nueva Imagen (PRUEBA)',
                '3000000003',
                'imagen@example.test',
                'Ubicación ficticia de prueba - Usaquén, Bogotá D.C.',
                -74.0310::double precision,
                4.6950::double precision
            ),
            (
                'NIT-PRUEBA-004',
                'Comercializadora Manos Perfectas (PRUEBA)',
                '3000000004',
                'manos@example.test',
                'Ubicación ficticia de prueba - Kennedy, Bogotá D.C.',
                -74.1420::double precision,
                4.6250::double precision
            ),
            (
                'NIT-PRUEBA-005',
                'Insumos Profesionales de Belleza (PRUEBA)',
                '3000000005',
                'insumos@example.test',
                'Ubicación ficticia de prueba - Engativá, Bogotá D.C.',
                -74.1050::double precision,
                4.7050::double precision
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
-- 9. DATOS DE REFERENCIA: SEIS MOTIVOS DE MOVIMIENTO
-- ============================================================================

INSERT INTO inventario.motivo_movimiento (
    codigo,
    descripcion
)
VALUES
    (
        'COMPRA',
        'Ingreso de productos por compra a proveedor'
    ),
    (
        'CONSUMO_SERVICIO',
        'Salida de productos para prestación de servicios'
    ),
    (
        'MERMA',
        'Disminución de inventario por merma'
    ),
    (
        'VENCIMIENTO',
        'Retiro de productos vencidos'
    ),
    (
        'AJUSTE_CONTEO',
        'Ajuste por diferencia en conteo físico'
    ),
    (
        'SALDO_INICIAL',
        'Registro del saldo inicial del inventario'
    )

ON CONFLICT (codigo) DO UPDATE SET
    descripcion = EXCLUDED.descripcion;


-- ============================================================================
-- FIN DE LA MIGRACIÓN D12
-- ============================================================================
