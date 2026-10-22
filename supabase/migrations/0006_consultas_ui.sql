-- CRM Comunitario Tucumán · Migración 0006 · Consultas para la interfaz (todas respetan RLS: SECURITY INVOKER)

create or replace function public.buscar_personas(q text default null, limite int default 50)
returns table (id uuid, nombres text, apellidos text, nombre_preferido text, fecha_nacimiento date,
  precision_fecha precision_fecha, edad int, telefono text, email text, estado_registro estado_registro, no_contactar boolean)
language sql stable security invoker set search_path = public, app, extensions, pg_temp as $$
  select p.id, p.nombres, p.apellidos, p.nombre_preferido, p.fecha_nacimiento, p.precision_fecha,
    app.edad(p.fecha_nacimiento, p.precision_fecha),
    (select m.valor_original from medios_contacto m where m.persona_id = p.id and m.tipo = 'telefono' and m.vigente order by m.preferido desc, m.creado_en limit 1),
    (select m.valor_original from medios_contacto m where m.persona_id = p.id and m.tipo = 'email' and m.vigente order by m.preferido desc, m.creado_en limit 1),
    p.estado_registro,
    exists (select 1 from preferencias_contacto pc where pc.persona_id = p.id and pc.vigente and not pc.permitido and pc.canal = 'todos')
  from personas p
  where p.estado_registro = 'activo'
    and (app.normalizar_texto(q) is null
         or p.nombre_busqueda like '%' || app.normalizar_texto(q) || '%'
         or extensions.similarity(p.nombre_busqueda, app.normalizar_texto(q)) > 0.35
         or exists (select 1 from medios_contacto m where m.persona_id = p.id
                    and (m.valor_normalizado like '%' || regexp_replace(q, '\D', '', 'g') || '%' and length(regexp_replace(q, '\D', '', 'g')) >= 6
                         or lower(m.valor_original) = lower(btrim(q)))))
  order by case when app.normalizar_texto(q) is null then 0 else 1 - extensions.similarity(p.nombre_busqueda, app.normalizar_texto(q)) end,
           p.apellidos nulls last, p.nombres
  limit least(coalesce(limite, 50), 500)
$$;

create or replace function public.personas_resumen(ids uuid[])
returns table (id uuid, nombre text, fecha_nacimiento date, edad int, telefono text, email text, estado_registro estado_registro)
language sql stable security invoker set search_path = public, app, pg_temp as $$
  select p.id, concat_ws(' ', p.nombres, p.apellidos), p.fecha_nacimiento, app.edad(p.fecha_nacimiento, p.precision_fecha),
    (select string_agg(m.valor_original, ', ') from medios_contacto m where m.persona_id = p.id and m.tipo = 'telefono' and m.vigente),
    (select string_agg(m.valor_original, ', ') from medios_contacto m where m.persona_id = p.id and m.tipo = 'email' and m.vigente),
    p.estado_registro
  from personas p where p.id = any(ids)
$$;

-- Usuarios que pueden ser responsables en un programa (solo si quien consulta tiene acceso al programa)
create or replace function public.responsables_programa(p_programa uuid)
returns table (id uuid, nombre text)
language sql stable security definer set search_path = public, app, pg_temp as $$
  select u.id, u.nombre from usuarios u
  where app.puede_programa(p_programa) and u.activo and app.usuario_tiene_programa(u.id, p_programa)
  order by u.nombre
$$;

create or replace function public.mis_tareas()
returns table (tarea_id uuid, accion text, vence_el date, prioridad prioridad, estado estado_tarea, caso_id uuid,
  programa text, persona_id uuid, persona text, etapa text, vencida boolean)
