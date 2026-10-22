'use server';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { requireUser } from '@/lib/supabase/server';

const s = (f: FormData, k: string) => { const v = String(f.get(k) ?? '').trim(); return v === '' ? null : v; };
async function fin(id: string, error: { message: string } | null) {
  if (error) redirect(`/casos/${id}?error=${encodeURIComponent(error.message)}`);
  revalidatePath(`/casos/${id}`);
}

export async function registrar(id: string, f: FormData) {
  const { sb } = await requireUser();
  const accion = s(f, 'prox_accion');
  const { error } = await sb.rpc('registrar_interaccion', { p: {
    caso_id: id, interlocutor_id: s(f, 'interlocutor'), canal: s(f, 'canal'), direccion: s(f, 'direccion'),
    fecha: s(f, 'fecha') ? new Date(String(f.get('fecha'))).toISOString() : null,
    resumen: s(f, 'resumen'), resultado: s(f, 'resultado'), nueva_etapa: s(f, 'etapa'), motivo: s(f, 'motivo'),
    barreras: f.getAll('barrera').map((b) => ({ tipo: String(b), detalle: b === 'otra' ? s(f, 'barrera_detalle') : null })),
    completar_tarea_id: s(f, 'completar'),
    proxima_tarea: accion ? { accion, vence_el: s(f, 'prox_vence'), responsable_id: s(f, 'prox_resp'), prioridad: s(f, 'prox_prioridad') } : null,
  } });
  await fin(id, error);
}

export async function cumplirTarea(id: string, tarea: string, f: FormData) {
  const { sb } = await requireUser();
  const { error } = await sb.from('tareas').update({ estado: 'cumplida', resultado: s(f, 'resultado') }).eq('id', tarea);
  await fin(id, error);
}

export async function reasignar(id: string, f: FormData) {
  const { sb } = await requireUser();
  const { error } = await sb.from('casos').update({ responsable_id: s(f, 'responsable') }).eq('id', id);
  await fin(id, error);
}

export async function nuevaTarea(id: string, f: FormData) {
  const { sb } = await requireUser();
  const { error } = await sb.from('tareas').insert({ caso_id: id, accion: s(f, 'accion'), vence_el: s(f, 'vence'), responsable_id: s(f, 'responsable'), prioridad: s(f, 'prioridad') ?? 'normal' });
  await fin(id, error);
}
