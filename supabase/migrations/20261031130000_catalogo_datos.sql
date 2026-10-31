-- ════════════════════════════════════════════════════════════════════════════
--  D3 · Datos de referencia del catálogo: 8 categorías y 12 unidades de medida
--  Van en una migración y no en seed.sql porque producción también los necesita y
--  porque Supabase ejecuta seed.sql una sola vez: si el archivo cambia, solo
--  actualiza su hash y no vuelve a correrlo.
--  Idempotente: ON CONFLICT DO NOTHING. Los primeros registros coinciden con los
--  datos simulados del frontend (Esmaltes=1, Removedores=2... · UND=1, ML=2, PAR=3).
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO inventario.categoria (nombre, descripcion, orden) VALUES
  ('Esmaltes',               'Esmaltes tradicionales y semipermanentes',      1),
  ('Removedores',            'Acetona y removedores sin acetona',              2),
  ('Herramientas',           'Limas, pinzas y cortaúñas',                      3),
  ('Desechables',            'Guantes, algodón y toallas',                     4),
  ('Geles y acrílicos',      'Geles, polímeros, monómeros y tips',             5),
  ('Tratamientos',           'Bases, fortalecedores, aceites y cremas',        6),
  ('Decoración',             'Piedras, foils, stickers y pigmentos',           7),
  ('Higiene y desinfección', 'Alcohol, desinfectantes y esterilización',       8)
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO inventario.unidad_medida (codigo, nombre, magnitud, admite_decimales) VALUES
  ('UND',   'Unidad',       'CONTEO',  false),
  ('ML',    'Mililitro',    'VOLUMEN', true),
  ('PAR',   'Par',          'CONTEO',  false),
  ('L',     'Litro',        'VOLUMEN', true),
  ('GAL',   'Galón',        'VOLUMEN', true),
  ('OZ',    'Onza fluida',  'VOLUMEN', true),
  ('G',     'Gramo',        'MASA',    true),
  ('KG',    'Kilogramo',    'MASA',    true),
  ('CAJA',  'Caja',         'CONTEO',  false),
  ('PAQ',   'Paquete',      'CONTEO',  false),
  ('ROLLO', 'Rollo',        'CONTEO',  false),
  ('KIT',   'Kit',          'CONTEO',  false)
ON CONFLICT (codigo) DO NOTHING;
