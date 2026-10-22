-- CRM Comunitario Tucumán · Migración 0002 · Autorización en base de datos (RLS) y auditoría
-- Regla: la API (PostgREST) usa el JWT del usuario; todo acceso pasa por estas políticas.
-- Ocultar un botón en la interfaz NO es control de acceso.

-- ───────────── Funciones de autorización ─────────────
create or replace function app.uid() returns uuid language sql stable as $$ select auth.uid() $$;

create or replace function app.usuario_activo() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from usuarios where id = auth.uid() and activo)
$$;

-- ¿El usuario tiene alguno de estos roles en la institución?
create or replace function app.tiene_rol(inst uuid, roles rol_app[]) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select app.usuario_activo() and exists (
    select 1 from asignaciones_rol a
    where a.usuario_id = auth.uid() and a.institucion_id = inst and a.rol = any(roles))
$$;

create or replace function app.tiene_rol_global(roles rol_app[]) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select app.usuario_activo() and exists (
    select 1 from asignaciones_rol a where a.usuario_id = auth.uid() and a.rol = any(roles))
$$;

create or replace function app.roles_operativos() returns rol_app[] language sql immutable as $$
  select array['admin_operativo','equipo_educativo','coordinacion_comunitaria','equipo_acompanamiento','autoridad_rabinica']::rol_app[]
$$;

