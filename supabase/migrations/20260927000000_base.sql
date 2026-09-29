-- ════════════════════════════════════════════════════════════════════════════
--  Línea base · Spa de Uñas · Inventario
--  Extensiones y esquema de dominio. Las tablas de negocio llegan en migraciones
--  posteriores (una por historia/entidad), siempre idempotentes.
-- ════════════════════════════════════════════════════════════════════════════
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;   -- gen_random_uuid, hashing
CREATE EXTENSION IF NOT EXISTS citext   WITH SCHEMA extensions;   -- códigos/correos sin distinción de mayúsculas
CREATE EXTENSION IF NOT EXISTS postgis  WITH SCHEMA extensions;   -- capacidades espaciales (sedes, bodegas, analítica territorial)

CREATE SCHEMA IF NOT EXISTS inventario;
COMMENT ON SCHEMA inventario IS 'Dominio de control interno de inventario del spa de uñas (RF-01..RF-20, RN-01..RN-14)';

REVOKE ALL ON SCHEMA inventario FROM PUBLIC;
GRANT USAGE ON SCHEMA inventario TO authenticated, service_role;
