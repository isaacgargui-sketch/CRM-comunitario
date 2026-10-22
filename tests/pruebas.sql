-- Pruebas de aceptación con datos FICTICIOS. Cada bloque falla con excepción si no se cumple el criterio.
\set ON_ERROR_STOP 1
\set admin  '''aaaaaaaa-0000-4000-8000-000000000001'''
\set edu    '''aaaaaaaa-0000-4000-8000-000000000002'''
\set acomp  '''aaaaaaaa-0000-4000-8000-000000000003'''
\set stats  '''aaaaaaaa-0000-4000-8000-000000000004'''
\set rabino '''aaaaaaaa-0000-4000-8000-000000000005'''
\set KEH    '''11111111-1111-4111-8111-111111111111'''
\set MAI    '''22222222-2222-4222-8222-222222222222'''
\set PROG_EDU '''a1111111-1111-4111-8111-111111111111'''
\set PROG_COM '''a2222222-2222-4222-8222-222222222222'''

-- Usuarios ficticios y roles (como superusuario: equivale al procedimiento de infraestructura)
insert into auth.users values (:admin,'admin@demo'),(:edu,'edu@demo'),(:acomp,'acomp@demo'),(:stats,'stats@demo'),(:rabino,'rabino@demo');
insert into usuarios (id, nombre, email) values (:admin,'Ana Admin','admin@demo'),(:edu,'Ernesto Educativo','edu@demo'),
  (:acomp,'Alicia Acompañamiento','acomp@demo'),(:stats,'Sergio Estadísticas','stats@demo'),(:rabino,'Autoridad Rabínica','rabino@demo');
insert into asignaciones_rol (usuario_id, rol, institucion_id) values
  (:admin,'admin_operativo',:KEH),(:admin,'admin_operativo',:MAI),
  (:edu,'equipo_educativo',:MAI),
  (:acomp,'equipo_acompanamiento',:KEH),
  (:stats,'estadisticas',:KEH),(:stats,'estadisticas',:MAI),
  (:rabino,'autoridad_rabinica',:KEH);

create temp table ctx (k text primary key, v uuid);
grant all on ctx to authenticated;

-- ══════════ 1. Importación incompleta (admin, padrón Kehilá autorizado para Kehilá y Maimónides) ══════════
select set_config('request.jwt.claim.sub', :admin, false); set role authenticated;
insert into ctx select 'lote1', public.importacion_preparar(
  jsonb_build_object('fuente_id','f3333333-3333-4333-8333-333333333333','archivo_nombre','padron_demo.xlsx',
    'archivo_sha256','sha-padron-1','proposito','Mapeo comunitario y acercamiento','fecha_datos','2026-03-01',
    'instituciones_autorizadas', jsonb_build_array(:KEH, :MAI)),
  '[{"nombres":"Sara","apellidos":"Levy","fecha_nacimiento":"10/03/2014","telefono":"0381 15 555-1111","email":"Familia.Levy@example.com","direccion":"Las Piedras 100"},
    {"nombres":"David","apellidos":"Levy","fecha_nacimiento":"2016-05-02","telefono":"381-5551111"},
    {"nombres":"Raquel","apellidos":"Levy","fecha_nacimiento":"1985","telefono":"+54 9 381 555 1111"},
    {"nombres":"","apellidos":"SinNombre","telefono":"123"},
    {"nombres":"Jacobo","apellidos":"Cohen"},
    {"nombres":"Mirta","apellidos":"Benarroch","fecha_nacimiento":"01/07/1950","telefono":"4221234"},
    {"nombres":"Sara","apellidos":"Levy","fecha_nacimiento":"2014-03-10","telefono":"(0381) 155551111","email":"familia.levy@example.com","direccion":"Las Piedras 100"},
    {"nombres":"Tomás","apellidos":"Halac","fecha_nacimiento":"45/13/2012"}]'::jsonb);
do $$ declare r record; begin
  select count(*) filter (where cardinality(errores)>0) e, count(*) filter (where decision='omitir') o,
         count(*) filter (where decision is null and cardinality(errores)=0) pend
  into r from filas_importacion where lote_id = (select v from ctx where k='lote1');
  assert r.e = 1, 'debe haber 1 fila con error (sin nombre)';
  assert r.o = 1, 'la fila idéntica dentro del archivo debe omitirse';
  assert r.pend = 0, 'sin filas pendientes: no hay coincidencias previas';
