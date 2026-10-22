-- CRM Comunitario Tucumán · Migración 0003 · Lógica de negocio en base de datos
-- Las operaciones compuestas (importar, fusionar, revertir) son funciones SECURITY DEFINER
-- con controles de permiso explícitos. Las operaciones simples respetan RLS (SECURITY INVOKER).

-- ───────────── Normalización ─────────────
-- Teléfono: devuelve una clave de comparación "+54" + 10 dígitos nacionales (sin 0 ni 15).
-- No distingue fijo/móvil: es una clave para comparar, no para marcar. El original siempre se conserva.
create or replace function app.normalizar_telefono(t text, area text default '381',
  out normalizado text, out advertencia text)
language plpgsql immutable as $$
declare d text;
begin
  d := regexp_replace(coalesce(t,''), '\D', '', 'g');
  if d = '' then return; end if;
  if d like '00%' then d := substr(d, 3); end if;
  if d like '54%' and length(d) >= 12 then
    d := substr(d, 3);
    if d like '9%' and length(d) = 11 then d := substr(d, 2); end if;
  end if;
  if d like '0%' then d := substr(d, 2); end if;
  if length(d) = 12 then
    if left(d,2) = '11' and substr(d,3,2) = '15' then d := left(d,2) || substr(d,5);
    elsif substr(d,4,2) = '15' then d := left(d,3) || substr(d,6);
    elsif substr(d,5,2) = '15' then d := left(d,4) || substr(d,7);
    end if;
  end if;
  if length(d) = 9 and left(d,2) = '15' then
    d := area || substr(d,3); advertencia := 'sin código de área, se asumió ' || area;
  elsif length(d) = 7 then
    d := area || d; advertencia := 'sin código de área, se asumió ' || area;
  end if;
  if length(d) = 10 then normalizado := '+54' || d;
  else advertencia := 'formato no reconocido, se conserva el original sin normalizar'; normalizado := null;
  end if;
end $$;

create or replace function app.normalizar_email(t text) returns text language sql immutable as $$
  select case when lower(btrim(coalesce(t,''))) ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then lower(btrim(t)) end
$$;

create or replace function app.parsear_fecha(t text, out fecha date, out prec precision_fecha, out error text)
language plpgsql stable as $$
declare s text := btrim(coalesce(t,'')); m text[];
begin
  if s = '' then return; end if;
  begin
    if s ~ '^\d{4}-\d{2}-\d{2}' then fecha := left(s,10)::date; prec := 'dia';
    elsif s ~ '^\d{1,2}[/.-]\d{1,2}[/.-]\d{4}$' then
      m := regexp_split_to_array(s, '[/.-]'); fecha := make_date(m[3]::int, m[2]::int, m[1]::int); prec := 'dia';
    elsif s ~ '^\d{1,2}[/.-]\d{1,2}[/.-]\d{2}$' then
      error := 'Fecha con año de dos dígitos (' || s || '): completar el año';
    elsif s ~ '^\d{1,2}[/.-]\d{4}$' then
      m := regexp_split_to_array(s, '[/.-]'); fecha := make_date(m[2]::int, m[1]::int, 1); prec := 'mes';
    elsif s ~ '^\d{4}$' then fecha := make_date(s::int, 1, 1); prec := 'anio';
    elsif s ~ '^\d{5}$' then fecha := date '1899-12-30' + s::int; prec := 'dia';  -- número de serie de Excel
    else error := 'Fecha no reconocida (' || s || ')';
    end if;
  exception when others then
    fecha := null; prec := null; error := 'Fecha inválida (' || s || ')';
  end;
  if fecha is not null and (fecha > current_date or fecha < date '1900-01-01') then
    error := 'Fecha fuera de rango (' || s || ')'; fecha := null; prec := null;
  end if;
end $$;

create or replace function app.edad(f date, p precision_fecha, ref date default current_date) returns int
language sql stable as $$
  select case when f is null then null else extract(year from age(ref, f))::int end
$$;

create or replace function public.edad(f date, p precision_fecha) returns int language sql stable as $$ select app.edad(f, p) $$;

-- Sigue la cadena de fusiones hasta la ficha vigente.
create or replace function app.persona_vigente(p uuid) returns uuid
language sql stable security definer set search_path = public, pg_temp as $$
  with recursive c(id, sig, n) as (
    select id, fusionada_en, 0 from personas where id = p
    union all
    select pe.id, pe.fusionada_en, c.n + 1 from personas pe join c on pe.id = c.sig where c.n < 20)
  select id from c where sig is null limit 1
$$;

create or replace function app.usuario_tiene_programa(u uuid, prog uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from programas pr
    join asignaciones_rol a on a.institucion_id = pr.institucion_id
    join usuarios us on us.id = a.usuario_id and us.activo
    where pr.id = prog and a.usuario_id = u
      and (a.rol = 'admin_operativo' or (a.rol = app.rol_de_tipo(pr.tipo) and (a.programa_id is null or a.programa_id = pr.id))))
$$;

create or replace function app.registrar_evento(accion text, tabla text, registro uuid, campos text[] default null)
returns void language sql security definer set search_path = public, pg_temp as $$
  insert into auditoria (usuario_id, tabla, registro_id, accion, campos) values (auth.uid(), tabla, registro, accion, campos)
$$;

-- ───────────── Alta manual con datos mínimos ─────────────
create or replace function public.crear_persona(p_institucion uuid, p_fuente uuid, p_nombres text,
  p_apellidos text default null, p_nombre_preferido text default null, p_fecha text default null)
