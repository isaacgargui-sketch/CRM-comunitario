-- Datos base FICTICIOS para desarrollo y demostración. No usar con datos reales.
insert into instituciones (id, nombre) values
  ('11111111-1111-4111-8111-111111111111', 'Kehilá Sefaradí de Tucumán'),
  ('22222222-2222-4222-8222-222222222222', 'Colegio Maimónides de Tucumán')
on conflict do nothing;

insert into programas (id, institucion_id, nombre, tipo, objetivos, edad_min, edad_max) values
  ('a1111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 'Acercamiento Maimónides', 'educacion',
   'Acercar a Maimónides a familias con hijos que no asisten a una escuela judía.', 2, 17),
  ('a2222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111111', 'Vida comunitaria', 'comunitario',
   'Invitar a familias a participar en la vida comunitaria.', null, null),
  ('a3333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111', 'Acompañamiento a adultos mayores', 'adultos_mayores',
   'Ofrecer actividades y acompañamiento según intereses y necesidades confirmadas.', 65, null)
on conflict do nothing;

insert into fuentes (id, institucion_id, nombre, proposito_autorizado, autorizacion_referencia) values
  ('f1111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 'Carga manual Maimónides',
   'Seguimiento institucional de familias', 'Pendiente de acta institucional'),
  ('f2222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111111', 'Carga manual Kehilá',
   'Seguimiento institucional de socios y familias', 'Pendiente de acta institucional'),
  ('f3333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111', 'Padrón Kehilá (ficticio)',
   'Mapeo comunitario y acercamiento educativo y comunitario', 'Demo: autorización ficticia'),
  ('f4444444-4444-4444-8444-444444444444', '22222222-2222-4222-8222-222222222222', 'Matrícula Maimónides (ficticia)',
   'Cotejo de escolaridad para el piloto', 'Demo: autorización ficticia')
on conflict do nothing;