end $$;
select public.importacion_confirmar((select v from ctx where k='lote1'));
do $$ declare n int; begin
  select count(*) into n from personas; assert n = 6, format('esperaba 6 personas, hay %s', n);
  select count(*) into n from personas where nombres='Jacobo' and fecha_nacimiento is null; assert n = 1, 'alta incompleta';
  select count(*) into n from personas where nombres='Tomás' and fecha_nacimiento is null; assert n = 1, 'fecha inválida queda sin dato';
  select count(*) into n from medios_contacto where valor_normalizado = '+543815551111'; assert n = 3, 'teléfono compartido por 3 personas';
  select count(*) into n from candidatos_duplicado; assert n = 0, 'teléfono compartido NO genera candidato de fusión';
  select count(*) into n from medios_contacto where valor_normalizado = '+543814221234'; assert n = 1, 'número de 7 dígitos con área asumida';
  select count(*) into n from public.importacion_informe((select v from ctx where k='lote1')); assert n >= 3, 'informe de errores y advertencias';
end $$;

-- ══════════ 2. Reimportación sin duplicación ══════════
do $$ begin
  begin
    perform public.importacion_preparar(jsonb_build_object('fuente_id','f3333333-3333-4333-8333-333333333333',
      'archivo_nombre','padron_demo.xlsx','archivo_sha256','sha-padron-1','proposito','x'), '[{"nombres":"X"}]');
    raise exception 'debió rechazar el mismo archivo';
  exception when sqlstate 'P0001' then null; end;
end $$;
insert into ctx select 'lote2', public.importacion_preparar(
  jsonb_build_object('fuente_id','f3333333-3333-4333-8333-333333333333','archivo_nombre','padron_demo_v2.csv',
    'archivo_sha256','sha-padron-2','proposito','Mapeo comunitario y acercamiento','fecha_datos','2026-04-01',
    'instituciones_autorizadas', jsonb_build_array(:KEH, :MAI)),
  '[{"nombres":"Sara","apellidos":"Levy","fecha_nacimiento":"10/03/2014","telefono":"0381 15 555-1111","email":"Familia.Levy@example.com","direccion":"Las Piedras 100"},
    {"nombres":"Ana","apellidos":"Levy","fecha_nacimiento":"2019-08-08","telefono":"3815551111"},
    {"nombres":"Bruno","apellidos":"Prueba","telefono":"3815559999"}]'::jsonb);
do $$ declare r record; begin
  select * into r from filas_importacion where lote_id=(select v from ctx where k='lote2') and nro_fila=1;
  assert r.decision='vincular' and r.repetida_de_persona is not null, 'fila ya importada se vincula, no se duplica';
  select * into r from filas_importacion where lote_id=(select v from ctx where k='lote2') and nro_fila=2;
  assert r.decision='crear', 'compartir teléfono no bloquea ni fusiona';
  assert r.candidatos::text like '%Comparte teléfono%', 'se informa el teléfono compartido';
end $$;
select public.importacion_confirmar((select v from ctx where k='lote2'));
do $$ declare n int; begin
  select count(*) into n from personas; assert n = 8, format('esperaba 8 personas tras reimportar, hay %s', n);
  select count(*) into n from medios_contacto m join personas p on p.id=m.persona_id where p.nombres='Sara'; assert n = 2, 'no duplica contactos de Sara';
end $$;

-- ══════════ 3. Reversión de lote que preserva datos posteriores ══════════
update medios_contacto set estado='confirmado', verificado_por=auth.uid(), verificado_en=now()
  where valor_normalizado='+543815559999';
do $$ declare j jsonb; n int; begin
  j := public.revertir_lote((select v from ctx where k='lote2'), 'Prueba de reversión');
  assert (j->>'personas_eliminadas')::int = 1, 'Ana (sin datos posteriores) se elimina';
  assert (j->>'personas_conservadas_por_datos_posteriores')::int = 1, 'Bruno (contacto verificado) se conserva';
  select count(*) into n from personas where nombres='Sara'; assert n = 1, 'Sara intacta';
end $$;

-- ══════════ 4. Matrícula Maimónides (equipo educativo) y escolaridad ══════════
reset role; select set_config('request.jwt.claim.sub', :edu, false); set role authenticated;
do $$ declare n int; begin
  select count(*) into n from personas; assert n = 7, format('educativo ve las 7 fichas autorizadas a Maimónides, ve %s', n);
