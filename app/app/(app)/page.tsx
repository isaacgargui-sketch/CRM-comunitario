import Link from 'next/link';
import { requireUser } from '@/lib/supabase/server';
import { fecha } from '@/lib/format';
import { Indicadores } from '@/components/Indicadores';

export default async function Inicio({ searchParams }: { searchParams: { inst?: string; desde?: string; hasta?: string; programa?: string } }) {
  const { sb } = await requireUser();
  const anio = new Date().getFullYear();
  const desde = searchParams.desde ?? `${anio}-01-01`;
  const hasta = searchParams.hasta ?? new Date().toISOString().slice(0, 10);
  const [{ data: tareas }, { data: insts }, { data: progs }] = await Promise.all([
    sb.rpc('mis_tareas'),
    sb.from('instituciones').select('id, nombre').order('nombre'),
    sb.from('programas').select('id, nombre, institucion_id').order('nombre'),
  ]);
  const inst = searchParams.inst ?? insts?.[0]?.id;
  const programa = searchParams.programa || null;
  const { data: ind, error } = inst
    ? await sb.rpc('indicadores', { p_institucion: inst, p_desde: desde, p_hasta: hasta, p_programa: programa })
    : { data: [], error: null };
  const vencidas = (tareas ?? []).filter((t: any) => t.vencida);

  return (
    <>
      <h1>Inicio</h1>
      <p className="sub">Tus compromisos y el estado de los programas.</p>

      <section className="panel">
        <h2>Mis tareas {vencidas.length > 0 && <span className="chip danger">{vencidas.length} vencidas</span>}</h2>
        {!tareas?.length ? <p className="sin-dato">No tenés tareas pendientes.</p> : (
          <div className="tabla-wrap"><table>
            <thead><tr><th>Vence</th><th>Acción</th><th>Persona</th><th>Programa</th><th>Etapa</th></tr></thead>
            <tbody>{tareas.map((t: any) => (
              <tr key={t.tarea_id}>
                <td>{t.vencida ? <span className="chip danger">{fecha(t.vence_el)}</span> : fecha(t.vence_el)}</td>
                <td><Link href={`/casos/${t.caso_id}`}>{t.accion}</Link></td>
                <td>{t.persona_id ? <Link href={`/personas/${t.persona_id}`}>{t.persona}</Link> : <span className="sin-dato">hogar</span>}</td>
                <td>{t.programa}</td><td>{t.etapa}</td>
              </tr>))}</tbody>
          </table></div>
        )}
      </section>

      <section className="panel">
        <h2>Indicadores</h2>
        <form className="fila" style={{ marginBottom: '1rem' }}>
          <div><label>Institución</label><select name="inst" defaultValue={inst}>{insts?.map((i) => <option key={i.id} value={i.id}>{i.nombre}</option>)}</select></div>
          <div><label>Programa</label><select name="programa" defaultValue={programa ?? ''}><option value="">Todos</option>
            {progs?.filter((p) => p.institucion_id === inst).map((p) => <option key={p.id} value={p.id}>{p.nombre}</option>)}</select></div>
          <div><label>Desde</label><input type="date" name="desde" defaultValue={desde} /></div>
          <div><label>Hasta</label><input type="date" name="hasta" defaultValue={hasta} /></div>
          <button type="submit" className="secundario">Aplicar</button>
        </form>
        {error ? <div className="aviso warn">{error.message}</div> : <Indicadores filas={(ind as any) ?? []} />}
        <p className="sub" style={{ marginTop: '1rem' }}>Los registros reflejan solo los archivos y contactos cargados: no representan el tamaño total de la comunidad.</p>
      </section>
    </>
  );
}
