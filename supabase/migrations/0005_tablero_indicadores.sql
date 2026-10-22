-- CRM Comunitario Tucumán · Migración 0005 · Vistas, tablero del piloto e indicadores

create or replace view personas_v with (security_invoker = true) as
select p.*, app.edad(p.fecha_nacimiento, p.precision_fecha) as edad,
  exists (select 1 from preferencias_contacto pc where pc.persona_id = p.id and pc.vigente and not pc.permitido and pc.canal = 'todos') as no_contactar
from personas p;
grant select on personas_v to authenticated;

-- Estado escolar de una persona para un ciclo, sin inferencias:
-- la ausencia en un archivo solo se informa como "No encontrado en la matrícula importada de [fecha]".
create or replace function public.estado_escolar(p_persona uuid, p_ciclo int, out estado text, out detalle text)
language plpgsql stable security invoker set search_path = public, app, pg_temp as $$
declare e escolaridad; f date;
begin
  select * into e from escolaridad es where es.persona_id = p_persona and es.ciclo_lectivo = p_ciclo and es.estado = 'confirmado'
  order by case es.categoria when 'maimonides' then 1 when 'otra_judia' then 2 when 'otra' then 3 else 4 end, es.verificado_en desc nulls last
  limit 1;
  if e.id is not null and e.categoria <> 'sin_verificar' then
    estado := case e.categoria when 'maimonides' then 'Matrícula confirmada en Maimónides'
                               when 'otra_judia' then 'Escolaridad confirmada en otra escuela judía'
                               else 'Escolaridad confirmada en otra escuela' end;
    detalle := concat_ws(' · ', e.escuela_nombre, e.grado_sala);
    return;
  end if;
  estado := 'Escolaridad sin verificar';
  select max(l.fecha_datos) into f from lotes_importacion l
  where l.tipo = 'matricula' and l.matricula_categoria = 'maimonides' and l.matricula_ciclo = p_ciclo and l.estado = 'confirmado';
  if f is not null then detalle := 'No encontrado en la matrícula importada de ' || to_char(f, 'DD/MM/YYYY'); end if;
end $$;

create or replace function public.tablero_maimonides(p_programa uuid, p_ciclo int)
returns table (persona_id uuid, nombres text, apellidos text, edad int, precision_fecha precision_fecha,
  escolaridad_estado text, escolaridad_detalle text, caso_id uuid, etapa text, etapa_nombre text, caso_estado estado_caso,
  responsable text, proxima_accion text, vence_el date, adultos_responsables int, no_contactar boolean)
language sql stable security invoker set search_path = public, app, pg_temp as $$
  with pr as (select * from programas where id = p_programa),
  base as (
    select p.*, app.edad(p.fecha_nacimiento, p.precision_fecha, make_date(p_ciclo, 6, 30)) as edad_ref
    from personas p join persona_institucion pi on pi.persona_id = p.id
    join pr on pr.institucion_id = pi.institucion_id
    where p.estado_registro = 'activo')
  select b.id, b.nombres, b.apellidos, b.edad_ref, b.precision_fecha, es.estado, es.detalle,
    c.id, c.etapa, ce.nombre, c.estado, u.nombre, t.accion, t.vence_el,
    (select count(*)::int from vinculos v where v.persona_id = b.id and v.vigente and v.categoria = 'adulto_responsable'),
    exists (select 1 from vinculos v join preferencias_contacto pc on pc.persona_id = v.persona_relacionada_id
            where v.persona_id = b.id and v.vigente and v.categoria = 'adulto_responsable' and pc.vigente and not pc.permitido and pc.canal = 'todos')
  from base b
  cross join pr
  cross join lateral public.estado_escolar(b.id, p_ciclo) es
  left join lateral (select * from casos c where c.persona_id = b.id and c.programa_id = p_programa
                     order by (c.estado = 'cerrado'), c.abierto_en desc limit 1) c on true
  left join catalogo_etapas ce on ce.tipo_programa = c.tipo_programa and ce.codigo = c.etapa
  left join usuarios u on u.id = c.responsable_id
  left join lateral (select accion, vence_el from tareas t where t.caso_id = c.id and t.estado in ('pendiente','en_curso')
                     order by vence_el limit 1) t on true
  where (b.edad_ref is null or b.edad_ref between coalesce(pr.edad_min, 0) and coalesce(pr.edad_max, 200))
  order by b.apellidos nulls last, b.nombres