end $$;
insert into ctx select 'lote3', public.importacion_preparar(
  jsonb_build_object('fuente_id','f4444444-4444-4444-8444-444444444444','archivo_nombre','matricula_2026.csv',
    'archivo_sha256','sha-mat-2026','proposito','Cotejo de escolaridad','fecha_datos','2026-03-15',
    'instituciones_autorizadas', jsonb_build_array(:MAI), 'tipo','matricula','matricula_escuela','Colegio Maimónides',
    'matricula_categoria','maimonides','matricula_ciclo',2026),
  '[{"nombres":"Tomás","apellidos":"Halac","nivel":"secundario","grado_sala":"2° año"},
    {"nombres":"Lea","apellidos":"Sasson","fecha_nacimiento":"2018-02-02","nivel":"primario","grado_sala":"2° grado"}]'::jsonb);
do $$ declare f uuid; p uuid; begin
  select id into f from filas_importacion where lote_id=(select v from ctx where k='lote3') and nro_fila=1;
  assert (select decision from filas_importacion where id=f) is null, 'mismo nombre exige revisión manual';
  select id into p from personas where nombres='Tomás';
  perform public.importacion_resolver_fila(f, 'vincular', p);
end $$;
select public.importacion_confirmar((select v from ctx where k='lote3'));
do $$ declare e record; s uuid; begin
  select * into e from public.estado_escolar((select id from personas where nombres='Tomás'), 2026);
  assert e.estado = 'Matrícula confirmada en Maimónides', e.estado;
  s := (select id from personas where nombres='Sara');
  select * into e from public.estado_escolar(s, 2026);
  assert e.estado = 'Escolaridad sin verificar' and e.detalle = 'No encontrado en la matrícula importada de 15/03/2026', coalesce(e.detalle,'sin detalle');
  insert into escolaridad (persona_id, ciclo_lectivo, escuela_nombre, categoria, nivel, grado_sala, estado, verificado_por, verificado_en)
    values (s, 2025, 'Escuela Normal (ficticia)', 'otra', 'primario', '5° grado', 'confirmado', auth.uid(), now()),
           (s, 2026, 'Escuela Normal (ficticia)', 'otra', 'primario', '6° grado', 'confirmado', auth.uid(), now());
  assert (select count(*) from escolaridad where persona_id = s) = 2, 'historial escolar conservado';
  select * into e from public.estado_escolar(s, 2026);
  assert e.estado = 'Escolaridad confirmada en otra escuela', e.estado;
end $$;

-- ══════════ 5. Acercamiento con responsable, vencimiento y adulto responsable ══════════
do $$ declare s uuid; r uuid; c uuid; t uuid; begin
  s := (select id from personas where nombres='Sara'); r := (select id from personas where nombres='Raquel');
  insert into vinculos (persona_id, persona_relacionada_id, categoria, detalle) values
    (s, r, 'parentesco', 'madre'), (s, r, 'adulto_responsable', 'madre');
  c := public.abrir_caso(s, 'a1111111-1111-4111-8111-111111111111', 'Familia con hija en edad escolar sin escolaridad judía confirmada',
       auth.uid(), 'Llamar a la madre para presentar la propuesta', current_date + 3);
  insert into ctx values ('caso', c);
  begin
    insert into tareas (caso_id, accion, vence_el) values (c, 'Sin responsable', current_date);
    raise exception 'tarea sin responsable no debe aceptarse';
  exception when not_null_violation then null; end;
  begin
    insert into tareas (caso_id, responsable_id, accion) values (c, auth.uid(), 'Sin fecha');
    raise exception 'tarea sin vencimiento no debe aceptarse';
  exception when not_null_violation then null; end;
  begin
    perform public.registrar_interaccion(jsonb_build_object('caso_id', c, 'interlocutor_id', s, 'canal','whatsapp',
      'resumen','Mensaje a la menor', 'resultado','mensaje_dejado'));
    raise exception 'no debe registrar contacto directo con menor';
  exception when sqlstate 'P0003' then null; end;
  t := (select id from tareas where caso_id = c and estado='pendiente');
  perform public.registrar_interaccion(jsonb_build_object('caso_id', c, 'interlocutor_id', r, 'canal','telefono',
    'resumen','Se presentó la propuesta; la madre pidió información sobre aranceles.', 'resultado','conversacion',
    'nueva_etapa','interes_comunicado', 'barreras', jsonb_build_array(jsonb_build_object('tipo','costo')),
    'completar_tarea_id', t, 'proxima_tarea', jsonb_build_object('accion','Enviar información y proponer entrevista','vence_el', current_date + 7)));
  assert (select etapa from casos where id = c) = 'interes_comunicado', 'etapa actualizada';
  assert (select estado from tareas where id = t) = 'cumplida', 'tarea cumplida';
  assert (select count(*) from tareas where caso_id = c and estado = 'pendiente') = 1, 'próximo paso con responsable y fecha';
  assert (select count(*) from caso_historial where caso_id = c) = 2, 'historial de etapas';
  assert (select count(*) from barreras where caso_id = c) = 1, 'barrera comunicada';
