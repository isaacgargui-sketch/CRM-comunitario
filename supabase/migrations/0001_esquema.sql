-- CRM Comunitario Tucumán · Migración 0001 · Esquema base
-- Convención: tablas operativas en "public" (expuestas a la API con RLS),
-- funciones auxiliares en "app" (no expuestas), módulo restringido en "rabinico".

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create schema if not exists app;

-- ───────────── Tipos ─────────────
create type estado_dato as enum ('desconocido','pendiente_verificacion','confirmado','desactualizado');
create type precision_fecha as enum ('dia','mes','anio');
create type estado_registro as enum ('activo','fusionado','inactivo','supresion_solicitada');
create type rol_app as enum ('admin_operativo','equipo_educativo','coordinacion_comunitaria',
                             'equipo_acompanamiento','autoridad_rabinica','estadisticas');
create type tipo_programa as enum ('educacion','comunitario','adultos_mayores');
create type tipo_contacto as enum ('telefono','email');
create type categoria_vinculo as enum ('parentesco','adulto_responsable','contacto_autorizado');
create type categoria_escolaridad as enum ('maimonides','otra_judia','otra','sin_verificar');
create type canal as enum ('telefono','whatsapp','email','presencial','otro');
create type direccion_interaccion as enum ('saliente','entrante');
create type estado_tarea as enum ('pendiente','en_curso','cumplida','cancelada');
create type prioridad as enum ('baja','normal','alta');
create type estado_caso as enum ('abierto','pausado','cerrado');
create type estado_lote as enum ('borrador','confirmado','revertido');
create type resultado_fila as enum ('persona_creada','vinculada_existente','repetida_en_reimportacion','omitida','error');
create type estado_candidato as enum ('pendiente','descartado','fusionado');
create type tipo_barrera as enum ('costo','transporte','horarios','propuesta_educativa','otra');

-- ───────────── Funciones inmutables de normalización ─────────────
create or replace function app.normalizar_texto(t text) returns text
language sql immutable parallel safe as $$
  select nullif(lower(extensions.unaccent('extensions.unaccent'::regdictionary,
         btrim(regexp_replace(coalesce(t,''), '\s+', ' ', 'g')))), '')
$$;

-- ───────────── Instituciones, programas, usuarios ─────────────
create table instituciones (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique,
  activa boolean not null default true,
  creado_en timestamptz not null default now()
);

create table programas (
  id uuid primary key default gen_random_uuid(),
  institucion_id uuid not null references instituciones(id),
  nombre text not null,
  tipo tipo_programa not null,
  objetivos text,
  edad_min int,
  edad_max int,
  estado text not null default 'activo' check (estado in ('activo','pausado','cerrado')),
  creado_en timestamptz not null default now(),
  unique (institucion_id, nombre),
  check (edad_min is null or edad_max is null or edad_min <= edad_max)
);

create table usuarios (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text not null,
  email text,
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);

create table asignaciones_rol (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references usuarios(id) on delete cascade,
  rol rol_app not null,
  institucion_id uuid not null references instituciones(id),
  programa_id uuid references programas(id),   -- null = todos los programas compatibles con el rol
  creado_en timestamptz not null default now(),
  unique nulls not distinct (usuario_id, rol, institucion_id, programa_id)
);

create table programa_responsables (
  programa_id uuid not null references programas(id) on delete cascade,
  usuario_id uuid not null references usuarios(id) on delete cascade,
  primary key (programa_id, usuario_id)
);

-- ───────────── Fuentes e importaciones ─────────────
create table fuentes (
  id uuid primary key default gen_random_uuid(),
  institucion_id uuid not null references instituciones(id),
  nombre text not null,
  proposito_autorizado text not null,
  autorizacion_referencia text,           -- acta, nota o decisión que autoriza el uso
  creado_por uuid references usuarios(id),
  creado_en timestamptz not null default now(),
  unique (institucion_id, nombre)
);

create table lotes_importacion (
  id uuid primary key default gen_random_uuid(),
  fuente_id uuid not null references fuentes(id),
  institucion_id uuid not null references instituciones(id),
  archivo_nombre text not null,
  archivo_sha256 text not null,
  proposito text not null,
  instituciones_autorizadas uuid[] not null,
  fecha_datos date not null,               -- fecha a la que corresponde el archivo
  tipo text not null default 'personas' check (tipo in ('personas','matricula')),
  matricula_escuela text,
  matricula_categoria categoria_escolaridad,
  matricula_ciclo int,
  estado estado_lote not null default 'borrador',
  resumen jsonb,
  creado_por uuid not null references usuarios(id),
  creado_en timestamptz not null default now(),
  confirmado_en timestamptz,
  revertido_en timestamptz,
  revertido_por uuid references usuarios(id),
  motivo_reversion text,
  check (tipo <> 'matricula' or (matricula_escuela is not null and matricula_categoria is not null and matricula_ciclo is not null)),
  check (cardinality(instituciones_autorizadas) > 0)
);
create unique index lotes_archivo_unico on lotes_importacion (fuente_id, archivo_sha256) where estado = 'confirmado';

