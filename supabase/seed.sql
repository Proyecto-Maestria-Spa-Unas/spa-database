-- ════════════════════════════════════════════════════════════════════════════
--  Seed: solo datos de demostración (D11), nunca datos que producción necesite.
--  ⚠ Supabase ejecuta este archivo UNA vez por proyecto. Si se modifica después,
--    `supabase db push --include-seed` solo actualiza su hash y NO lo vuelve a correr.
--    Los datos de referencia (categorías, unidades, motivos, roles, permisos) van en
--    una migración nueva con INSERT ... ON CONFLICT DO NOTHING.
-- ════════════════════════════════════════════════════════════════════════════
-- ============================================================================
-- D11 · DATOS DE DEMOSTRACIÓN
-- Solo staging. No modifica registros existentes ni el stock de productos.
-- ============================================================================

BEGIN;

INSERT INTO inventario.producto (
    codigo,
    nombre,
    descripcion,
    categoria_id,
    unidad_medida_id,
    stock_minimo
)
SELECT
    datos.codigo,
    datos.nombre,
    datos.descripcion,
    categoria.id,
    unidad.id,
    datos.stock_minimo
FROM (
    VALUES
        ('DEMO-ESM-001', 'Esmalte rojo clásico', 'Esmalte tradicional tono rojo intenso', 'Esmaltes', 'UND', 5),
        ('DEMO-ESM-002', 'Esmalte nude', 'Esmalte tradicional tono nude', 'Esmaltes', 'UND', 5),
        ('DEMO-REM-001', 'Removedor de esmalte', 'Removedor líquido para esmalte tradicional', 'Removedores', 'ML', 250),
        ('DEMO-HER-001', 'Lima profesional', 'Lima de uñas de grano medio', 'Herramientas', 'UND', 10),
        ('DEMO-HER-002', 'Empujador de cutícula', 'Herramienta metálica para manicura', 'Herramientas', 'UND', 3),
        ('DEMO-DES-001', 'Algodón', 'Algodón para limpieza de uñas', 'Desechables', 'PAQ', 5),
        ('DEMO-DES-002', 'Guantes desechables', 'Guantes para procedimientos de manicura', 'Desechables', 'CAJA', 2),
        ('DEMO-GEL-001', 'Gel constructor transparente', 'Gel constructor para uñas', 'Geles y acrílicos', 'G', 100),
        ('DEMO-GEL-002', 'Acrílico cristal', 'Polvo acrílico transparente', 'Geles y acrílicos', 'G', 100),
        ('DEMO-TRA-001', 'Aceite de cutícula', 'Aceite hidratante para cutículas', 'Tratamientos', 'ML', 100),
        ('DEMO-TRA-002', 'Fortalecedor de uñas', 'Tratamiento fortalecedor', 'Tratamientos', 'ML', 50),
        ('DEMO-DEC-001', 'Stickers decorativos', 'Láminas adhesivas para decoración', 'Decoración', 'PAQ', 3),
        ('DEMO-HIG-001', 'Alcohol antiséptico', 'Alcohol para limpieza y desinfección', 'Higiene y desinfección', 'ML', 250),
        ('DEMO-HIG-002', 'Desinfectante de herramientas', 'Solución para desinfección de herramientas', 'Higiene y desinfección', 'ML', 250)
) AS datos(codigo, nombre, descripcion, categoria_nombre, unidad_codigo, stock_minimo)
JOIN inventario.categoria AS categoria
    ON categoria.nombre = datos.categoria_nombre
JOIN inventario.unidad_medida AS unidad
    ON unidad.codigo = datos.unidad_codigo
ON CONFLICT (codigo) DO NOTHING;


DO $$
DECLARE
    v_total INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_total
    FROM inventario.producto
    WHERE codigo IN (
        'DEMO-ESM-001',
        'DEMO-ESM-002',
        'DEMO-REM-001',
        'DEMO-HER-001',
        'DEMO-HER-002',
        'DEMO-DES-001',
        'DEMO-DES-002',
        'DEMO-GEL-001',
        'DEMO-GEL-002',
        'DEMO-TRA-001',
        'DEMO-TRA-002',
        'DEMO-DEC-001',
        'DEMO-HIG-001',
        'DEMO-HIG-002'
    );

    IF v_total <> 14 THEN
        RAISE EXCEPTION
            'D11: se esperaban 14 productos demo, pero se encontraron %',
            v_total;
    END IF;
END;
$$;