-- Ver la ficha básica de una persona: rol operativo en alguna institución con alcance sobre ella.
-- El rol "estadisticas" no ve fichas, solo agregados.
create or replace function app.puede_ver_persona(p uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select app.usuario_activo() and exists (
    select 1 from persona_institucion pi
    join asignaciones_rol a on a.institucion_id = pi.institucion_id
    where pi.persona_id = p and a.usuario_id = auth.uid() and a.rol = any(app.roles_operativos()))
$$;

-- Editar datos de base de la ficha (no incluye a la autoridad rabínica).
create or replace function app.puede_editar_persona(p uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select app.usuario_activo() and exists (
    select 1 from persona_institucion pi
    join asignaciones_rol a on a.institucion_id = pi.institucion_id
    where pi.persona_id = p and a.usuario_id = auth.uid()
      and a.rol in ('admin_operativo','equipo_educativo','coordinacion_comunitaria','equipo_acompanamiento'))
$$;

-- La escolaridad la ven administración operativa y equipo educativo.
create or replace function app.puede_ver_escolaridad(p uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select app.usuario_activo() and exists (
    select 1 from persona_institucion pi
    join asignaciones_rol a on a.institucion_id = pi.institucion_id
    where pi.persona_id = p and a.usuario_id = auth.uid()
      and a.rol in ('admin_operativo','equipo_educativo'))
$$;

create or replace function app.rol_de_tipo(t tipo_programa) returns rol_app language sql immutable as $$
  select case t when 'educacion' then 'equipo_educativo'::rol_app
                when 'comunitario' then 'coordinacion_comunitaria'::rol_app
                else 'equipo_acompanamiento'::rol_app end
$$;

-- Acceso a un programa: administración operativa de la institución, o el equipo del tipo de programa
-- (con asignación general o específica a ese programa).
create or replace function app.puede_programa(prog uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select app.usuario_activo() and exists (
    select 1 from programas pr
    join asignaciones_rol a on a.institucion_id = pr.institucion_id
    where pr.id = prog and a.usuario_id = auth.uid()
      and (a.rol = 'admin_operativo'
           or (a.rol = app.rol_de_tipo(pr.tipo) and (a.programa_id is null or a.programa_id = pr.id))))
$$;

create or replace function app.puede_caso(c uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from casos where id = c and app.puede_programa(programa_id))
$$;

create or replace function app.puede_importar(inst uuid) returns boolean
language sql stable as $$ select app.tiene_rol(inst, array['admin_operativo','equipo_educativo']::rol_app[]) $$;

create or replace function app.puede_ver_hogar(h uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from hogares where id = h and creado_por = auth.uid())
      or exists (select 1 from hogar_integrantes hi where hi.hogar_id = h and app.puede_ver_persona(hi.persona_id))
$$;

-- ───────────── Activar RLS en todas las tablas ─────────────
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- ───────────── Políticas ─────────────
create policy inst_sel on instituciones for select using (app.tiene_rol(id, enum_range(null::rol_app)));
create policy prog_sel on programas for select using (app.tiene_rol(institucion_id, enum_range(null::rol_app)));
create policy prog_adm on programas for all using (app.tiene_rol(institucion_id, array['admin_operativo']::rol_app[]))
  with check (app.tiene_rol(institucion_id, array['admin_operativo']::rol_app[]));
create policy progresp_sel on programa_responsables for select using (app.puede_programa(programa_id));

create policy usu_sel on usuarios for select using (
  id = auth.uid() or exists (
    select 1 from asignaciones_rol a join asignaciones_rol b on a.institucion_id = b.institucion_id
    where a.usuario_id = auth.uid() and b.usuario_id = usuarios.id and a.rol <> 'estadisticas'));
create policy asig_sel on asignaciones_rol for select using (
  usuario_id = auth.uid() or app.tiene_rol(institucion_id, array['admin_operativo']::rol_app[]));
-- La administración operativa gestiona roles de su institución, pero NUNCA puede otorgar el rol rabínico
-- (ni a sí misma). Ese rol se asigna solo por procedimiento de infraestructura documentado.
create policy asig_ins on asignaciones_rol for insert with check (
  rol <> 'autoridad_rabinica' and app.tiene_rol(institucion_id, array['admin_operativo']::rol_app[]));
create policy asig_del on asignaciones_rol for delete using (
  rol <> 'autoridad_rabinica' and app.tiene_rol(institucion_id, array['admin_operativo']::rol_app[]));

create policy fuentes_sel on fuentes for select using (app.tiene_rol(institucion_id, app.roles_operativos()));
create policy fuentes_ins on fuentes for insert with check (app.tiene_rol(institucion_id, array['admin_operativo']::rol_app[]));

create policy lotes_sel on lotes_importacion for select using (app.puede_importar(institucion_id));
create policy filas_sel on filas_importacion for select using (
  exists (select 1 from lotes_importacion l where l.id = lote_id and app.puede_importar(l.institucion_id)));

create policy per_sel on personas for select using (app.puede_ver_persona(id));
create policy per_upd on personas for update using (app.puede_editar_persona(id)) with check (app.puede_editar_persona(id));
-- Altas solo mediante la función crear_persona() (asigna alcance institucional en la misma transacción).

create policy pi_sel on persona_institucion for select using (app.puede_ver_persona(persona_id));

-- Datos de la ficha
create policy mc_sel on medios_contacto for select using (app.puede_ver_persona(persona_id));
create policy mc_ins on medios_contacto for insert with check (app.puede_editar_persona(persona_id));
create policy mc_upd on medios_contacto for update using (app.puede_editar_persona(persona_id));
create policy dom_sel on domicilios for select using (app.puede_ver_persona(persona_id));
create policy dom_ins on domicilios for insert with check (app.puede_editar_persona(persona_id));
create policy dom_upd on domicilios for update using (app.puede_editar_persona(persona_id));
create policy pref_sel on preferencias_contacto for select using (app.puede_ver_persona(persona_id));
create policy pref_ins on preferencias_contacto for insert with check (app.puede_editar_persona(persona_id));
create policy pref_upd on preferencias_contacto for update using (app.puede_editar_persona(persona_id));
create policy vin_sel on vinculos for select using (app.puede_ver_persona(persona_id) and app.puede_ver_persona(persona_relacionada_id));
create policy vin_ins on vinculos for insert with check (app.puede_editar_persona(persona_id) and app.puede_editar_persona(persona_relacionada_id));
create policy vin_upd on vinculos for update using (app.puede_editar_persona(persona_id));

create policy hog_sel on hogares for select using (app.puede_ver_hogar(id));
create policy hog_ins on hogares for insert with check (app.tiene_rol_global(array['admin_operativo','equipo_educativo','coordinacion_comunitaria','equipo_acompanamiento']::rol_app[]) and creado_por = auth.uid());
create policy hog_upd on hogares for update using (app.puede_ver_hogar(id));
create policy hi_sel on hogar_integrantes for select using (app.puede_ver_persona(persona_id));
create policy hi_ins on hogar_integrantes for insert with check (app.puede_editar_persona(persona_id) and app.puede_ver_hogar(hogar_id));
create policy hi_upd on hogar_integrantes for update using (app.puede_editar_persona(persona_id));

create policy esc_sel on escolaridad for select using (app.puede_ver_escolaridad(persona_id));
create policy esc_ins on escolaridad for insert with check (app.puede_ver_escolaridad(persona_id));
create policy esc_upd on escolaridad for update using (app.puede_ver_escolaridad(persona_id));

create policy par_sel on participaciones for select using (app.puede_programa(programa_id) and app.puede_ver_persona(persona_id));
create policy par_ins on participaciones for insert with check (app.puede_programa(programa_id) and app.puede_ver_persona(persona_id));
create policy par_upd on participaciones for update using (app.puede_programa(programa_id));
create policy parh_sel on participacion_historial for select using (
  exists (select 1 from participaciones p where p.id = participacion_id and app.puede_programa(p.programa_id)));

create policy etapas_sel on catalogo_etapas for select using (auth.uid() is not null);

-- Casos: si no tenés acceso al programa, el caso no existe para vos (ni su resumen ni su motivo).
create policy caso_sel on casos for select using (app.puede_programa(programa_id) and (persona_id is null or app.puede_ver_persona(persona_id)));
create policy caso_ins on casos for insert with check (app.puede_programa(programa_id) and (persona_id is null or app.puede_ver_persona(persona_id)));
create policy caso_upd on casos for update using (app.puede_programa(programa_id)) with check (app.puede_programa(programa_id));
create policy casoh_sel on caso_historial for select using (app.puede_caso(caso_id));

create policy int_sel on interacciones for select using (app.puede_programa(programa_id) and app.puede_ver_persona(persona_id));
create policy int_ins on interacciones for insert with check (
  app.puede_programa(programa_id) and app.puede_ver_persona(persona_id) and usuario_id = auth.uid()
  and (caso_id is null or app.puede_caso(caso_id)));

create policy bar_sel on barreras for select using (app.puede_caso(caso_id));
create policy bar_ins on barreras for insert with check (app.puede_caso(caso_id));

create policy tar_sel on tareas for select using (app.puede_caso(caso_id));
create policy tar_ins on tareas for insert with check (app.puede_caso(caso_id));
create policy tar_upd on tareas for update using (app.puede_caso(caso_id)) with check (app.puede_caso(caso_id));

create policy cand_sel on candidatos_duplicado for select using (app.puede_ver_persona(persona_a) and app.puede_ver_persona(persona_b));
create policy fus_sel on fusiones for select using (app.puede_ver_persona(conservada_id));
create policy disc_sel on discrepancias for select using (app.puede_ver_persona(persona_id));
create policy disc_upd on discrepancias for update using (app.puede_editar_persona(persona_id));

create policy sol_sel on solicitudes_titular for select using (app.tiene_rol_global(array['admin_operativo']::rol_app[]) and app.puede_ver_persona(persona_id));
create policy sol_ins on solicitudes_titular for insert with check (app.tiene_rol_global(array['admin_operativo']::rol_app[]) and app.puede_ver_persona(persona_id));
create policy sol_upd on solicitudes_titular for update using (app.tiene_rol_global(array['admin_operativo']::rol_app[]) and app.puede_ver_persona(persona_id));

create policy aud_sel on auditoria for select using (app.tiene_rol_global(array['admin_operativo']::rol_app[]));

-- ───────────── Permisos de API ─────────────
-- Supabase otorga por defecto TODOS los privilegios (incluido TRUNCATE, que ignora RLS) a anon y authenticated:
-- se quitan y se otorga solo lo necesario.
revoke all on all tables in schema public from anon, authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon;
grant select, insert, update on all tables in schema public to authenticated;
grant delete on asignaciones_rol to authenticated;
revoke insert, update on auditoria, fusiones, fusion_movimientos, candidatos_duplicado, lotes_importacion,
  filas_importacion, persona_institucion, caso_historial, participacion_historial from authenticated;
revoke insert on personas from authenticated;
grant usage on all sequences in schema public to authenticated;
revoke all on schema app from public;
grant usage on schema app to authenticated;
grant execute on all functions in schema app to authenticated;

-- ───────────── Auditoría y marcas de tiempo ─────────────
create or replace function app.auditar() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare campos text[]; reg uuid;
begin
  if tg_op = 'UPDATE' then
    select array_agg(n.key) into campos
    from jsonb_each(to_jsonb(new)) n join jsonb_each(to_jsonb(old)) o using (key)
    where n.value is distinct from o.value and n.key not in ('actualizado_en');
    if campos is null then return new; end if;
    reg := (to_jsonb(new)->>'id')::uuid;
  elsif tg_op = 'INSERT' then reg := (to_jsonb(new)->>'id')::uuid;
  else reg := (to_jsonb(old)->>'id')::uuid;
  end if;
  insert into auditoria (usuario_id, tabla, registro_id, accion, campos)
  values (auth.uid(), tg_table_name, reg, lower(tg_op), campos);
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['personas','medios_contacto','domicilios','vinculos','hogares','hogar_integrantes',
    'escolaridad','participaciones','casos','interacciones','tareas','preferencias_contacto','discrepancias',
    'asignaciones_rol','fuentes','solicitudes_titular'] loop
    execute format('create trigger aud_%1$s after insert or update or delete on public.%1$I
                    for each row execute function app.auditar()', t);
  end loop;
end $$;

create or replace function app.tocar_actualizado() returns trigger language plpgsql as $$
begin new.actualizado_en := now(); return new; end $$;
create trigger t_personas_upd before update on personas for each row execute function app.tocar_actualizado();
create trigger t_casos_upd before update on casos for each row execute function app.tocar_actualizado();
create trigger t_part_upd before update on participaciones for each row execute function app.tocar_actualizado();