returns uuid language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_id uuid := gen_random_uuid(); f record;
begin
  if not app.tiene_rol(p_institucion, array['admin_operativo','equipo_educativo','coordinacion_comunitaria','equipo_acompanamiento']::rol_app[]) then
    raise exception 'Sin permiso para dar altas en esta institución' using errcode = '42501';
  end if;
  if not exists (select 1 from fuentes where id = p_fuente and institucion_id = p_institucion) then
    raise exception 'La fuente no pertenece a la institución';
  end if;
  if nullif(btrim(p_nombres), '') is null then raise exception 'El nombre es obligatorio'; end if;
  select * into f from app.parsear_fecha(p_fecha);
  if f.error is not null then raise exception '%', f.error; end if;
  insert into personas (id, nombres, apellidos, nombre_preferido, fecha_nacimiento, precision_fecha,
                        fecha_nacimiento_estado, fuente_alta_id, creado_por)
  values (v_id, btrim(p_nombres), nullif(btrim(p_apellidos),''), nullif(btrim(p_nombre_preferido),''), f.fecha, f.prec,
          (case when f.fecha is null then 'desconocido' else 'pendiente_verificacion' end)::estado_dato, p_fuente, auth.uid());
  insert into persona_institucion (persona_id, institucion_id) values (v_id, p_institucion);
  return v_id;
end $$;

-- ───────────── Posibles duplicados (solo entre fichas visibles para quien importa) ─────────────
create or replace function app.buscar_candidatos(p_nom text, p_ape text, p_fecha date, p_tel text, p_mail text)
returns jsonb language sql stable security definer set search_path = public, app, extensions, pg_temp as $$
  with b as (select app.normalizar_texto(coalesce(p_nom,'') || ' ' || coalesce(p_ape,'')) k),
  c as (
    select p.id, p.nombre_busqueda = b.k as mismo_nombre,
      (p_fecha is not null and p.fecha_nacimiento = p_fecha) as misma_fecha,
      (p_fecha is not null and p.fecha_nacimiento is not null and p.fecha_nacimiento <> p_fecha) as fecha_distinta,
      extensions.similarity(p.nombre_busqueda, b.k) as sim,
      (p_mail is not null and exists (select 1 from medios_contacto m where m.persona_id = p.id and m.tipo = 'email' and m.vigente and m.valor_normalizado = p_mail)) as mismo_mail,
      (p_tel is not null and exists (select 1 from medios_contacto m where m.persona_id = p.id and m.tipo = 'telefono' and m.vigente and m.valor_normalizado = p_tel)) as mismo_tel
    from personas p, b
    where p.estado_registro = 'activo' and app.puede_ver_persona(p.id)
      and (p.nombre_busqueda = b.k
           or (p_fecha is not null and p.fecha_nacimiento = p_fecha and extensions.similarity(p.nombre_busqueda, b.k) > 0.45)
           or (p_mail is not null and exists (select 1 from medios_contacto m where m.persona_id = p.id and m.tipo = 'email' and m.valor_normalizado = p_mail))
           or (p_tel is not null and exists (select 1 from medios_contacto m where m.persona_id = p.id and m.tipo = 'telefono' and m.valor_normalizado = p_tel)))
  )
  select coalesce(jsonb_agg(jsonb_build_object('persona_id', id, 'puntaje', puntaje, 'motivos', motivos) order by puntaje desc), '[]'::jsonb)
  from (
    select id,
      case when mismo_nombre and misma_fecha then 95
           when misma_fecha and sim > 0.45 then 75
           when mismo_nombre and fecha_distinta then 30
           when mismo_nombre then 60
           when mismo_mail and sim > 0.3 then 55
           when mismo_mail then 25
           else 10 end as puntaje,
      array_remove(array[
        case when mismo_nombre then 'Mismo nombre y apellido' end,
        case when not mismo_nombre and sim > 0.45 then 'Nombre similar' end,
        case when misma_fecha then 'Misma fecha de nacimiento' end,
        case when fecha_distinta then 'Fecha de nacimiento distinta' end,
        case when mismo_mail then 'Comparte correo (puede ser de un familiar)' end,
        case when mismo_tel then 'Comparte teléfono (puede ser familiar; no identifica por sí solo)' end], null) as motivos
    from c) x
$$;

-- ───────────── Importación: preparar (previsualización, validación, duplicados) ─────────────
-- meta: {fuente_id, archivo_nombre, archivo_sha256, proposito, fecha_datos, instituciones_autorizadas[],
--        tipo:'personas'|'matricula', matricula_escuela, matricula_categoria, matricula_ciclo}
-- filas: [{nombres, apellidos, telefono, email, direccion, fecha_nacimiento, nivel, grado_sala, _original:{...}}]
create or replace function public.importacion_preparar(meta jsonb, filas jsonb) returns uuid
language plpgsql security definer set search_path = public, app, extensions, pg_temp as $$
declare
  v_fuente fuentes; v_lote uuid; f jsonb; i int := 0;
  v_nom text; v_ape text; tel record; v_mail text; fec record;
  v_err text[]; v_adv text[]; v_norm jsonb; v_hash text; v_cands jsonb; v_rep uuid; v_dec text; v_auth uuid[];
