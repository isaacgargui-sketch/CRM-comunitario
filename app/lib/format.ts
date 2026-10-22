export const SIN_DATO = 'sin dato';

export function fecha(d?: string | null) {
  if (!d) return SIN_DATO;
  const [y, m, day] = d.slice(0, 10).split('-');
  return `${day}/${m}/${y}`;
}

export function fechaHora(d?: string | null) {
  if (!d) return SIN_DATO;
  return new Date(d).toLocaleString('es-AR', { dateStyle: 'short', timeStyle: 'short', timeZone: 'America/Argentina/Tucuman' });
}

export function nacimiento(f?: string | null, p?: string | null) {
  if (!f) return SIN_DATO;
  if (p === 'anio') return `año ${f.slice(0, 4)}`;
  if (p === 'mes') return `${f.slice(5, 7)}/${f.slice(0, 4)}`;
  return fecha(f);
}

export function edad(e?: number | null, p?: string | null) {
  if (e === null || e === undefined) return SIN_DATO;
  return p && p !== 'dia' ? `${e} años (aprox.)` : `${e} años`;
}

export const ESTADO_DATO: Record<string, string> = {
  desconocido: 'Desconocido',
  pendiente_verificacion: 'Sin verificar',
  confirmado: 'Confirmado',
  desactualizado: 'Desactualizado',
};

export const CANALES = [
  ['telefono', 'Teléfono'], ['whatsapp', 'WhatsApp'], ['email', 'Correo'], ['presencial', 'Presencial'], ['otro', 'Otro'],
] as const;

export const RESULTADOS = [
  ['sin_respuesta', 'Sin respuesta'], ['numero_erroneo', 'Número erróneo'], ['mensaje_dejado', 'Mensaje dejado'],
  ['conversacion', 'Conversación'], ['reunion', 'Reunión'], ['otro', 'Otro'],
] as const;

export const BARRERAS = [
  ['costo', 'Costo'], ['transporte', 'Transporte'], ['horarios', 'Horarios'],
  ['propuesta_educativa', 'Propuesta educativa'], ['otra', 'Otra'],
] as const;

export function hoyMas(dias: number) {
  const d = new Date(Date.now() + dias * 86400000);
  return d.toISOString().slice(0, 10);
}

/** Mensaje legible a partir de un error de Supabase/PostgREST. */
export function errorMsg(e: { message?: string; code?: string } | null | undefined) {
  if (!e) return '';
  if (e.code === '42501') return 'No tenés permiso para esta acción.';
  return e.message ?? 'Ocurrió un error.';
}
