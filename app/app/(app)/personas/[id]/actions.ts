'use server';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { requireUser } from '@/lib/supabase/server';

const s = (f: FormData, k: string) => { const v = String(f.get(k) ?? '').trim(); return v === '' ? null : v; };

async function fin(id: string, error: { message: string } | null) {
  if (error) redirect(`/personas/${id}?error=${encodeURIComponent(error.message)}`);
  revalidatePath(`/personas/${id}`);
}

export async function agregarContacto(id: string, f: FormData) {
  const { sb } = await requireUser();
  const { error } = await sb.from('medios_contacto').insert({ persona_id: id, tipo: s(f, 'tipo'), valor_original: s(f, 'valor'), preferido: f.get('preferido') === 'on' });
  await fin(id, error);
}

export async function verificarContacto(id: string, contacto: string) {
  const { sb, user } = await requireUser();
  const { error } = await sb.from('medios_contacto').update({ estado: 'confirmado', verificado_por: user.id, verificado_en: new Date().toISOString() }).eq('id', contacto);
  await fin(id, error);
}

export async function contactoDesactualizado(id: string, contacto: string) {
  const { sb } = await requireUser();
  const { error } = await sb.from('medios_contacto').update({ estado: 'desactualizado', vigente: false, vigente_hasta: new Date().toISOString().slice(0, 10) }).eq('id', contacto);
  await fin(id, error);
}

export async function agregarEscolaridad(id: string, f: FormData) {
  const { sb, user } = await requireUser();
  const confirmado = s(f, 'estado') === 'confirmado';
  const { error } = await sb.from('escolaridad').insert({
    persona_id: id, ciclo_lectivo: Number(s(f, 'ciclo')), categoria: s(f, 'categoria'), escuela_nombre: s(f, 'escuela'),
    nivel: s(f, 'nivel'), grado_sala: s(f, 'grado'), estado: confirmado ? 'confirmado' : 'pendiente_verificacion',
    nota: s(f, 'fuente'), registrado_por: user.id,
    verificado_por: confirmado ? user.id : null, verificado_en: confirmado ? new Date().toISOString() : null,
  });
  await fin(id, error);
}

export async function agregarVinculo(id: string, relacionada: string, f: FormData) {
  const { sb } = await requireUser();
  const { error } = await sb.from('vinculos').insert({
    persona_id: id, persona_relacionada_id: relacionada, categoria: s(f, 'categoria'), detalle: s(f, 'detalle'),
    estado: s(f, 'verificado') ? 'confirmado' : 'pendiente_verificacion',
  });
  await fin(id, error);
}

export async function finalizarVinculo(id: string, vinculo: string) {
  const { sb } = await requireUser();
  const { error } = await sb.from('vinculos').update({ vigente: false }).eq('id', vinculo);
  await fin(id, error);
}

export async function registrarPreferencia(id: string, f: FormData) {
  const { sb, user } = await requireUser();
  const { error } = await sb.from('preferencias_contacto').insert({
    persona_id: id, canal: s(f, 'canal'), permitido: s(f, 'permitido') === 'si', proposito: s(f, 'proposito'),
    alcance: s(f, 'alcance'), fuente: s(f, 'fuente') ?? 'Registro manual', registrado_por: user.id,
  });
  await fin(id, error);
}

export async function dejarSinEfectoPreferencia(id: string, pref: string) {
  const { sb } = await requireUser();
  const { error } = await sb.from('preferencias_contacto').update({ vigente: false }).eq('id', pref);
  await fin(id, error);
}

export async function resolverDiscrepancia(id: string, disc: string, aplicar: boolean) {
  const { sb, user } = await requireUser();
  const { data: d } = await sb.from('discrepancias').select('*').eq('id', disc).single();
  if (d && aplicar) {
    const cambio = d.campo === 'fecha_nacimiento'
      ? { fecha_nacimiento: d.valor_nuevo, precision_fecha: 'dia', fecha_nacimiento_estado: 'pendiente_verificacion' }
      : { [d.campo]: d.valor_nuevo };
    const { error } = await sb.from('personas').update(cambio).eq('id', id);
    if (error) return fin(id, error);
  }
  const { error } = await sb.from('discrepancias').update({
    estado: aplicar ? 'aplicar_nuevo' : 'mantener_existente', resuelto_por: user.id, resuelto_en: new Date().toISOString(),
  }).eq('id', disc);
  await fin(id, error);
}

export async function abrirCaso(id: string, f: FormData) {
  const { sb, user } = await requireUser();
  const { data, error } = await sb.rpc('abrir_caso', {
    p_persona: id, p_programa: s(f, 'programa'), p_motivo: s(f, 'motivo'), p_responsable: s(f, 'responsable') ?? user.id,
    p_primera_accion: s(f, 'accion'), p_vence: s(f, 'vence'),
  });
  if (error) return fin(id, error);
  redirect(`/casos/${data}`);
}
