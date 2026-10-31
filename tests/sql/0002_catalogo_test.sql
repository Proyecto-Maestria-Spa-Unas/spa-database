-- D2 y D3 · Estructura, seguridad y seed del catálogo.
DO $$
BEGIN
  ASSERT to_regclass('inventario.categoria')     IS NOT NULL, 'Falta inventario.categoria';
  ASSERT to_regclass('inventario.unidad_medida') IS NOT NULL, 'Falta inventario.unidad_medida';
  ASSERT to_regclass('inventario.producto')      IS NOT NULL, 'Falta inventario.producto';

  ASSERT (SELECT attgenerated FROM pg_attribute
          WHERE attrelid = 'inventario.producto'::regclass AND attname = 'estado') = 's',
         'producto.estado debe ser columna generada (RN-08..RN-11)';
  ASSERT (SELECT count(*) FROM pg_attribute
          WHERE attrelid = 'inventario.producto'::regclass
            AND attname IN ('version', 'costo_promedio') AND NOT attisdropped) = 2,
         'producto debe tener version y costo_promedio';

  ASSERT (SELECT bool_and(relrowsecurity) FROM pg_class
          WHERE oid IN ('inventario.categoria'::regclass, 'inventario.unidad_medida'::regclass,
                        'inventario.producto'::regclass)),
         'RLS debe estar activa en las tres tablas del catálogo';

  ASSERT NOT has_table_privilege('anon', 'inventario.producto', 'SELECT'), 'anon no debe leer productos';
  ASSERT has_table_privilege('authenticated', 'inventario.producto', 'SELECT'), 'authenticated debe leer productos';
  ASSERT NOT has_column_privilege('authenticated', 'inventario.producto', 'stock_actual', 'UPDATE'),
         'El catálogo no debe poder escribir stock_actual';
  ASSERT NOT has_column_privilege('authenticated', 'inventario.producto', 'costo_promedio', 'UPDATE'),
         'El catálogo no debe poder escribir costo_promedio';

  ASSERT (SELECT count(*) FROM inventario.categoria) >= 8, 'El seed debe crear 8 categorías';
  ASSERT (SELECT count(*) FROM inventario.unidad_medida) >= 12, 'El seed debe crear 12 unidades';
  ASSERT (SELECT admite_decimales FROM inventario.unidad_medida WHERE codigo = 'ML'), 'ML admite decimales';
  ASSERT NOT (SELECT admite_decimales FROM inventario.unidad_medida WHERE codigo = 'UND'), 'UND no admite decimales';
  RAISE NOTICE '0002_catalogo_test: OK';
END $$;
