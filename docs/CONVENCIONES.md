# Convenciones de base de datos

- **Una sola fuente de verdad del esquema:** este repositorio. El backend no ejecuta DDL.
- **Migraciones** en `supabase/migrations/AAAAMMDDHHMMSS_descripcion.sql`, inmutables una vez fusionadas en `develop`,
  idempotentes (`IF NOT EXISTS`, `CREATE OR REPLACE`) y compatibles hacia atrás (expand → migrate → contract).
- **Reglas críticas en la base** además de la API (defensa en profundidad, RNF-02):
  `CHECK (cantidad > 0)` (RN-04), `CHECK (stock_actual >= 0)` (RN-06), bloqueo de fila en salidas (RN-05),
  movimiento inmutable con usuario y marca de tiempo (RN-07, RNF-06).
- **RLS** activa en todas las tablas expuestas; políticas por rol.
- **Pruebas SQL** en `tests/sql/NNNN_*_test.sql` con bloques `DO $$ ... ASSERT ... $$`; toda migración trae su prueba.
- **Nomenclatura:** snake_case, singular para tablas de entidad, `id uuid` como PK, `creado_en/actualizado_en timestamptz`.

## Flujo con Supabase CLI

```bash
supabase link --project-ref <ref>
supabase migration new <descripcion>      # crea el archivo con timestamp
supabase db reset                         # local: aplica migraciones + seed
supabase db push                          # staging/producción (lo ejecuta CD con aprobación)
```
