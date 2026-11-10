-- ============================================================================
-- D10 · PRUEBA REAL DE CONCURRENCIA EN MOVIMIENTOS
-- Verifica que dos salidas simultáneas no produzcan saldo negativo.
-- Requiere PostgreSQL con la extensión dblink disponible.
-- ============================================================================

\set ON_ERROR_STOP on

CREATE EXTENSION IF NOT EXISTS dblink;

DROP SCHEMA IF EXISTS test_d10 CASCADE;
CREATE SCHEMA test_d10;

CREATE TABLE test_d10.contexto (
    producto_id uuid NOT NULL,
    usuario_id uuid NOT NULL,
    motivo_id integer NOT NULL
);

CREATE OR REPLACE FUNCTION test_d10.intentar_salida(
    p_producto_id uuid,
    p_usuario_id uuid,
    p_motivo_id integer,
    p_cantidad numeric,
    p_clave uuid
)
RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO inventario.movimiento (
        producto_id,
        tipo,
        motivo_id,
        cantidad,
        registrado_por,
        clave_idempotencia
    )
    VALUES (
        p_producto_id,
        'SALIDA',
        p_motivo_id,
        p_cantidad,
        p_usuario_id,
        p_clave
    );

    -- Conserva el bloqueo hasta finalizar la transacción remota.
    PERFORM pg_sleep(2);

    RETURN 'OK';
EXCEPTION
    WHEN OTHERS THEN
        RETURN 'ERROR:' || SQLERRM;
END;
$$;

-- Preparación y confirmación de los datos antes de abrir las conexiones.
DO $$
DECLARE
    v_usuario uuid := gen_random_uuid();
    v_producto uuid;
    v_motivo integer;
    v_codigo text;
BEGIN
    INSERT INTO auth.users (id, email)
    VALUES (v_usuario, v_usuario::text || '@d10.test');

    v_codigo := 'D10-' ||
        upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));

    INSERT INTO inventario.producto (
        codigo,
        nombre,
        categoria_id,
        unidad_medida_id
    )
    SELECT
        v_codigo,
        'Producto prueba concurrencia D10',
        c.id,
        u.id
    FROM inventario.categoria c
    CROSS JOIN inventario.unidad_medida u
    WHERE c.nombre = 'Herramientas'
      AND u.codigo = 'UND'
    RETURNING id INTO v_producto;

    IF v_producto IS NULL THEN
        RAISE EXCEPTION 'D10: no se pudo crear el producto de prueba';
    END IF;

    SELECT id
    INTO v_motivo
    FROM inventario.motivo_movimiento
    WHERE codigo = 'SALDO_INICIAL';

    IF v_motivo IS NULL THEN
        RAISE EXCEPTION 'D10: no existe el motivo SALDO_INICIAL';
    END IF;

    INSERT INTO inventario.movimiento (
        producto_id,
        tipo,
        motivo_id,
        cantidad,
        costo_unitario,
        registrado_por,
        clave_idempotencia
    )
    VALUES (
        v_producto,
        'ENTRADA',
        v_motivo,
        10,
        1,
        v_usuario,
        gen_random_uuid()
    );

    SELECT id
    INTO v_motivo
    FROM inventario.motivo_movimiento
    WHERE codigo = 'MERMA';

    IF v_motivo IS NULL THEN
        RAISE EXCEPTION 'D10: no existe el motivo MERMA';
    END IF;

    INSERT INTO test_d10.contexto (
        producto_id,
        usuario_id,
        motivo_id
    )
    VALUES (v_producto, v_usuario, v_motivo);

    RAISE NOTICE 'D10: producto preparado con 10 unidades. ID: %', v_producto;
END;
$$;

-- Dos conexiones independientes intentan retirar 7 unidades.
DO $$
DECLARE
    v_producto uuid;
    v_usuario uuid;
    v_motivo integer;
    v_sql text;
    v_envio_a integer;
    v_envio_b integer;
    v_resultado_a text;
    v_resultado_b text;
    v_stock numeric;
    v_salidas integer;
BEGIN
    SELECT producto_id, usuario_id, motivo_id
    INTO v_producto, v_usuario, v_motivo
    FROM test_d10.contexto;

    PERFORM public.dblink_connect('d10_a', 'dbname=spa');
    PERFORM public.dblink_connect('d10_b', 'dbname=spa');

    v_sql := format(
        'SELECT test_d10.intentar_salida(%L::uuid, %L::uuid, %s, 7, %L::uuid)',
        v_producto,
        v_usuario,
        v_motivo,
        gen_random_uuid()
    );

    v_envio_a := public.dblink_send_query('d10_a', v_sql);

    v_sql := format(
        'SELECT test_d10.intentar_salida(%L::uuid, %L::uuid, %s, 7, %L::uuid)',
        v_producto,
        v_usuario,
        v_motivo,
        gen_random_uuid()
    );

    v_envio_b := public.dblink_send_query('d10_b', v_sql);

    IF v_envio_a <> 1 OR v_envio_b <> 1 THEN
        RAISE EXCEPTION 'D10: no fue posible iniciar ambas operaciones concurrentes';
    END IF;

    SELECT resultado
    INTO v_resultado_a
    FROM public.dblink_get_result('d10_a') AS t(resultado text);

    SELECT resultado
    INTO v_resultado_b
    FROM public.dblink_get_result('d10_b') AS t(resultado text);

    -- Consumir los resultados finales para liberar ambas conexiones.
    PERFORM 1
    FROM public.dblink_get_result('d10_a') AS t(resultado text);

    PERFORM 1
    FROM public.dblink_get_result('d10_b') AS t(resultado text);

    PERFORM public.dblink_disconnect('d10_a');
    PERFORM public.dblink_disconnect('d10_b');

    IF NOT (
        (v_resultado_a = 'OK'
         AND v_resultado_b = 'ERROR:STOCK_INSUFICIENTE')
        OR
        (v_resultado_b = 'OK'
         AND v_resultado_a = 'ERROR:STOCK_INSUFICIENTE')
    ) THEN
        RAISE EXCEPTION
            'D10: resultados inesperados. Conexión A: %, conexión B: %',
            v_resultado_a, v_resultado_b;
    END IF;

    SELECT stock_actual
    INTO v_stock
    FROM inventario.producto
    WHERE id = v_producto;

    SELECT count(*)::integer
    INTO v_salidas
    FROM inventario.movimiento
    WHERE producto_id = v_producto
      AND tipo = 'SALIDA';

    IF v_stock <> 3 THEN
        RAISE EXCEPTION
            'D10: saldo final incorrecto. Esperado 3, obtenido %',
            v_stock;
    END IF;

    IF v_salidas <> 1 THEN
        RAISE EXCEPTION
            'D10: se esperaba una sola salida aceptada; se encontraron %',
            v_salidas;
    END IF;

    RAISE NOTICE 'D10 OK: dos salidas concurrentes, una aceptada y otra rechazada.';
    RAISE NOTICE 'D10 OK: saldo final %, salidas registradas %.', v_stock, v_salidas;
END;
$$;

DROP SCHEMA test_d10 CASCADE;
