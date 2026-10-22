import { NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase/server';

const csv = (v: unknown) => `"${String(v ?? '').replace(/"/g, '""')}"`;

export async function GET(_: Request, { params }: { params: { lote: string } }) {
  const sb = supabaseServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return new NextResponse('No autorizado', { status: 401 });
  const { data, error } = await sb.rpc('importacion_informe', { p_lote: params.lote });
  if (error) return new NextResponse(error.message, { status: 403 });
  const filas = (data as any[]) ?? [];
  const cols = Array.from(new Set(filas.flatMap((f) => Object.keys(f.datos_originales ?? {}))));
  const out = [['fila', 'resultado', 'errores', 'advertencias', ...cols].map(csv).join(',')]
    .concat(filas.map((f) => [f.nro_fila, f.resultado, f.errores, f.advertencias, ...cols.map((c) => f.datos_originales?.[c])].map(csv).join(',')));
  return new NextResponse('\uFEFF' + out.join('\r\n'), {
    headers: {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="informe_${params.lote.slice(0, 8)}.csv"`,
      'Cache-Control': 'no-store',
    },
  });
}