-- ───────────── Personas ─────────────
create table personas (
  id uuid primary key default gen_random_uuid(),
  nombres text not null check (btrim(nombres) <> ''),
  apellidos text,
  nombre_preferido text,
  fecha_nacimiento date,
  precision_fecha precision_fecha,
  fecha_nacimiento_estado estado_dato not null default 'desconocido',
  estado_registro estado_registro not null default 'activo',
  fusionada_en uuid references personas(id),
  fuente_alta_id uuid references fuentes(id),
  lote_alta_id uuid references lotes_importacion(id),
  nombre_busqueda text generated always as (app.normalizar_texto(coalesce(nombres,'') || ' ' || coalesce(apellidos,''))) stored,
  creado_por uuid references usuarios(id),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  check ((fecha_nacimiento is null) = (precision_fecha is null))
);
create index personas_nombre_trgm on personas using gin (nombre_busqueda extensions.gin_trgm_ops);
create index personas_nombre on personas (nombre_busqueda);
create index personas_nacimiento on personas (fecha_nacimiento);

-- Alcance institucional: qué instituciones pueden ver la ficha (deriva del alcance autorizado del lote o de la carga manual)
create table persona_institucion (
  persona_id uuid not null references personas(id),
  institucion_id uuid not null references instituciones(id),
  lote_id uuid references lotes_importacion(id),
  creado_en timestamptz not null default now(),
  primary key (persona_id, institucion_id)
);
create index persona_institucion_inst on persona_institucion (institucion_id);

create table filas_importacion (
  id uuid primary key default gen_random_uuid(),
  lote_id uuid not null references lotes_importacion(id) on delete cascade,
  nro_fila int not null,
  datos_originales jsonb not null,
  datos_normalizados jsonb,
  hash_fila text,
  errores text[] not null default '{}',
  advertencias text[] not null default '{}',
  candidatos jsonb not null default '[]',
  repetida_de_persona uuid references personas(id),
  decision text check (decision in ('crear','vincular','omitir')),
  persona_destino uuid references personas(id),
  resultado resultado_fila,
  persona_id uuid references personas(id),
  unique (lote_id, nro_fila)
);
create index filas_hash on filas_importacion (hash_fila);
create index filas_persona on filas_importacion (persona_id);

-- ───────────── Contactos y domicilios ─────────────
create table medios_contacto (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id),
  tipo tipo_contacto not null,
  valor_original text not null,
  valor_normalizado text,
  preferido boolean not null default false,
  estado estado_dato not null default 'pendiente_verificacion',
  vigente boolean not null default true,
  vigente_hasta date,
  fuente_id uuid references fuentes(id),
  lote_id uuid references lotes_importacion(id),
  verificado_por uuid references usuarios(id),
  verificado_en timestamptz,
  creado_en timestamptz not null default now()
);
-- Un teléfono o correo puede repetirse entre personas (familias): índice NO único entre personas.
create index contactos_valor on medios_contacto (tipo, valor_normalizado);
create index contactos_persona on medios_contacto (persona_id);

create table domicilios (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id),
  direccion_original text not null,
  localidad text,
  estado estado_dato not null default 'pendiente_verificacion',
  vigente boolean not null default true,
  fuente_id uuid references fuentes(id),
  lote_id uuid references lotes_importacion(id),
  verificado_por uuid references usuarios(id),
  verificado_en timestamptz,
  creado_en timestamptz not null default now()
);
create index domicilios_persona on domicilios (persona_id);

-- ───────────── Hogares y vínculos ─────────────
create table hogares (
  id uuid primary key default gen_random_uuid(),
  nombre_referencia text not null,
  domicilio text,
  localidad text,
  estado estado_dato not null default 'pendiente_verificacion',
  creado_por uuid references usuarios(id),
  creado_en timestamptz not null default now()
);