begin
  select * into v_fuente from fuentes where id = (meta->>'fuente_id')::uuid;
  if v_fuente.id is null then raise exception 'Fuente inexistente'; end if;
  if not app.puede_importar(v_fuente.institucion_id) then
    raise exception 'Sin permiso para importar en esta institución' using errcode = '42501';
  end if;
  if nullif(btrim(meta->>'proposito'),'') is null then raise exception 'Indicá el propósito autorizado del archivo'; end if;
  select array_agg(x::uuid) into v_auth from jsonb_array_elements_text(meta->'instituciones_autorizadas') x;
  v_auth := coalesce(v_auth, array[v_fuente.institucion_id]);
  if exists (select 1 from lotes_importacion where fuente_id = v_fuente.id and archivo_sha256 = meta->>'archivo_sha256' and estado = 'confirmado') then
    raise exception 'Este archivo ya fue importado desde esta fuente. No se carga de nuevo.' using errcode = 'P0001';
  end if;
  if jsonb_array_length(filas) = 0 then raise exception 'El archivo no tiene filas'; end if;
  if jsonb_array_length(filas) > 20000 then raise exception 'Máximo 20.000 filas por lote'; end if;

  insert into lotes_importacion (fuente_id, institucion_id, archivo_nombre, archivo_sha256, proposito,
    instituciones_autorizadas, fecha_datos, tipo, matricula_escuela, matricula_categoria, matricula_ciclo, creado_por)
  values (v_fuente.id, v_fuente.institucion_id, meta->>'archivo_nombre', meta->>'archivo_sha256', meta->>'proposito',
    v_auth, coalesce((meta->>'fecha_datos')::date, current_date), coalesce(meta->>'tipo','personas'),
    meta->>'matricula_escuela', (meta->>'matricula_categoria')::categoria_escolaridad, (meta->>'matricula_ciclo')::int, auth.uid())
  returning id into v_lote;

  for f in select value from jsonb_array_elements(filas) loop
    i := i + 1; v_err := '{}'; v_adv := '{}'; v_rep := null; v_cands := '[]'; v_dec := null;
    v_nom := nullif(btrim(f->>'nombres'), ''); v_ape := nullif(btrim(f->>'apellidos'), '');
    if v_nom is null then v_err := v_err || 'Falta el nombre'::text; end if;
    select * into tel from app.normalizar_telefono(f->>'telefono');
    if tel.advertencia is not null then v_adv := v_adv || ('Teléfono: ' || tel.advertencia); end if;
    v_mail := app.normalizar_email(f->>'email');
    if nullif(btrim(f->>'email'),'') is not null and v_mail is null then
      v_adv := v_adv || 'Correo con formato inválido: se conserva el original'::text;
    end if;
    select * into fec from app.parsear_fecha(f->>'fecha_nacimiento');
    if fec.error is not null then v_adv := v_adv || ('Fecha de nacimiento: ' || fec.error || '; queda sin dato'); end if;

    v_norm := jsonb_strip_nulls(jsonb_build_object(
      'nombres', v_nom, 'apellidos', v_ape,
      'telefono', tel.normalizado, 'telefono_original', nullif(btrim(f->>'telefono'),''),
      'email', v_mail, 'email_original', nullif(btrim(f->>'email'),''),
      'direccion', nullif(btrim(f->>'direccion'),''),
      'fecha_nacimiento', fec.fecha, 'precision_fecha', fec.prec,
      'nivel', nullif(btrim(f->>'nivel'),''), 'grado_sala', nullif(btrim(f->>'grado_sala'),'')));
    v_hash := encode(extensions.digest(concat_ws('|', app.normalizar_texto(v_nom), app.normalizar_texto(v_ape), fec.fecha,
              tel.normalizado, coalesce(v_mail, app.normalizar_texto(f->>'email')), app.normalizar_texto(f->>'direccion')), 'sha256'), 'hex');

    if cardinality(v_err) = 0 then
      -- ¿La misma fila ya entró desde esta fuente en un lote confirmado? (reimportación)
      select app.persona_vigente(fi.persona_id) into v_rep
      from filas_importacion fi join lotes_importacion l on l.id = fi.lote_id
      where l.fuente_id = v_fuente.id and l.estado = 'confirmado' and fi.hash_fila = v_hash and fi.persona_id is not null
      limit 1;
      if v_rep is not null then
        v_dec := 'vincular'; v_adv := v_adv || 'Ya importada desde esta fuente: se vincula a la ficha existente'::text;
      elsif exists (select 1 from filas_importacion where lote_id = v_lote and hash_fila = v_hash) then
        v_dec := 'omitir'; v_adv := v_adv || 'Fila idéntica a otra del mismo archivo'::text;
      else
        v_cands := app.buscar_candidatos(v_nom, v_ape, fec.fecha, tel.normalizado, v_mail);
        if exists (select 1 from filas_importacion o where o.lote_id = v_lote and cardinality(o.errores) = 0
                   and app.normalizar_texto(concat_ws(' ', o.datos_normalizados->>'nombres', o.datos_normalizados->>'apellidos'))
                       = app.normalizar_texto(concat_ws(' ', v_nom, v_ape))
                   and (fec.fecha is null or o.datos_normalizados->>'fecha_nacimiento' is null
                        or (o.datos_normalizados->>'fecha_nacimiento')::date = fec.fecha)) then
          v_adv := v_adv || 'Mismo nombre que otra fila del archivo: revisar'::text;
        elsif coalesce((select max((c->>'puntaje')::int) from jsonb_array_elements(v_cands) c), 0) < 50 then
          v_dec := 'crear';
        end if;
      end if;
    end if;

    insert into filas_importacion (lote_id, nro_fila, datos_originales, datos_normalizados, hash_fila, errores,
      advertencias, candidatos, repetida_de_persona, decision, persona_destino)
    values (v_lote, i, coalesce(f->'_original', f), v_norm, v_hash, v_err, v_adv, v_cands, v_rep, v_dec, v_rep);
  end loop;
  return v_lote;
end $$;

create or replace function public.importacion_resolver_fila(p_fila uuid, p_decision text, p_persona uuid default null)
returns void language plpgsql security definer set search_path = public, app, pg_temp as $$
declare l lotes_importacion;
begin
  select lo.* into l from lotes_importacion lo join filas_importacion fi on fi.lote_id = lo.id where fi.id = p_fila;
  if l.id is null or not app.puede_importar(l.institucion_id) then raise exception 'Sin acceso' using errcode = '42501'; end if;
  if l.estado <> 'borrador' then raise exception 'El lote ya no admite cambios'; end if;
  if p_decision not in ('crear','vincular','omitir') then raise exception 'Decisión inválida'; end if;
  if p_decision = 'vincular' and (p_persona is null or not app.puede_ver_persona(p_persona)) then
    raise exception 'Elegí una ficha existente visible para vincular';
  end if;
  update filas_importacion set decision = p_decision,
         persona_destino = case when p_decision = 'vincular' then app.persona_vigente(p_persona) end
  where id = p_fila and cardinality(errores) = 0;
