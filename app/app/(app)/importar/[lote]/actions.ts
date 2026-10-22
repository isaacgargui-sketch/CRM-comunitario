'use server';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { requireUser } from '@/lib/supabase/server';

async function fin(lote: string, error: { message: string } | null, destino?: string) {
  if (error) redirect(`/importar/${lote}?error=${encodeURIComponent(error.message)}`);
  revalidatePath(`/importar/${lote}`);
  if (destino) redirect(destino);
}

export async function resolver(lote: string, fila: string, decision: string, persona: string | null) {
  const { sb } = await requireUser();
  const { error } = await sb.rpc('importacion_resolver_fila', { p_fila: fila, p_decision: decision, p_persona: persona });
  await fin(lote, error);
}
export async function crearPendientes(lote: string) {
  const { sb } = await requireUser();
  const { error } = await sb.rpc('importacion_crear_pendientes', { p_lote: lote });
  await fin(lote, error);
}
export async function confirmar(lote: string) {
  const { sb } = await requireUser();
  const { error } = await sb.rpc('importacion_confirmar', { p_lote: lote });
  await fin(lote, error);
}
export async function cancelar(lote: string) {
  const { sb } = await requireUser();
  const { error } = await sb.rpc('importacion_cancelar', { p_lote: lote });
  await fin(lote, error, '/importar');
}
export async function revertir(lote: string, f: FormData) {
  const { sb } = await requireUser();
  const { error } = await sb.rpc('revertir_lote', { p_lote: lote, p_motivo: String(f.get('motivo') ?? '') });
  await fin(lote, error);
}