create table hogar_integrantes (
  id uuid primary key default gen_random_uuid(),
  hogar_id uuid not null references hogares(id),
  persona_id uuid not null references personas(id),
  desde date,
  hasta date,
  estado estado_dato not null default 'pendiente_verificacion',
  fuente_id uuid references fuentes(id),
  creado_en timestamptz not null default now()
);
create index hogar_integrantes_persona on hogar_integrantes (persona_id);

-- persona_relacionada es [detalle] de persona. Ej.: persona = niña, relacionada = madre, categoria = parentesco, detalle = 'madre'.
create table vinculos (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id),
  persona_relacionada_id uuid not null references personas(id),
  categoria categoria_vinculo not null,
  detalle text not null,
  estado estado_dato not null default 'pendiente_verificacion',
  vigente boolean not null default true,
  fuente_id uuid references fuentes(id),
  verificado_por uuid references usuarios(id),
  verificado_en timestamptz,
  creado_en timestamptz not null default now(),
  check (persona_id <> persona_relacionada_id)
);
create index vinculos_persona on vinculos (persona_id);
create index vinculos_relacionada on vinculos (persona_relacionada_id);

-- ───────────── Escolaridad ─────────────
create table escolaridad (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id),
  ciclo_lectivo int not null check (ciclo_lectivo between 1990 and 2100),
  escuela_nombre text,
  categoria categoria_escolaridad not null,
  nivel text check (nivel in ('inicial','primario','secundario','otro')),
  grado_sala text,
  estado estado_dato not null default 'pendiente_verificacion',
  fuente_id uuid references fuentes(id),
  lote_id uuid references lotes_importacion(id),
  verificado_por uuid references usuarios(id),
  verificado_en timestamptz,
  nota text,
  registrado_por uuid references usuarios(id),
  creado_en timestamptz not null default now()
);
create index escolaridad_persona_ciclo on escolaridad (persona_id, ciclo_lectivo);

-- ───────────── Participaciones ─────────────
create table participaciones (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id),
  programa_id uuid not null references programas(id),
  actividad text,
  estado text not null check (estado in ('invitada','interesada','inscripta','activa','pausada','finalizada')),
  desde date,
  hasta date,
  creado_por uuid references usuarios(id),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
create index participaciones_persona on participaciones (persona_id);

create table participacion_historial (
  id bigint generated always as identity primary key,
  participacion_id uuid not null references participaciones(id) on delete cascade,
  estado_anterior text,
  estado_nuevo text not null,
  usuario_id uuid,
  en timestamptz not null default now()
);

-- ───────────── Casos, interacciones, tareas ─────────────
create table catalogo_etapas (
  tipo_programa tipo_programa not null,
  codigo text not null,
  nombre text not null,
  orden int not null,
  estado_resultante estado_caso not null default 'abierto',
  requiere_motivo boolean not null default false,
  primary key (tipo_programa, codigo)
);

create table casos (
  id uuid primary key default gen_random_uuid(),
  programa_id uuid not null references programas(id),
  tipo_programa tipo_programa not null,
  persona_id uuid references personas(id),
  hogar_id uuid references hogares(id),
  motivo text not null check (btrim(motivo) <> ''),
  responsable_id uuid not null references usuarios(id),
  etapa text not null,
  estado estado_caso not null default 'abierto',
  motivo_cierre text,
  abierto_en date not null default current_date,
  cerrado_en date,
  creado_por uuid references usuarios(id),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  foreign key (tipo_programa, etapa) references catalogo_etapas(tipo_programa, codigo),
  check (persona_id is not null or hogar_id is not null)
);
create unique index casos_un_abierto_por_persona on casos (persona_id, programa_id) where estado <> 'cerrado';
create index casos_responsable on casos (responsable_id) where estado <> 'cerrado';

create table caso_historial (
  id bigint generated always as identity primary key,
  caso_id uuid not null references casos(id) on delete cascade,
  etapa_anterior text,
  etapa_nueva text,
  estado_anterior estado_caso,
  estado_nuevo estado_caso,
  motivo text,
  usuario_id uuid,
  en timestamptz not null default now()
);

create table interacciones (
  id uuid primary key default gen_random_uuid(),
  programa_id uuid not null references programas(id),
  caso_id uuid references casos(id),
  persona_id uuid not null references personas(id),       -- interlocutor
  sobre_persona_id uuid references personas(id),           -- persona del caso, si es otra
  fecha timestamptz not null default now(),
  canal canal not null,
  direccion direccion_interaccion not null default 'saliente',
  usuario_id uuid not null references usuarios(id),
  resumen text not null check (char_length(resumen) between 1 and 600),
  resultado text not null check (resultado in ('sin_respuesta','numero_erroneo','mensaje_dejado','conversacion','reunion','otro')),
  creado_en timestamptz not null default now()
);
create index interacciones_persona on interacciones (persona_id, fecha desc);
create index interacciones_sobre on interacciones (sobre_persona_id, fecha desc);
create index interacciones_caso on interacciones (caso_id);