$$;

-- Indicadores: cada uno con definición, período y denominador explícitos.
-- Agregados accesibles también al rol "estadisticas" (que no ve fichas).
create or replace function public.indicadores(p_institucion uuid, p_desde date, p_hasta date,
  p_programa uuid default null, p_responsable uuid default null)
returns table (codigo text, indicador text, valor bigint, denominador bigint, definicion text)
language plpgsql volatile security definer set search_path = public, app, pg_temp as $$
declare periodo text := to_char(p_desde,'DD/MM/YYYY') || ' a ' || to_char(p_hasta,'DD/MM/YYYY');
  n_personas bigint; n_casos_periodo bigint; n_contactadas bigint; n_tareas_venc_periodo bigint; n_pend bigint; n_abiertos bigint;
begin
  if not app.tiene_rol(p_institucion, enum_range(null::rol_app)) then
    raise exception 'Sin acceso a indicadores de esta institución' using errcode = '42501';
  end if;
  if p_programa is not null and not exists (select 1 from programas where id = p_programa and institucion_id = p_institucion) then
    raise exception 'El programa no pertenece a la institución';
  end if;

  create temp table if not exists _per (id uuid primary key) on commit drop;
  truncate _per;
  insert into _per select p.id from personas p join persona_institucion pi on pi.persona_id = p.id
    where pi.institucion_id = p_institucion and p.estado_registro = 'activo';
  select count(*) into n_personas from _per;

  create temp table if not exists _cas (id uuid primary key, persona_id uuid, estado estado_caso) on commit drop;
  truncate _cas;
  insert into _cas select c.id, c.persona_id, c.estado from casos c join programas pr on pr.id = c.programa_id
    where pr.institucion_id = p_institucion and (p_programa is null or c.programa_id = p_programa)
      and (p_responsable is null or c.responsable_id = p_responsable)
      and c.abierto_en <= p_hasta and (c.cerrado_en is null or c.cerrado_en >= p_desde);
  select count(distinct persona_id) into n_casos_periodo from _cas;

  return query select 'personas_unicas', 'Personas únicas registradas', n_personas, null::bigint,
    'Fichas activas (excluye fusionadas) con alcance en la institución, a la fecha. No es el tamaño de la comunidad: la cobertura de los archivos es desconocida.';

  return query select 'hogares', 'Hogares registrados', count(distinct hi.hogar_id), null::bigint,
    'Hogares con al menos un integrante vigente con alcance en la institución, a la fecha. Solo hogares cargados manualmente: no se deducen por domicilio.'
    from hogar_integrantes hi join _per on _per.id = hi.persona_id where hi.hasta is null;

  return query select 'cobertura_fecha_nacimiento', 'Fichas con fecha de nacimiento', count(*), n_personas,
    'Personas con fecha de nacimiento cargada (cualquier precisión) sobre personas únicas.'
    from personas p join _per on _per.id = p.id where p.fecha_nacimiento is not null;

  return query select 'contacto_utilizable', 'Personas con contacto utilizable', count(*), n_personas,
    'Personas con al menos un teléfono normalizado o correo válido vigente, sin pedido de no contacto total, sobre personas únicas.'
    from _per where exists (select 1 from medios_contacto m where m.persona_id = _per.id and m.vigente and m.valor_normalizado is not null)
      and not exists (select 1 from preferencias_contacto pc where pc.persona_id = _per.id and pc.vigente and not pc.permitido and pc.canal = 'todos');

  return query select 'contacto_verificado_12m', 'Contactos verificados en el último año', count(*), n_personas,
    'Personas con al menos un medio de contacto verificado por un usuario en los últimos 12 meses, sobre personas únicas.'
    from _per where exists (select 1 from medios_contacto m where m.persona_id = _per.id and m.verificado_en >= now() - interval '12 months');

  return query select 'duplicados_pendientes', 'Posibles duplicados por revisar', count(*), null::bigint,
    'Pares de fichas marcados como posible duplicado y aún sin revisar, a la fecha.'
    from candidatos_duplicado cd where cd.estado = 'pendiente'
      and cd.persona_a in (select id from _per) and cd.persona_b in (select id from _per);

  select count(distinct coalesce(i.sobre_persona_id, i.persona_id)) into n_contactadas
  from interacciones i join _cas on _cas.id = i.caso_id
  where i.direccion = 'saliente' and i.fecha::date between p_desde and p_hasta
    and (p_responsable is null or i.usuario_id = p_responsable);

  return query select 'personas_contacto_intentado', 'Personas con contacto intentado', n_contactadas, n_casos_periodo,
    'Personas distintas (no acciones) sobre las que se registró al menos un contacto saliente en el período ' || periodo ||
    ', sobre personas con caso vigente en el período.';

  return query select 'personas_conversacion', 'Personas con conversación realizada', count(distinct coalesce(i.sobre_persona_id, i.persona_id)), n_contactadas,
    'Personas distintas con al menos una interacción con resultado conversación o reunión en el período ' || periodo || ', sobre personas con contacto intentado.'
    from interacciones i join _cas on _cas.id = i.caso_id
    where i.resultado in ('conversacion','reunion') and i.fecha::date between p_desde and p_hasta
      and (p_responsable is null or i.usuario_id = p_responsable);

  return query select 'entrevistas_realizadas', 'Entrevistas realizadas', count(distinct h.caso_id), n_casos_periodo,
    'Casos que pasaron a "Entrevista realizada" en el período ' || periodo || ', sobre personas con caso vigente.'
    from caso_historial h join _cas on _cas.id = h.caso_id
    where h.etapa_nueva = 'entrevista_realizada' and h.en::date between p_desde and p_hasta;

  return query select 'inscripciones_confirmadas', 'Inscripciones confirmadas', count(distinct h.caso_id), n_casos_periodo,
    'Casos que pasaron a "Inscripción confirmada" en el período ' || periodo || '. Que ocurra después de un contacto no prueba que el contacto la haya causado.'
    from caso_historial h join _cas on _cas.id = h.caso_id
    where h.etapa_nueva = 'inscripcion_confirmada' and h.en::date between p_desde and p_hasta;

  return query select 'participacion_activa', 'Personas participando', count(distinct pa.persona_id), null::bigint,
    'Personas con participación inscripta o activa en programas de la institución durante el período ' || periodo || '.'
    from participaciones pa join programas pr on pr.id = pa.programa_id join _per on _per.id = pa.persona_id
    where pr.institucion_id = p_institucion and (p_programa is null or pa.programa_id = p_programa)
      and pa.estado in ('inscripta','activa') and coalesce(pa.desde, p_desde) <= p_hasta and coalesce(pa.hasta, p_hasta) >= p_desde;

  select count(*) into n_tareas_venc_periodo from tareas t join _cas on _cas.id = t.caso_id
  where t.vence_el between p_desde and p_hasta and t.estado <> 'cancelada' and (p_responsable is null or t.responsable_id = p_responsable);
  return query select 'compromisos_cumplidos', 'Compromisos cumplidos', count(*), n_tareas_venc_periodo,
    'Tareas con vencimiento en el período ' || periodo || ' marcadas como cumplidas, sobre tareas no canceladas que vencían en el período.'
    from tareas t join _cas on _cas.id = t.caso_id
    where t.vence_el between p_desde and p_hasta and t.estado = 'cumplida' and (p_responsable is null or t.responsable_id = p_responsable);

  select count(*) into n_pend from tareas t join _cas on _cas.id = t.caso_id
  where t.estado in ('pendiente','en_curso') and (p_responsable is null or t.responsable_id = p_responsable);
  return query select 'compromisos_vencidos', 'Compromisos vencidos', count(*), n_pend,
    'Tareas pendientes o en curso con vencimiento anterior a hoy, sobre todas las tareas pendientes, a la fecha.'
    from tareas t join _cas on _cas.id = t.caso_id
    where t.estado in ('pendiente','en_curso') and t.vence_el < current_date and (p_responsable is null or t.responsable_id = p_responsable);

  select count(*) into n_abiertos from _cas where estado = 'abierto';
  return query select 'casos_sin_proxima_accion', 'Casos abiertos sin próxima acción', count(*), n_abiertos,
    'Casos abiertos sin ninguna tarea pendiente o en curso, sobre casos abiertos, a la fecha.'
    from _cas where estado = 'abierto' and not exists (select 1 from tareas t where t.caso_id = _cas.id and t.estado in ('pendiente','en_curso'));
end $$;

grant execute on function public.estado_escolar(uuid,int), public.tablero_maimonides(uuid,int),
  public.indicadores(uuid,date,date,uuid,uuid) to authenticated;
