import Link from 'next/link';
import { redirect } from 'next/navigation';
import { revalidatePath } from 'next/cache';
import { requireUser } from '@/lib/supabase/server';
import { fecha, fechaHora, SIN_DATO } from '@/lib/format';

async function fusionar(conservada: string, absorbida: string, f: FormData) {
  'use server';
  const { sb } = await requireUser();
  const { error } = await sb.rpc('fusionar_personas', { p_conservada: conservada, p_absorbida: absorbida, p_motivo: String(f.get('motivo') ?? '') });
  if (error) redirect(`/duplicados?error=${encodeURIComponent(error.message)}`);
  revalidatePath('/duplicados');
}
async function descartar(id: string) {
  'use server';
  const { sb } = await requireUser();
  const { error } = await sb.rpc('descartar_duplicado', { p_candidato: id });
  if (error) redirect(`/duplicados?error=${encodeURIComponent(error.message)}`);
  revalidatePath('/duplicados');
}
async function revertir(id: string) {
  'use server';
  const { sb } = await requireUser();
  const { error } = await sb.rpc('revertir_fusion', { p_fusion: id });
  if (error) redirect(`/duplicados?error=${encodeURIComponent(error.message)}`);
  revalidatePath('/duplicados');
}

export default async function Duplicados({ searchParams }: { searchParams: { error?: string } }) {
  const { sb } = await requireUser();
  const [{ data: pares }, { data: fusiones }] = await Promise.all([
    sb.rpc('duplicados_pendientes'),
    sb.from('fusiones').select('id, motivo, realizada_en, revertida_en, conservada_id, absorbida_id').order('realizada_en', { ascending: false }).limit(30),
  ]);
  const ids = Array.from(new Set((fusiones ?? []).flatMap((f) => [f.conservada_id, f.absorbida_id])));
  const { data: nombres } = ids.length ? await sb.rpc('personas_resumen', { ids }) : { data: [] };
  const nom = (id: string) => (nombres as any[])?.find((n) => n.id === id)?.nombre ?? 'ficha';

  return (
    <>
      <h1>Duplicados y calidad de datos</h1>
      <p className="sub">Fusionar solo con certeza (p. ej. confirmado con la familia). La fusión queda auditada y se puede revertir.</p>
      {searchParams.error && <div className="aviso danger">{searchParams.error}</div>}
      <section className="panel">
        <h2>Posibles duplicados ({(pares as any[])?.length ?? 0})</h2>
        {!(pares as any[])?.length && <p className="sin-dato">No hay pares pendientes.</p>}
        {(pares as any[])?.map((d) => (
          <div key={d.candidato_id} style={{ borderTop: '1px solid var(--line)', padding: '.75rem 0' }}>
            <div className="fila" style={{ justifyContent: 'space-between' }}>
              <span><Link href={`/personas/${d.persona_a}`}>{d.nombre_a}</Link> ({d.nacimiento_a ? fecha(d.nacimiento_a) : SIN_DATO}) y <Link href={`/personas/${d.persona_b}`}>{d.nombre_b}</Link> ({d.nacimiento_b ? fecha(d.nacimiento_b) : SIN_DATO})</span>
              <span className="chip warn">{d.motivos.join('; ')}</span>
            </div>
            <div className="fila" style={{ marginTop: '.5rem' }}>
              <form action={descartar.bind(null, d.candidato_id)}><button className="secundario">Son personas distintas</button></form>
              <form action={fusionar.bind(null, d.persona_a, d.persona_b)} className="fila">
                <input name="motivo" required placeholder="Cómo se confirmó" aria-label="Motivo" /><button className="secundario">Conservar la primera y fusionar</button></form>
              <form action={fusionar.bind(null, d.persona_b, d.persona_a)} className="fila">
                <input name="motivo" required placeholder="Cómo se confirmó" aria-label="Motivo" /><button className="secundario">Conservar la segunda y fusionar</button></form>
            </div>
          </div>))}
      </section>
      <section className="panel tabla-wrap">
        <h2>Fusiones realizadas</h2>
        {!fusiones?.length ? <p className="sin-dato">Sin fusiones.</p> : (
          <table><thead><tr><th>Conservada</th><th>Absorbida</th><th>Motivo</th><th>Fecha</th><th></th></tr></thead>
            <tbody>{fusiones.map((f) => (
              <tr key={f.id}><td><Link href={`/personas/${f.conservada_id}`}>{nom(f.conservada_id)}</Link></td><td>{nom(f.absorbida_id)}</td>
                <td>{f.motivo}</td><td className="sub">{fechaHora(f.realizada_en)}</td>
                <td>{f.revertida_en ? <span className="chip neutro">revertida</span> : <form action={revertir.bind(null, f.id)}><button className="secundario">Revertir</button></form>}</td></tr>))}</tbody></table>)}
      </section>
    </>
  );
}