create table barreras (
  id uuid primary key default gen_random_uuid(),
  caso_id uuid not null references casos(id),
  interaccion_id uuid not null references interacciones(id),   -- solo se registran si la familia las comunicó en una interacción
  tipo tipo_barrera not null,
  detalle text check (char_length(detalle) <= 300),
  creado_en timestamptz not null default now()
);

create table tareas (
  id uuid primary key default gen_random_uuid(),
  caso_id uuid not null references casos(id),
  responsable_id uuid not null references usuarios(id),
  accion text not null check (btrim(accion) <> ''),
  vence_el date not null,
  prioridad prioridad not null default 'normal',
  estado estado_tarea not null default 'pendiente',
  resultado text,
  proximo_paso text,
  creado_por uuid references usuarios(id),
  creado_en timestamptz not null default now(),
  completada_en timestamptz
);
create index tareas_responsable on tareas (responsable_id, estado, vence_el);
create index tareas_caso on tareas (caso_id);

-- ───────────── Preferencias de contacto ─────────────
create table preferencias_contacto (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id),
  canal text not null check (canal in ('todos','telefono','whatsapp','email','presencial')),
  permitido boolean not null,
  proposito text,                 -- para qué se habilitó/restringió
  alcance text,                   -- p. ej. 'Kehilá y Maimónides'
  documentado_en date not null default current_date,
  fuente text not null,           -- cómo se obtuvo: 'pedido telefónico', 'nota firmada', etc.
  vigente boolean not null default true,
  registrado_por uuid references usuarios(id),
  creado_en timestamptz not null default now()
);
create index preferencias_persona on preferencias_contacto (persona_id) where vigente;

-- ───────────── Calidad de datos: duplicados, fusiones, discrepancias ─────────────
create table candidatos_duplicado (
  id uuid primary key default gen_random_uuid(),
  persona_a uuid not null references personas(id),
  persona_b uuid not null references personas(id),
  motivos text[] not null,
  puntaje int not null,
  estado estado_candidato not null default 'pendiente',
  origen_lote_id uuid references lotes_importacion(id),
  revisado_por uuid references usuarios(id),
  revisado_en timestamptz,
  creado_en timestamptz not null default now(),
  check (persona_a < persona_b),
  unique (persona_a, persona_b)
);

create table fusiones (
  id uuid primary key default gen_random_uuid(),
  conservada_id uuid not null references personas(id),
  absorbida_id uuid not null references personas(id),
  motivo text not null,
  realizada_por uuid not null references usuarios(id),
  realizada_en timestamptz not null default now(),
  revertida_por uuid references usuarios(id),
  revertida_en timestamptz
);

create table fusion_movimientos (
  fusion_id uuid not null references fusiones(id),
  tabla text not null,
  columna text not null,
  registro_id uuid not null,
  primary key (fusion_id, tabla, columna, registro_id)
);

create table discrepancias (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id),
  campo text not null,
  valor_existente text,
  valor_nuevo text,
  fuente_id uuid references fuentes(id),
  lote_id uuid references lotes_importacion(id),
  estado text not null default 'pendiente' check (estado in ('pendiente','mantener_existente','aplicar_nuevo')),
  resuelto_por uuid references usuarios(id),
  resuelto_en timestamptz,
  creado_en timestamptz not null default now()
);

-- ───────────── Derechos de las personas ─────────────
create table solicitudes_titular (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id),
  tipo text not null check (tipo in ('acceso','rectificacion','supresion','oposicion')),
  detalle text,
  recibida_en date not null default current_date,
  responsable_id uuid references usuarios(id),
  estado text not null default 'recibida' check (estado in ('recibida','en_curso','resuelta','rechazada')),
  resolucion text,
  resuelta_en date,
  creado_en timestamptz not null default now()
);

-- ───────────── Auditoría (sin valores: solo qué campos cambiaron) ─────────────
create table auditoria (
  id bigint generated always as identity primary key,
  en timestamptz not null default now(),
  usuario_id uuid,
  tabla text not null,
  registro_id uuid,
  accion text not null,
  campos text[]
);
create index auditoria_registro on auditoria (tabla, registro_id);