end $$;

-- ══════════ 6. Restricciones efectivas vía API (RLS) ══════════
reset role; select set_config('request.jwt.claim.sub', :acomp, false); set role authenticated;
do $$ declare n int; begin
  select count(*) into n from casos; assert n = 0, 'acompañamiento no ve casos educativos';
  select count(*) into n from interacciones; assert n = 0, 'ni sus interacciones';
  select count(*) into n from escolaridad; assert n = 0, 'ni la escolaridad';
  select count(*) into n from personas; assert n > 0, 'sí ve fichas de la Kehilá';
  begin
    insert into interacciones (programa_id, caso_id, persona_id, canal, usuario_id, resumen, resultado)
    values ('a1111111-1111-4111-8111-111111111111', (select v from ctx where k='caso'), (select id from personas where nombres='Raquel'),
            'telefono', auth.uid(), 'intento', 'otro');
    raise exception 'no debe poder escribir en programa ajeno';
  exception when insufficient_privilege then null; end;
end $$;
reset role; select set_config('request.jwt.claim.sub', :stats, false); set role authenticated;
do $$ declare n int; begin
  select count(*) into n from personas; assert n = 0, 'estadísticas no ve fichas';
  select count(*) into n from public.indicadores('22222222-2222-4222-8222-222222222222', '2026-01-01', current_date); assert n > 5, 'sí ve agregados';
end $$;

-- ══════════ 7. Módulo rabínico restringido ══════════
reset role; select set_config('request.jwt.claim.sub', :rabino, false); set role authenticated;
insert into rabinico.vocabulario (codigo, descripcion, definido_por) values ('termino_demo', 'Término ficticio de prueba', 'Autoridad demo');
insert into rabinico.revisiones (persona_id, estado, autoridad, fecha) select id, 'pendiente', 'Autoridad demo', current_date from personas where nombres='Mirta';
reset role; select set_config('request.jwt.claim.sub', :admin, false); set role authenticated;
do $$ declare n int; begin
  select count(*) into n from rabinico.revisiones; assert n = 0, 'admin operativo NO ve revisiones rabínicas';
  begin
    insert into asignaciones_rol (usuario_id, rol, institucion_id) values (auth.uid(), 'autoridad_rabinica', '11111111-1111-4111-8111-111111111111');
    raise exception 'admin no debe autoasignarse el rol rabínico';
  exception when insufficient_privilege then null; end;
end $$;

-- ══════════ 8. No contacto y exportación ══════════
do $$ declare j uuid; c uuid; n int; begin
  j := (select id from personas where nombres='Jacobo');
  insert into preferencias_contacto (persona_id, canal, permitido, proposito, fuente, registrado_por)
    values (j, 'todos', false, 'Pidió no ser contactado', 'Pedido telefónico', auth.uid());
  c := public.abrir_caso(j, 'a2222222-2222-4222-8222-222222222222', 'Invitación a actividades', auth.uid());
  begin
    perform public.registrar_interaccion(jsonb_build_object('caso_id', c, 'interlocutor_id', j, 'canal','telefono',
      'resumen','Invitación', 'resultado','sin_respuesta'));
    raise exception 'no debe registrar contacto saliente a quien pidió no contacto';
  exception when sqlstate 'P0002' then null; end;
  select count(*) into n from public.exportar_personas('11111111-1111-4111-8111-111111111111') e where e.nombres='Jacobo' and e.no_contactar;
  assert n = 1, 'la exportación marca no contactar';
  assert not exists (select 1 from information_schema.routines r
    join information_schema.parameters p on p.specific_name = r.specific_name
    where r.routine_name='exportar_personas' and p.parameter_mode='OUT' and p.parameter_name ~ 'rabin|halac|conclusion'),
    'la exportación no tiene columnas restringidas';
end $$;

