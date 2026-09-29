-- Pruebas de la línea base. Falla la ejecución (ON_ERROR_STOP) si alguna aserción no se cumple.
DO $$
BEGIN
  ASSERT (SELECT count(*) FROM pg_namespace WHERE nspname = 'inventario') = 1,
         'Debe existir el esquema inventario';
  ASSERT (SELECT count(*) FROM pg_extension WHERE extname IN ('pgcrypto', 'citext', 'postgis')) = 3,
         'Deben estar instaladas pgcrypto, citext y postgis';
  ASSERT NOT has_schema_privilege('anon', 'inventario', 'USAGE'),
         'El rol anon no debe tener acceso al esquema inventario';
  ASSERT has_schema_privilege('authenticated', 'inventario', 'USAGE'),
         'El rol authenticated debe tener USAGE sobre inventario';
  RAISE NOTICE '0001_base_test: OK';
END $$;