end $$;

-- Resolución masiva explícita: SOLO para filas sin decisión. Nunca fusiona.
create or replace function public.importacion_crear_pendientes(p_lote uuid) returns int
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare l lotes_importacion; n int;
begin
  select * into l from lotes_importacion where id = p_lote;
  if l.id is null or not app.puede_importar(l.institucion_id) then raise exception 'Sin acceso' using errcode = '42501'; end if;
  if l.estado <> 'borrador' then raise exception 'El lote ya no admite cambios'; end if;
  update filas_importacion set decision = 'crear' where lote_id = p_lote and decision is null and cardinality(errores) = 0;
  get diagnostics n = row_count; return n;
end $$;

create or replace function public.importacion_cancelar(p_lote uuid) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare l lotes_importacion;
begin
  select * into l from lotes_importacion where id = p_lote;
  if l.id is null or not app.puede_importar(l.institucion_id) then raise exception 'Sin acceso' using errcode = '42501'; end if;
  if l.estado <> 'borrador' then raise exception 'Solo se cancelan lotes en borrador'; end if;
  delete from lotes_importacion where id = p_lote;
end $$;

-- ───────────── Importación: confirmar ─────────────
create or replace function public.importacion_confirmar(p_lote uuid) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  l lotes_importacion; r filas_importacion; n jsonb; v_p uuid; per personas; res resultado_fila;
  pendientes int; c jsonb; v_res jsonb;
begin
  select * into l from lotes_importacion where id = p_lote for update;
  if l.id is null or not app.puede_importar(l.institucion_id) then raise exception 'Sin acceso' using errcode = '42501'; end if;
  if l.estado <> 'borrador' then raise exception 'El lote ya fue procesado'; end if;
  select count(*) into pendientes from filas_importacion where lote_id = p_lote and cardinality(errores) = 0 and decision is null;
  if pendientes > 0 then raise exception 'Quedan % filas con posibles duplicados por revisar', pendientes; end if;
  if exists (select 1 from lotes_importacion where fuente_id = l.fuente_id and archivo_sha256 = l.archivo_sha256 and estado = 'confirmado') then
    raise exception 'Este archivo ya fue importado desde esta fuente.';
  end if;

  for r in select * from filas_importacion where lote_id = p_lote order by nro_fila loop
    n := r.datos_normalizados;
    if cardinality(r.errores) > 0 then
      update filas_importacion set resultado = 'error' where id = r.id; continue;
    end if;
    if r.decision = 'omitir' then
      update filas_importacion set resultado = 'omitida' where id = r.id; continue;
    end if;

    if r.decision = 'crear' then
      v_p := gen_random_uuid();
      insert into personas (id, nombres, apellidos, fecha_nacimiento, precision_fecha, fecha_nacimiento_estado,
                            fuente_alta_id, lote_alta_id, creado_por)
      values (v_p, n->>'nombres', n->>'apellidos', (n->>'fecha_nacimiento')::date, (n->>'precision_fecha')::precision_fecha,
              (case when n ? 'fecha_nacimiento' then 'pendiente_verificacion' else 'desconocido' end)::estado_dato,
              l.fuente_id, l.id, auth.uid());
      res := 'persona_creada';
      -- Coincidencias relevantes quedan para revisión manual (nunca se fusiona automáticamente)
      for c in select value from jsonb_array_elements(r.candidatos) where (value->>'puntaje')::int >= 50 loop
        insert into candidatos_duplicado (persona_a, persona_b, motivos, puntaje, origen_lote_id)
        values (least(v_p, (c->>'persona_id')::uuid), greatest(v_p, (c->>'persona_id')::uuid),
                array(select jsonb_array_elements_text(c->'motivos')), (c->>'puntaje')::int, l.id)
        on conflict do nothing;
      end loop;
    else
      v_p := app.persona_vigente(r.persona_destino);
      res := case when r.repetida_de_persona is not null then 'repetida_en_reimportacion' else 'vinculada_existente' end;
      select * into per from personas where id = v_p;
      -- Completar vacíos; si difiere de lo existente, registrar discrepancia (no se sobrescribe)
      if n ? 'apellidos' then
        if per.apellidos is null then update personas set apellidos = n->>'apellidos' where id = v_p;
        elsif app.normalizar_texto(per.apellidos) <> app.normalizar_texto(n->>'apellidos') then
          insert into discrepancias (persona_id, campo, valor_existente, valor_nuevo, fuente_id, lote_id)
          values (v_p, 'apellidos', per.apellidos, n->>'apellidos', l.fuente_id, l.id);
        end if;
      end if;
      if n ? 'fecha_nacimiento' then
        if per.fecha_nacimiento is null then
          update personas set fecha_nacimiento = (n->>'fecha_nacimiento')::date, precision_fecha = (n->>'precision_fecha')::precision_fecha,
                 fecha_nacimiento_estado = 'pendiente_verificacion' where id = v_p;
        elsif per.fecha_nacimiento <> (n->>'fecha_nacimiento')::date then
          insert into discrepancias (persona_id, campo, valor_existente, valor_nuevo, fuente_id, lote_id)
          values (v_p, 'fecha_nacimiento', per.fecha_nacimiento::text, n->>'fecha_nacimiento', l.fuente_id, l.id);
        end if;
      end if;
    end if;

    insert into persona_institucion (persona_id, institucion_id, lote_id)
    select v_p, x, l.id from unnest(l.instituciones_autorizadas) x on conflict do nothing;

    if n ? 'telefono_original' and not exists (
        select 1 from medios_contacto where persona_id = v_p and tipo = 'telefono'
          and (valor_normalizado = n->>'telefono' or valor_original = n->>'telefono_original')) then
      insert into medios_contacto (persona_id, tipo, valor_original, valor_normalizado, fuente_id, lote_id)
      values (v_p, 'telefono', n->>'telefono_original', n->>'telefono', l.fuente_id, l.id);
    end if;
    if n ? 'email_original' and not exists (
        select 1 from medios_contacto where persona_id = v_p and tipo = 'email'
          and (valor_normalizado = n->>'email' or lower(valor_original) = lower(n->>'email_original'))) then
      insert into medios_contacto (persona_id, tipo, valor_original, valor_normalizado, fuente_id, lote_id)
      values (v_p, 'email', n->>'email_original', n->>'email', l.fuente_id, l.id);
    end if;
    if n ? 'direccion' and not exists (
        select 1 from domicilios where persona_id = v_p and app.normalizar_texto(direccion_original) = app.normalizar_texto(n->>'direccion')) then
      insert into domicilios (persona_id, direccion_original, fuente_id, lote_id) values (v_p, n->>'direccion', l.fuente_id, l.id);
    end if;

    if l.tipo = 'matricula' and not exists (
        select 1 from escolaridad where persona_id = v_p and ciclo_lectivo = l.matricula_ciclo
          and categoria = l.matricula_categoria and lote_id = l.id) then
      insert into escolaridad (persona_id, ciclo_lectivo, escuela_nombre, categoria, nivel, grado_sala, estado,
                               fuente_id, lote_id, verificado_en, nota, registrado_por)
      values (v_p, l.matricula_ciclo, l.matricula_escuela, l.matricula_categoria,
              case when n->>'nivel' in ('inicial','primario','secundario') then n->>'nivel' when n ? 'nivel' then 'otro' end,
              n->>'grado_sala', 'confirmado', l.fuente_id, l.id, l.fecha_datos::timestamptz,
              'Matrícula importada (' || l.archivo_nombre || ', ' || to_char(l.fecha_datos, 'DD/MM/YYYY') || ')', auth.uid());
    end if;

    update filas_importacion set resultado = res, persona_id = v_p where id = r.id;
  end loop;

  select jsonb_object_agg(coalesce(x.resultado::text,'sin_resultado'), x.cant) into v_res
  from (select resultado, count(*) as cant from filas_importacion where lote_id = p_lote group by 1) x;
  update lotes_importacion set estado = 'confirmado', confirmado_en = now(), resumen = v_res where id = p_lote;
  perform app.registrar_evento('importacion_confirmada', 'lotes_importacion', p_lote);
  return v_res;
