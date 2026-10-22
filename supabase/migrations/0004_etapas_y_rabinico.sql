-- CRM Comunitario Tucumán · Migración 0004 · Recorridos por programa y módulo rabínico

-- ───────────── Recorridos (no hay un embudo único) ─────────────
insert into catalogo_etapas (tipo_programa, codigo, nombre, orden, estado_resultante, requiere_motivo) values
  ('educacion','pendiente','Pendiente',1,'abierto',false),
  ('educacion','contacto_intentado','Contacto intentado',2,'abierto',false),
  ('educacion','conversacion_realizada','Conversación realizada',3,'abierto',false),
  ('educacion','interes_comunicado','Interés comunicado',4,'abierto',false),
  ('educacion','entrevista_propuesta','Entrevista propuesta',5,'abierto',false),
  ('educacion','entrevista_realizada','Entrevista realizada',6,'abierto',false),
  ('educacion','inscripcion_confirmada','Inscripción confirmada',7,'cerrado',false),
  ('educacion','pausado','Seguimiento pausado',8,'pausado',true),
  ('educacion','cerrado','Seguimiento cerrado',9,'cerrado',true),

  ('comunitario','invitacion_pendiente','Invitación pendiente',1,'abierto',false),
  ('comunitario','invitado','Invitación realizada',2,'abierto',false),
  ('comunitario','interes_expresado','Interés expresado',3,'abierto',false),
  ('comunitario','inscripto','Inscripción a actividad',4,'abierto',false),
  ('comunitario','participa','Participa',5,'abierto',false),
  ('comunitario','continuidad','Participación continuada',6,'abierto',false),
  ('comunitario','pausado','Seguimiento pausado',7,'pausado',true),
  ('comunitario','cerrado','Seguimiento cerrado',8,'cerrado',true),

  ('adultos_mayores','ofrecimiento_pendiente','Ofrecimiento pendiente',1,'abierto',false),
  ('adultos_mayores','contacto_ofrecido','Contacto ofrecido',2,'abierto',false),
  ('adultos_mayores','interes_comunicado','Interés o necesidad comunicada',3,'abierto',false),
  ('adultos_mayores','acompanamiento_acordado','Acompañamiento acordado',4,'abierto',false),
  ('adultos_mayores','en_seguimiento','En seguimiento',5,'abierto',false),
  ('adultos_mayores','pausado','Seguimiento pausado',6,'pausado',true),
  ('adultos_mayores','cerrado','Seguimiento cerrado',7,'cerrado',true);

-- ───────────── Módulo rabínico (esquema separado) ─────────────
-- La aplicación NO decide ni infiere condición halájica. Solo registra lo que la autoridad designada consigna.
-- Fuera de búsquedas, tableros, notificaciones y exportaciones ordinarias: ninguna función de "public" lo consulta.
create schema if not exists rabinico;

create table rabinico.vocabulario (
  codigo text primary key,
  descripcion text not null,
  definido_por text not null,             -- autoridad que definió el término
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);

create table rabinico.revisiones (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references public.personas(id),
  estado text not null default 'sin_revision' check (estado in ('sin_revision','pendiente','finalizado')),
  autoridad text not null,
  fecha date,
  referencia_documental text,             -- referencia, no el documento: no cargar documentación sensible hasta habilitar almacenamiento cifrado
  conclusion_codigo text references rabinico.vocabulario(codigo),
  registrado_por uuid not null default auth.uid(),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  check (conclusion_codigo is null or estado = 'finalizado')
);
create index revisiones_persona on rabinico.revisiones (persona_id);

create table rabinico.auditoria (
  id bigint generated always as identity primary key,
  en timestamptz not null default now(),
  usuario_id uuid,
  registro_id uuid,
  accion text not null
);

alter table rabinico.vocabulario enable row level security;
alter table rabinico.revisiones enable row level security;
alter table rabinico.auditoria enable row level security;

create or replace function app.es_autoridad_rabinica() returns boolean language sql stable as $$
  select app.tiene_rol_global(array['autoridad_rabinica']::rol_app[])
$$;

-- Solo la autoridad rabínica. La administración operativa NO tiene acceso funcional.
create policy rab_voc on rabinico.vocabulario for all using (app.es_autoridad_rabinica()) with check (app.es_autoridad_rabinica());
create policy rab_rev on rabinico.revisiones for all
  using (app.es_autoridad_rabinica() and app.puede_ver_persona(persona_id))
  with check (app.es_autoridad_rabinica() and app.puede_ver_persona(persona_id));
create policy rab_aud on rabinico.auditoria for select using (app.es_autoridad_rabinica());

create or replace function rabinico.auditar() returns trigger
language plpgsql security definer set search_path = rabinico, pg_temp as $$
begin
  insert into rabinico.auditoria (usuario_id, registro_id, accion) values (auth.uid(), coalesce(new.id, old.id), lower(tg_op));
  return coalesce(new, old);
end $$;
create trigger aud_revisiones after insert or update or delete on rabinico.revisiones for each row execute function rabinico.auditar();
create trigger t_rev_upd before update on rabinico.revisiones for each row execute function app.tocar_actualizado();

revoke all on schema rabinico from public;
grant usage on schema rabinico to authenticated;
grant select, insert, update on rabinico.vocabulario, rabinico.revisiones to authenticated;
grant select on rabinico.auditoria to authenticated;
-- Nota: este esquema NO debe agregarse a "Exposed schemas" de la API hasta habilitar el módulo (Etapa 2+).