DO $$
DECLARE
    v_total_cuentas INTEGER;
    v_cuentas_validas INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_total_cuentas
    FROM auth.users
    WHERE lower(email) IN (
        'admin.demo@example.test',
        'manicurista.demo@example.test'
    );

    IF v_total_cuentas = 0 THEN
        RAISE NOTICE
            'D11: no hay cuentas demo. Se omiten los movimientos.';
    ELSE
        IF v_total_cuentas <> 2 THEN
            RAISE EXCEPTION
                'D11: se esperaban 2 cuentas demo y se encontraron %.',
                v_total_cuentas;
        END IF;

        SELECT COUNT(*)
        INTO v_cuentas_validas
        FROM auth.users AS u
        JOIN seguridad.perfil AS p
            ON p.usuario_id = u.id
        JOIN seguridad.rol AS r
            ON r.id = p.rol_id
        WHERE p.activo
          AND (
              (lower(u.email) = 'admin.demo@example.test'
                  AND r.codigo = 'ADMINISTRADOR')
              OR
              (lower(u.email) = 'manicurista.demo@example.test'
                  AND r.codigo = 'MANICURISTA')
          );

        IF v_cuentas_validas <> 2 THEN
            RAISE EXCEPTION
                'D11: las cuentas demo no tienen los roles activos esperados.';
        END IF;

        RAISE NOTICE
            'D11: cuentas Administradora y Manicurista verificadas.';
    END IF;
END;
$$;


DO $$
DECLARE
    v_admin uuid;
    v_manicurista uuid;
    v_total_entradas integer;
    v_total_salidas integer;