end $$;

create or replace function public.importacion_informe(p_lote uuid)
returns table (nro_fila int, resultado text, errores text, advertencias text, datos_originales jsonb)
language sql stable security invoker set search_path = public, pg_temp as $$
  select nro_fila, coalesce(resultado::text, decision, 'pendiente'), array_to_string(errores, '; '),
         array_to_string(advertencias, '; '), datos_originales
  from filas_importacion where lote_id = p_lote
    and (cardinality(errores) > 0 or cardinality(advertencias) > 0)
  order by nro_fila
$$;

-- ───────────── Reversión de lote (preserva modificaciones posteriores válidas) ─────────────
create or replace function public.revertir_lote(p_lote uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare l lotes_importacion; v uuid; borradas int := 0; conservadas uuid[] := '{}'; d1 int; d2 int; d3 int;
begin
  select * into l from lotes_importacion where id = p_lote for update;
  if l.id is null or not app.tiene_rol(l.institucion_id, array['admin_operativo']::rol_app[]) then
    raise exception 'Solo la administración operativa puede revertir lotes' using errcode = '42501';
  end if;
  if l.estado <> 'confirmado' then raise exception 'Solo se revierten lotes confirmados'; end if;
  if nullif(btrim(p_motivo),'') is null then raise exception 'Indicá el motivo de la reversión'; end if;

  -- Datos aportados por el lote que nadie verificó después
  delete from medios_contacto where lote_id = p_lote and verificado_en is null; get diagnostics d1 = row_count;
  delete from domicilios where lote_id = p_lote and verificado_en is null; get diagnostics d2 = row_count;
  delete from escolaridad where lote_id = p_lote and verificado_por is null; get diagnostics d3 = row_count;
  delete from discrepancias where lote_id = p_lote and estado = 'pendiente';
  delete from candidatos_duplicado where origen_lote_id = p_lote and estado = 'pendiente';

  for v in select distinct persona_id from filas_importacion where lote_id = p_lote and resultado = 'persona_creada' and persona_id is not null loop
    if exists (select 1 from personas where id = v and estado_registro <> 'activo')
       or exists (select 1 from medios_contacto where persona_id = v)
       or exists (select 1 from domicilios where persona_id = v)
       or exists (select 1 from escolaridad where persona_id = v)
       or exists (select 1 from vinculos where persona_id = v or persona_relacionada_id = v)
       or exists (select 1 from hogar_integrantes where persona_id = v)
       or exists (select 1 from casos where persona_id = v)
       or exists (select 1 from interacciones where persona_id = v or sobre_persona_id = v)
       or exists (select 1 from participaciones where persona_id = v)
       or exists (select 1 from preferencias_contacto where persona_id = v)
       or exists (select 1 from solicitudes_titular where persona_id = v)
       or exists (select 1 from fusiones where conservada_id = v or absorbida_id = v)
       or exists (select 1 from candidatos_duplicado where (persona_a = v or persona_b = v) and estado <> 'pendiente')
       or exists (select 1 from filas_importacion where persona_id = v and lote_id <> p_lote)
       or exists (select 1 from personas where id = v and actualizado_en > l.confirmado_en + interval '1 minute')
    then
      conservadas := conservadas || v;
    else
      delete from candidatos_duplicado where persona_a = v or persona_b = v;
      delete from discrepancias where persona_id = v;
      delete from persona_institucion where persona_id = v;
      update filas_importacion set persona_id = null where persona_id = v;
      delete from personas where id = v;
      borradas := borradas + 1;
    end if;
  end loop;

  -- Alcance institucional otorgado por este lote a fichas preexistentes: se quita si hay otro alcance
  delete from persona_institucion pi where pi.lote_id = p_lote
    and not (pi.persona_id = any(conservadas))
    and exists (select 1 from persona_institucion o where o.persona_id = pi.persona_id and o.lote_id is distinct from p_lote);

  update lotes_importacion set estado = 'revertido', revertido_en = now(), revertido_por = auth.uid(), motivo_reversion = p_motivo,
    resumen = coalesce(resumen, '{}') || jsonb_build_object('reversion', jsonb_build_object(
      'personas_eliminadas', borradas, 'personas_conservadas_por_datos_posteriores', cardinality(conservadas),
      'contactos_eliminados', d1, 'domicilios_eliminados', d2, 'escolaridades_eliminadas', d3,
      'conservadas', to_jsonb(conservadas)))
  where id = p_lote;
  perform app.registrar_evento('lote_revertido', 'lotes_importacion', p_lote);
  return (select resumen->'reversion' from lotes_importacion where id = p_lote);
end $$;

-- ───────────── Fusión auditada y reversible ─────────────
create or replace function app.columnas_persona() returns text[][] language sql immutable as $$
  select array[
    ['public.medios_contacto','persona_id'], ['public.domicilios','persona_id'], ['public.hogar_integrantes','persona_id'],
    ['public.vinculos','persona_id'], ['public.vinculos','persona_relacionada_id'], ['public.escolaridad','persona_id'],
    ['public.participaciones','persona_id'], ['public.casos','persona_id'], ['public.interacciones','persona_id'],
    ['public.interacciones','sobre_persona_id'], ['public.preferencias_contacto','persona_id'],
    ['public.discrepancias','persona_id'], ['public.solicitudes_titular','persona_id'], ['rabinico.revisiones','persona_id']]
$$;

create or replace function public.fusionar_personas(p_conservada uuid, p_absorbida uuid, p_motivo text) returns uuid
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_f uuid; cols text[][] := app.columnas_persona(); i int; t text; c text; extra text;
begin
  if not (app.puede_ver_persona(p_conservada) and app.puede_ver_persona(p_absorbida)
          and app.tiene_rol_global(array['admin_operativo']::rol_app[])) then
    raise exception 'Sin permiso para fusionar estas fichas' using errcode = '42501';
  end if;
  if p_conservada = p_absorbida then raise exception 'Elegí dos fichas distintas'; end if;
  if nullif(btrim(p_motivo),'') is null then raise exception 'Indicá el motivo de la fusión'; end if;
  if exists (select 1 from personas where id in (p_conservada, p_absorbida) and estado_registro <> 'activo') then
    raise exception 'Solo se fusionan fichas activas';
  end if;
  if exists (select 1 from casos a join casos b on a.programa_id = b.programa_id
             where a.persona_id = p_conservada and b.persona_id = p_absorbida and a.estado <> 'cerrado' and b.estado <> 'cerrado') then
    raise exception 'Ambas fichas tienen un caso abierto en el mismo programa: cerrá uno antes de fusionar';
  end if;

  insert into fusiones (conservada_id, absorbida_id, motivo, realizada_por) values (p_conservada, p_absorbida, p_motivo, auth.uid())
  returning id into v_f;

  for i in 1 .. array_length(cols, 1) loop
    t := cols[i][1]; c := cols[i][2];
    if to_regclass(t) is null then continue; end if;
    extra := case when t = 'public.vinculos' and c = 'persona_id' then ' and persona_relacionada_id <> $1'
                  when t = 'public.vinculos' and c = 'persona_relacionada_id' then ' and persona_id <> $1' else '' end;
    execute format('with m as (update %s set %I = $1 where %I = $2%s returning id)
                    insert into fusion_movimientos (fusion_id, tabla, columna, registro_id) select $3, %L, %L, id from m',
                   t, c, c, extra, t, c)
      using p_conservada, p_absorbida, v_f;
  end loop;

  with nuevos as (
    insert into persona_institucion (persona_id, institucion_id, lote_id)
    select p_conservada, institucion_id, lote_id from persona_institucion where persona_id = p_absorbida
    on conflict do nothing returning institucion_id)
  insert into fusion_movimientos select v_f, 'public.persona_institucion', 'alta_alcance', institucion_id from nuevos;

  update candidatos_duplicado set estado = 'fusionado', revisado_por = auth.uid(), revisado_en = now()
  where persona_a = least(p_conservada, p_absorbida) and persona_b = greatest(p_conservada, p_absorbida);
  update personas set estado_registro = 'fusionado', fusionada_en = p_conservada where id = p_absorbida;
  perform app.registrar_evento('fusion', 'personas', p_conservada, array[p_absorbida::text]);
  return v_f;
end $$;

-- Revierte solo lo que la fusión movió. Lo creado después de la fusión queda en la ficha conservada.
create or replace function public.revertir_fusion(p_fusion uuid) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare fu fusiones; m record;
begin
  select * into fu from fusiones where id = p_fusion for update;
  if fu.id is null or not (app.puede_ver_persona(fu.conservada_id) and app.tiene_rol_global(array['admin_operativo']::rol_app[])) then
    raise exception 'Sin permiso' using errcode = '42501';
  end if;
  if fu.revertida_en is not null then raise exception 'La fusión ya fue revertida'; end if;
  if exists (select 1 from fusiones where conservada_id = fu.absorbida_id and revertida_en is null) then
    raise exception 'La ficha absorbida participó luego en otra fusión: revertí esa primero';
  end if;
  for m in select * from fusion_movimientos where fusion_id = p_fusion loop
    if m.tabla = 'public.persona_institucion' then
      delete from persona_institucion where persona_id = fu.conservada_id and institucion_id = m.registro_id;
    elsif to_regclass(m.tabla) is not null then
      execute format('update %s set %I = $1 where id = $2 and %I = $3', m.tabla, m.columna, m.columna)
        using fu.absorbida_id, m.registro_id, fu.conservada_id;
    end if;
  end loop;
  update personas set estado_registro = 'activo', fusionada_en = null where id = fu.absorbida_id;
  update candidatos_duplicado set estado = 'pendiente', revisado_por = null, revisado_en = null
  where persona_a = least(fu.conservada_id, fu.absorbida_id) and persona_b = greatest(fu.conservada_id, fu.absorbida_id);
  update fusiones set revertida_en = now(), revertida_por = auth.uid() where id = p_fusion;
  perform app.registrar_evento('fusion_revertida', 'personas', fu.conservada_id, array[fu.absorbida_id::text]);
end $$;

create or replace function public.descartar_duplicado(p_candidato uuid) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare cd candidatos_duplicado;
begin
  select * into cd from candidatos_duplicado where id = p_candidato;
  if cd.id is null or not (app.puede_editar_persona(cd.persona_a) and app.puede_editar_persona(cd.persona_b)) then
    raise exception 'Sin permiso' using errcode = '42501';
  end if;
  update candidatos_duplicado set estado = 'descartado', revisado_por = auth.uid(), revisado_en = now() where id = p_candidato;
end $$;

-- ───────────── Casos, interacciones y tareas ─────────────
create or replace function app.antes_caso() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  select tipo into new.tipo_programa from programas where id = new.programa_id;
  if tg_op = 'INSERT' then
    new.creado_por := coalesce(new.creado_por, auth.uid());
    if new.etapa is null then
      select codigo into new.etapa from catalogo_etapas where tipo_programa = new.tipo_programa order by orden limit 1;
    end if;
  end if;
  if new.responsable_id is not null and (tg_op = 'INSERT' or new.responsable_id is distinct from old.responsable_id)
     and not app.usuario_tiene_programa(new.responsable_id, new.programa_id) then
    raise exception 'La persona responsable no tiene acceso a este programa';
  end if;
  return new;
end $$;
create trigger t_antes_caso before insert or update on casos for each row execute function app.antes_caso();

create or replace function app.historial_caso() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' or new.etapa is distinct from old.etapa or new.estado is distinct from old.estado then
    insert into caso_historial (caso_id, etapa_anterior, etapa_nueva, estado_anterior, estado_nuevo, motivo, usuario_id)
    values (new.id, case when tg_op = 'UPDATE' then old.etapa end, new.etapa,
            case when tg_op = 'UPDATE' then old.estado end, new.estado, new.motivo_cierre, auth.uid());
  end if;
  return new;
end $$;
create trigger t_historial_caso after insert or update on casos for each row execute function app.historial_caso();

create or replace function app.validar_tarea() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare prog uuid;
begin
  select programa_id into prog from casos where id = new.caso_id;
  if new.responsable_id is not null and (tg_op = 'INSERT' or new.responsable_id is distinct from old.responsable_id)
     and not app.usuario_tiene_programa(new.responsable_id, prog) then
    raise exception 'La persona responsable no tiene acceso al programa del caso';
  end if;
  if tg_op = 'INSERT' then new.creado_por := coalesce(new.creado_por, auth.uid()); end if;
  if new.estado = 'cumplida' and new.completada_en is null then new.completada_en := now(); end if;
  return new;
end $$;
create trigger t_validar_tarea before insert or update on tareas for each row execute function app.validar_tarea();

-- Respeto de no contacto y protección de menores
create or replace function app.validar_interaccion() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_sobre uuid; p personas; v_edad int; v_tipo tipo_programa;
begin
  if new.direccion = 'saliente' and exists (
      select 1 from preferencias_contacto pc where pc.persona_id = new.persona_id and pc.vigente and not pc.permitido
        and pc.canal in ('todos', new.canal::text)) then
    raise exception 'Esta persona pidió no ser contactada por este canal. No se registra el contacto saliente.' using errcode = 'P0002';
  end if;
  v_sobre := coalesce(new.sobre_persona_id, (select persona_id from casos where id = new.caso_id));
  if v_sobre is not null then
    select * into p from personas where id = v_sobre;
    v_edad := app.edad(p.fecha_nacimiento, p.precision_fecha);
    select tipo into v_tipo from programas where id = new.programa_id;
    if (v_edad is not null and v_edad < 18) or (v_edad is null and v_tipo = 'educacion') then
      if new.persona_id = v_sobre then
        raise exception 'El acercamiento a menores (o de edad sin dato en educación) se dirige a sus adultos responsables o contactos autorizados.' using errcode = 'P0003';
      end if;
      if not exists (select 1 from vinculos v where v.persona_id = v_sobre and v.persona_relacionada_id = new.persona_id
                     and v.vigente and v.categoria in ('adulto_responsable','contacto_autorizado')) then
        raise exception 'El interlocutor no figura como adulto responsable ni contacto autorizado de la persona del caso.' using errcode = 'P0003';
      end if;
    end if;
  end if;
  return new;
end $$;
create trigger t_validar_interaccion before insert on interacciones for each row execute function app.validar_interaccion();

create or replace function public.abrir_caso(p_persona uuid, p_programa uuid, p_motivo text, p_responsable uuid,
  p_primera_accion text default null, p_vence date default null) returns uuid
language plpgsql security invoker set search_path = public, app, pg_temp as $$
declare v uuid := gen_random_uuid();
begin
  insert into casos (id, programa_id, tipo_programa, persona_id, motivo, responsable_id, etapa)
  values (v, p_programa, 'educacion', p_persona, p_motivo, p_responsable, null);
  if nullif(btrim(p_primera_accion),'') is not null then
    if p_vence is null then raise exception 'La primera acción necesita fecha de vencimiento'; end if;
    insert into tareas (caso_id, responsable_id, accion, vence_el) values (v, p_responsable, p_primera_accion, p_vence);
  end if;
  return v;
end $$;

create or replace function public.cambiar_etapa(p_caso uuid, p_etapa text, p_motivo text default null) returns void
language plpgsql security invoker set search_path = public, app, pg_temp as $$
declare c casos; e catalogo_etapas;
begin
  select * into c from casos where id = p_caso;
  if c.id is null then raise exception 'Caso inexistente o sin acceso' using errcode = '42501'; end if;
  select * into e from catalogo_etapas where tipo_programa = c.tipo_programa and codigo = p_etapa;
  if e.codigo is null then raise exception 'Etapa no válida para este programa'; end if;
  if e.requiere_motivo and nullif(btrim(p_motivo),'') is null then raise exception 'Indicá el motivo'; end if;
  update casos set etapa = e.codigo, estado = e.estado_resultante,
    motivo_cierre = case when e.estado_resultante <> 'abierto' then p_motivo else null end,
    cerrado_en = case when e.estado_resultante = 'cerrado' then current_date end
  where id = p_caso;
  if e.estado_resultante = 'cerrado' then
    update tareas set estado = 'cancelada', resultado = 'Caso cerrado' where caso_id = p_caso and estado in ('pendiente','en_curso');
  end if;
end $$;

-- p: {caso_id, interlocutor_id, canal, direccion, fecha, resumen, resultado, nueva_etapa, motivo,
--     barreras:[{tipo,detalle}], completar_tarea_id, resultado_tarea, proxima_tarea:{accion,vence_el,responsable_id,prioridad}}
create or replace function public.registrar_interaccion(p jsonb) returns uuid
language plpgsql security invoker set search_path = public, app, pg_temp as $$
declare c casos; v_id uuid := gen_random_uuid(); b jsonb; v_int uuid := (p->>'interlocutor_id')::uuid;
begin
  select * into c from casos where id = (p->>'caso_id')::uuid;
  if c.id is null then raise exception 'Caso inexistente o sin acceso' using errcode = '42501'; end if;
  insert into interacciones (id, programa_id, caso_id, persona_id, sobre_persona_id, fecha, canal, direccion, usuario_id, resumen, resultado)
  values (v_id, c.programa_id, c.id, v_int, case when c.persona_id is distinct from v_int then c.persona_id end,
          coalesce((p->>'fecha')::timestamptz, now()), (p->>'canal')::canal,
          coalesce((p->>'direccion')::direccion_interaccion, 'saliente'), auth.uid(), p->>'resumen', p->>'resultado');
  for b in select value from jsonb_array_elements(coalesce(p->'barreras', '[]'::jsonb)) loop
    insert into barreras (caso_id, interaccion_id, tipo, detalle) values (c.id, v_id, (b->>'tipo')::tipo_barrera, nullif(b->>'detalle',''));
  end loop;
  if nullif(p->>'completar_tarea_id','') is not null then
    update tareas set estado = 'cumplida', resultado = coalesce(nullif(p->>'resultado_tarea',''), p->>'resumen'),
           proximo_paso = p->'proxima_tarea'->>'accion'
    where id = (p->>'completar_tarea_id')::uuid and caso_id = c.id;
  end if;
  if nullif(p->>'nueva_etapa','') is not null and p->>'nueva_etapa' <> c.etapa then
    perform public.cambiar_etapa(c.id, p->>'nueva_etapa', p->>'motivo');
  end if;
  if nullif(p->'proxima_tarea'->>'accion','') is not null then
    insert into tareas (caso_id, responsable_id, accion, vence_el, prioridad)
    values (c.id, coalesce((p->'proxima_tarea'->>'responsable_id')::uuid, c.responsable_id), p->'proxima_tarea'->>'accion',
            (p->'proxima_tarea'->>'vence_el')::date, coalesce((p->'proxima_tarea'->>'prioridad')::prioridad, 'normal'));
  end if;
  return v_id;
end $$;

-- ───────────── Exportación ordinaria (nunca incluye información restringida) ─────────────
create or replace function public.exportar_personas(p_institucion uuid)
returns table (id uuid, nombres text, apellidos text, nombre_preferido text, fecha_nacimiento date, edad int,
               telefono text, email text, no_contactar boolean)
language plpgsql security invoker set search_path = public, app, pg_temp as $$
begin
  if not app.tiene_rol(p_institucion, array['admin_operativo']::rol_app[]) then
    raise exception 'Solo la administración operativa exporta fichas' using errcode = '42501';
  end if;
  perform app.registrar_evento('exportacion_personas', 'instituciones', p_institucion);
  return query
  select p.id, p.nombres, p.apellidos, p.nombre_preferido, p.fecha_nacimiento, app.edad(p.fecha_nacimiento, p.precision_fecha),
    (select m.valor_original from medios_contacto m where m.persona_id = p.id and m.tipo = 'telefono' and m.vigente order by m.preferido desc, m.creado_en limit 1),
    (select m.valor_original from medios_contacto m where m.persona_id = p.id and m.tipo = 'email' and m.vigente order by m.preferido desc, m.creado_en limit 1),
    exists (select 1 from preferencias_contacto pc where pc.persona_id = p.id and pc.vigente and not pc.permitido and pc.canal = 'todos')
  from personas p join persona_institucion pi on pi.persona_id = p.id and pi.institucion_id = p_institucion
  where p.estado_registro = 'activo'
  order by p.apellidos nulls last, p.nombres;
end $$;

grant execute on all functions in schema public to authenticated;
grant execute on all functions in schema app to authenticated;
revoke execute on all functions in schema public from public, anon;
