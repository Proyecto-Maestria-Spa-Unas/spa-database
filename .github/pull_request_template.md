## Qué cambia en el esquema

<!-- Tablas, columnas, índices, funciones, triggers, RLS o seeds afectados. -->

Closes #
Historias / reglas: HU- · RN-

## Lista de verificación de S0 · Datos

- [ ] Migración nueva con `npx supabase migration new <descripcion>` (nunca edito una migración ya fusionada)
- [ ] Idempotente: `IF NOT EXISTS`, `ON CONFLICT DO NOTHING`, `CREATE OR REPLACE`
- [ ] Cada tabla nueva con RLS activa y sus `GRANT` mínimos (sin exponer a `anon`)
- [ ] Prueba SQL en `tests/sql/` por cada regla de negocio (RN-xx) que la base garantiza
- [ ] Sin borrado de datos ni `DROP` destructivo; si es inevitable, explico el plan de migración de datos
- [ ] El check `calidad / pipeline` aplicó la migración en PostGIS limpio y en verde
- [ ] Si cambia una tabla o vista que lee un servicio, avisé a su responsable (sección 3 del documento de arquitectura)

Al fusionar en `develop`, el pipeline `cd` aplica el cambio en **staging**. Producción solo con un release aprobado por QA.