language sql stable security invoker set search_path = public, pg_temp as $$
  select t.id, t.accion, t.vence_el, t.prioridad, t.estado, c.id, pr.nombre, p.id, concat_ws(' ', p.nombres, p.apellidos),
    ce.nombre, t.vence_el < current_date
  from tareas t join casos c on c.id = t.caso_id join programas pr on pr.id = c.programa_id
  left join personas p on p.id = c.persona_id
  left join catalogo_etapas ce on ce.tipo_programa = c.tipo_programa and ce.codigo = c.etapa
  where t.responsable_id = auth.uid() and t.estado in ('pendiente','en_curso')
  order by t.vence_el, t.prioridad desc
$$;

-- Cronología de la ficha: solo lo que el usuario puede ver (casos de programas ajenos no aparecen)
create or replace function public.cronologia_persona(p_persona uuid)
returns table (fecha timestamptz, tipo text, programa text, caso_id uuid, titulo text, detalle text, usuario text)
language sql stable security invoker set search_path = public, pg_temp as $$
  select i.fecha, 'interaccion', pr.nombre, i.caso_id,
    initcap(i.canal::text) || ' · ' || replace(i.resultado, '_', ' ') ||
      case when i.persona_id <> p_persona then ' (con ' || coalesce(pi.nombres || ' ' || coalesce(pi.apellidos,''), 'otra persona') || ')' else '' end,
    i.resumen, u.nombre
  from interacciones i join programas pr on pr.id = i.programa_id
  left join personas pi on pi.id = i.persona_id left join usuarios u on u.id = i.usuario_id
  where i.persona_id = p_persona or i.sobre_persona_id = p_persona
  union all
  select h.en, 'etapa', pr.nombre, c.id, 'Etapa: ' || coalesce(ce.nombre, h.etapa_nueva), h.motivo, u.nombre
  from caso_historial h join casos c on c.id = h.caso_id join programas pr on pr.id = c.programa_id
  left join catalogo_etapas ce on ce.tipo_programa = c.tipo_programa and ce.codigo = h.etapa_nueva
  left join usuarios u on u.id = h.usuario_id
  where c.persona_id = p_persona
  union all
  select t.completada_en, 'tarea', pr.nombre, c.id, 'Tarea cumplida: ' || t.accion, t.resultado, u.nombre
  from tareas t join casos c on c.id = t.caso_id join programas pr on pr.id = c.programa_id
  left join usuarios u on u.id = t.responsable_id
  where c.persona_id = p_persona and t.estado = 'cumplida'
  order by 1 desc
$$;

create or replace function public.duplicados_pendientes()
returns table (candidato_id uuid, puntaje int, motivos text[], persona_a uuid, nombre_a text, nacimiento_a date,
  persona_b uuid, nombre_b text, nacimiento_b date, creado_en timestamptz)
language sql stable security invoker set search_path = public, pg_temp as $$
  select cd.id, cd.puntaje, cd.motivos, a.id, concat_ws(' ', a.nombres, a.apellidos), a.fecha_nacimiento,
         b.id, concat_ws(' ', b.nombres, b.apellidos), b.fecha_nacimiento, cd.creado_en
  from candidatos_duplicado cd join personas a on a.id = cd.persona_a join personas b on b.id = cd.persona_b
  where cd.estado = 'pendiente' and a.estado_registro = 'activo' and b.estado_registro = 'activo'
  order by cd.puntaje desc, cd.creado_en
$$;

grant execute on all functions in schema public to authenticated;
revoke execute on all functions in schema public from public, anon;

-- Normaliza contactos cargados desde la interfaz (conserva siempre el valor original)
create or replace function app.normalizar_contacto() returns trigger language plpgsql as $$
begin
  if new.valor_normalizado is null then
    new.valor_normalizado := case new.tipo when 'telefono' then (app.normalizar_telefono(new.valor_original)).normalizado
                                           else app.normalizar_email(new.valor_original) end;
  end if;
  return new;
end $$;
create trigger t_normalizar_contacto before insert or update of valor_original on medios_contacto
  for each row execute function app.normalizar_contacto();