BEGIN
    -- Identificar las cuentas por correo y rol.
    SELECT u.id
    INTO v_admin
    FROM auth.users AS u
    JOIN seguridad.perfil AS p ON p.usuario_id = u.id
    JOIN seguridad.rol AS r ON r.id = p.rol_id
    WHERE lower(u.email) = 'admin.demo@example.test'
      AND p.activo
      AND r.codigo = 'ADMINISTRADOR';

    SELECT u.id
    INTO v_manicurista
    FROM auth.users AS u
    JOIN seguridad.perfil AS p ON p.usuario_id = u.id
    JOIN seguridad.rol AS r ON r.id = p.rol_id
    WHERE lower(u.email) = 'manicurista.demo@example.test'
      AND p.activo
      AND r.codigo = 'MANICURISTA';

    IF v_admin IS NULL OR v_manicurista IS NULL THEN
        RAISE NOTICE
            'D11: no se registran movimientos porque no están disponibles las dos cuentas demo.';
        RETURN;
    END IF;

    -- Evitar que dos ejecuciones del seed procesen los mismos movimientos simultáneamente.
    LOCK TABLE inventario.movimiento IN SHARE ROW EXCLUSIVE MODE;

    -- ================================================================
    -- ENTRADAS: compras realizadas por la Administradora Demo.
    -- ================================================================

    INSERT INTO inventario.movimiento (
        producto_id,
        tipo,
        motivo_id,
        cantidad,
        costo_unitario,
        proveedor_id,
        observacion,
        registrado_por,
        ocurrido_en,
        clave_idempotencia
    )
    SELECT
        p.id,
        'ENTRADA',
        m.id,
        d.cantidad,
        d.costo,
        pr.id,
        d.observacion,
        v_admin,
        CURRENT_TIMESTAMP - make_interval(days => d.dias_atras),
        d.clave::uuid
    FROM (
        VALUES
        ('DEMO-ESM-001', 20, 4500, 'NIT-PRUEBA-001', 28, 'Compra de esmalte rojo', '00000000-0000-4000-8000-000000000001'),
        ('DEMO-ESM-002', 15, 4200, 'NIT-PRUEBA-002', 27, 'Compra de esmalte nude', '00000000-0000-4000-8000-000000000002'),
        ('DEMO-REM-001', 1000, 18, 'NIT-PRUEBA-003', 26, 'Compra de removedor', '00000000-0000-4000-8000-000000000003'),
        ('DEMO-HER-001', 20, 1800, 'NIT-PRUEBA-004', 25, 'Compra de limas profesionales', '00000000-0000-4000-8000-000000000004'),
        ('DEMO-HER-002', 10, 6500, 'NIT-PRUEBA-005', 24, 'Compra de empujadores de cutícula', '00000000-0000-4000-8000-000000000005'),
        ('DEMO-DES-001', 20, 2500, 'NIT-PRUEBA-001', 23, 'Compra de algodón', '00000000-0000-4000-8000-000000000006'),
        ('DEMO-DES-002', 10, 18000, 'NIT-PRUEBA-002', 22, 'Compra de guantes desechables', '00000000-0000-4000-8000-000000000007'),
        ('DEMO-GEL-001', 500, 180, 'NIT-PRUEBA-003', 21, 'Compra de gel constructor', '00000000-0000-4000-8000-000000000008'),
        ('DEMO-GEL-002', 500, 120, 'NIT-PRUEBA-004', 20, 'Compra de acrílico cristal', '00000000-0000-4000-8000-000000000009'),
        ('DEMO-TRA-001', 500, 60, 'NIT-PRUEBA-005', 19, 'Compra de aceite de cutícula', '00000000-0000-4000-8000-000000000010'),
        ('DEMO-TRA-002', 300, 70, 'NIT-PRUEBA-001', 18, 'Compra de fortalecedor de uñas', '00000000-0000-4000-8000-000000000011'),
        ('DEMO-DEC-001', 15, 3200, 'NIT-PRUEBA-002', 17, 'Compra de stickers decorativos', '00000000-0000-4000-8000-000000000012'),
        ('DEMO-HIG-001', 1000, 12, 'NIT-PRUEBA-003', 16, 'Compra de alcohol antiséptico', '00000000-0000-4000-8000-000000000013'),
        ('DEMO-HIG-002', 1000, 20, 'NIT-PRUEBA-004', 15, 'Compra de desinfectante', '00000000-0000-4000-8000-000000000014')
    ) AS d(codigo, cantidad, costo, nit, dias_atras, observacion, clave)
    JOIN inventario.producto AS p ON p.codigo = d.codigo
    JOIN inventario.motivo_movimiento AS m
        ON m.codigo = 'COMPRA'
       AND m.activo
    JOIN inventario.proveedor AS pr
        ON pr.nit = d.nit
       AND pr.activo
    WHERE NOT EXISTS (
        SELECT 1
        FROM inventario.movimiento AS existente
        WHERE existente.clave_idempotencia = d.clave::uuid
    )
    ORDER BY d.dias_atras DESC;

    -- ================================================================
    -- SALIDAS: consumo de productos por servicios de manicura.
    -- ================================================================

    INSERT INTO inventario.movimiento (
        producto_id,
        tipo,
        motivo_id,
        cantidad,
        proveedor_id,
        observacion,
        registrado_por,
        ocurrido_en,
        clave_idempotencia
    )
    SELECT
        p.id,
        'SALIDA',
        m.id,
        d.cantidad,
        NULL,
        d.observacion,
        v_manicurista,
        CURRENT_TIMESTAMP - make_interval(days => d.dias_atras),
        d.clave::uuid
    FROM (
        VALUES
        ('DEMO-ESM-001', 17, 14, 'Consumo de esmalte rojo en servicios', '00000000-0000-4000-8000-000000000015'),
        ('DEMO-ESM-002', 5, 13, 'Consumo de esmalte nude en servicios', '00000000-0000-4000-8000-000000000016'),
        ('DEMO-REM-001', 800, 12, 'Consumo de removedor en servicios', '00000000-0000-4000-8000-000000000017'),
        ('DEMO-HER-001', 5, 11, 'Uso de limas profesionales', '00000000-0000-4000-8000-000000000018'),
        ('DEMO-HER-002', 8, 10, 'Uso de empujadores de cutícula', '00000000-0000-4000-8000-000000000019'),
        ('DEMO-DES-001', 16, 9, 'Consumo de algodón en servicios', '00000000-0000-4000-8000-000000000020'),
        ('DEMO-DES-002', 9, 8, 'Consumo de guantes desechables', '00000000-0000-4000-8000-000000000021'),
        ('DEMO-GEL-001', 350, 7, 'Consumo de gel constructor', '00000000-0000-4000-8000-000000000022'),
        ('DEMO-GEL-002', 450, 6, 'Consumo de acrílico cristal', '00000000-0000-4000-8000-000000000023'),
        ('DEMO-TRA-001', 450, 5, 'Consumo de aceite de cutícula', '00000000-0000-4000-8000-000000000024'),
        ('DEMO-TRA-002', 270, 4, 'Consumo de fortalecedor de uñas', '00000000-0000-4000-8000-000000000025'),
        ('DEMO-DEC-001', 13, 3, 'Consumo de stickers decorativos', '00000000-0000-4000-8000-000000000026'),
        ('DEMO-HIG-001', 900, 2, 'Consumo de alcohol antiséptico', '00000000-0000-4000-8000-000000000027'),
        ('DEMO-HIG-002', 700, 1, 'Consumo de desinfectante', '00000000-0000-4000-8000-000000000028')
    ) AS d(codigo, cantidad, dias_atras, observacion, clave)
    JOIN inventario.producto AS p ON p.codigo = d.codigo
    JOIN inventario.motivo_movimiento AS m
        ON m.codigo = 'CONSUMO_SERVICIO'
       AND m.activo
    WHERE NOT EXISTS (
        SELECT 1
        FROM inventario.movimiento AS existente
        WHERE existente.clave_idempotencia = d.clave::uuid
    )
    ORDER BY d.dias_atras DESC;

    SELECT COUNT(*)
    INTO v_total_entradas
    FROM inventario.movimiento
    WHERE clave_idempotencia BETWEEN
        '00000000-0000-4000-8000-000000000001'::uuid
        AND '00000000-0000-4000-8000-000000000014'::uuid;

    IF v_total_entradas <> 14 THEN
        RAISE EXCEPTION
            'D11: se esperaban 14 entradas y se encontraron %.',
            v_total_entradas;
    END IF;

    SELECT COUNT(*)
    INTO v_total_salidas
    FROM inventario.movimiento
    WHERE clave_idempotencia BETWEEN
        '00000000-0000-4000-8000-000000000015'::uuid
        AND '00000000-0000-4000-8000-000000000028'::uuid;

    IF v_total_salidas <> 14 THEN
        RAISE EXCEPTION
            'D11: se esperaban 14 salidas y se encontraron %.',
            v_total_salidas;
    END IF;

    RAISE NOTICE 'D11: movimientos de demostración procesados.';
END;
$$;


COMMIT;