-- ══════════ 9. Fusión auditable y reversible ══════════
do $$ declare a uuid; b uuid; f uuid; begin
  a := (select id from personas where nombres='Mirta');
  b := public.crear_persona('11111111-1111-4111-8111-111111111111','f2222222-2222-4222-8222-222222222222','Mirta','Benaroch');
  assert b is not null, 'alta manual con datos mínimos';
  insert into medios_contacto (persona_id, tipo, valor_original, valor_normalizado) values (b, 'email', 'mirta@example.com', 'mirta@example.com');
  f := public.fusionar_personas(a, b, 'Misma persona: confirmado por teléfono');
  assert (select estado_registro from personas where id=b) = 'fusionado', 'absorbida marcada';
  assert (select count(*) from medios_contacto where persona_id = a) = 2, 'contactos movidos';
  insert into medios_contacto (persona_id, tipo, valor_original, valor_normalizado) values (a, 'telefono', '3815550000', '+543815550000');
  perform public.revertir_fusion(f);
  assert (select estado_registro from personas where id=b) = 'activo', 'absorbida restaurada';
  assert (select count(*) from medios_contacto where persona_id = b) = 1, 'el correo vuelve a su ficha';
  assert (select count(*) from medios_contacto where persona_id = a) = 2, 'el dato posterior a la fusión se conserva';
end $$;

-- ══════════ 10. Coherencia de indicadores con registros ══════════
reset role; select set_config('request.jwt.claim.sub', :edu, false); set role authenticated;
do $$ declare ind bigint; real bigint; begin
  select valor into ind from public.indicadores('22222222-2222-4222-8222-222222222222', '2026-01-01', current_date) where codigo='personas_unicas';
  select count(*) into real from personas p join persona_institucion pi on pi.persona_id=p.id
    where pi.institucion_id='22222222-2222-4222-8222-222222222222' and p.estado_registro='activo';
  assert ind = real, format('personas únicas: indicador %s vs registros %s', ind, real);
  select valor into ind from public.indicadores('22222222-2222-4222-8222-222222222222', '2026-01-01', current_date) where codigo='personas_contacto_intentado';
  select count(distinct coalesce(sobre_persona_id, persona_id)) into real from interacciones where direccion='saliente';
  assert ind = real, format('contactos intentados (personas, no acciones): %s vs %s', ind, real);
  assert (select count(*) from public.tablero_maimonides('a1111111-1111-4111-8111-111111111111', 2026)) >= 4, 'tablero del piloto';
end $$;
reset role;

-- ══════════ 11. Consultas de interfaz respetan permisos ══════════
select set_config('request.jwt.claim.sub', :edu, false); set role authenticated;
do $$ declare s uuid := (select id from personas where nombres='Sara'); begin
  assert (select count(*) from public.buscar_personas('levy')) >= 3, 'búsqueda por apellido';
  assert (select count(*) from public.buscar_personas('381 555 1111')) >= 3, 'búsqueda por teléfono';
  assert (select count(*) from public.cronologia_persona(s)) >= 4, 'cronología completa para el equipo educativo';
  assert (select count(*) from public.mis_tareas()) = 1, 'tareas propias';
  assert (select count(*) from public.responsables_programa('a1111111-1111-4111-8111-111111111111')) = 2, 'responsables posibles';
end $$;
reset role; select set_config('request.jwt.claim.sub', :acomp, false); set role authenticated;
do $$ declare s uuid := (select id from personas where nombres='Raquel'); begin
  assert (select count(*) from public.cronologia_persona(s)) = 0, 'sin acceso al programa: la cronología no revela nada';
  assert (select count(*) from public.responsables_programa('a1111111-1111-4111-8111-111111111111')) = 0, 'no lista responsables de programas ajenos';
end $$;
reset role;

-- ══════════ 12. Sin sesión no hay acceso; TRUNCATE nunca ══════════
set role anon;
do $$ begin
  begin perform 1 from personas; raise exception 'anon no debe leer personas'; exception when insufficient_privilege then null; end;
  begin perform public.buscar_personas('a'); raise exception 'anon no debe ejecutar funciones'; exception when insufficient_privilege then null; end;
end $$;
reset role; select set_config('request.jwt.claim.sub', :admin, false); set role authenticated;
do $$ begin
  begin truncate personas; raise exception 'TRUNCATE no debe estar permitido'; exception when insufficient_privilege then null; end;
  begin delete from interacciones; exception when insufficient_privilege then null; end;
  assert (select count(*) from interacciones) > 0, 'sin política de borrado: el historial no se elimina';
end $$;
reset role;
