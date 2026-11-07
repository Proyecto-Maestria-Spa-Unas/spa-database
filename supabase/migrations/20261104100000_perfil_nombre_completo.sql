
-- ============================================================
-- B5/B6: incorporar nombre_completo al perfil de identidad
-- Contrato identidad-v1:
--   - Tipo: varchar(120)
--   - Obligatorio: NOT NULL
--   - Longitud mínima: 3 caracteres
--
-- Se completa la información de perfiles existentes antes
-- de establecer la restricción NOT NULL.
-- No se modifican migraciones anteriores.
-- ============================================================

-- 1. Agregar la columna inicialmente nullable.
ALTER TABLE seguridad.perfil
ADD COLUMN IF NOT EXISTS nombre_completo varchar(120);

-- 2. Completar los perfiles existentes.
-- Prioridad:
--   a) nombre_completo de metadata
--   b) full_name de metadata
--   c) name de metadata
--   d) parte del correo anterior a @
--   e) identificador temporal del usuario
--
-- IMPORTANTE:
-- Los valores de respaldo son datos técnicos provisionales.
-- Deben sustituirse por nombres reales cuando estén disponibles.

UPDATE seguridad.perfil AS pe
SET nombre_completo = COALESCE(
    (
        SELECT CASE
            WHEN char_length(trim(candidato.nombre)) BETWEEN 3 AND 120
                THEN trim(candidato.nombre)
        END
        FROM (
            SELECT COALESCE(
                NULLIF(trim(u.raw_user_meta_data->>'nombre_completo'), ''),
                NULLIF(trim(u.raw_user_meta_data->>'full_name'), ''),
                NULLIF(trim(u.raw_user_meta_data->>'name'), ''),
                NULLIF(trim(split_part(COALESCE(u.email, ''), '@', 1)), '')
            ) AS nombre
            FROM auth.users AS u
            WHERE u.id = pe.usuario_id
        ) AS candidato
    ),
    'Usuario ' || left(pe.usuario_id::text, 8)
)
WHERE pe.nombre_completo IS NULL;

-- 3. Establecer la obligatoriedad de la columna.
ALTER TABLE seguridad.perfil
ALTER COLUMN nombre_completo SET NOT NULL;

-- 4. Agregar la restricción de longitud mínima.
-- varchar(120) garantiza el límite máximo de 120 caracteres.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'perfil_nombre_completo_chk'
          AND conrelid = 'seguridad.perfil'::regclass
    ) THEN
        ALTER TABLE seguridad.perfil
        ADD CONSTRAINT perfil_nombre_completo_chk
        CHECK (char_length(trim(nombre_completo)) >= 3);
    END IF;
END;
$$;

-- 5. Documentar la columna.
COMMENT ON COLUMN seguridad.perfil.nombre_completo IS
'Nombre completo del usuario. Campo obligatorio, entre 3 y 120 caracteres.';
