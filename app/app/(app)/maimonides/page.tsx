import Link from 'next/link';
import { redirect } from 'next/navigation';
import { revalidatePath } from 'next/cache';
import { requireUser } from '@/lib/supabase/server';
import { edad, fecha, hoyMas } from '@/lib/format';
import { Indicadores } from '@/components/Indicadores';

async function asignar(programa: string, persona: string, f: FormData) {
  'use server';
  const { sb } = await requireUser();
  const { data, error } = await sb.rpc('abrir_caso', {
    p_persona: persona, p_programa: programa, p_motivo: String(f.get('motivo')), p_responsable: String(f.get('responsable')),
    p_primera_accion: String(f.get('accion')), p_vence: String(f.get('vence')),
  });
  if (error) redirect(`/maimonides?error=${encodeURIComponent(error.message)}`);
  revalidatePath('/maimonides');
  redirect(`/casos/${data}`);
}

const ESC_CHIP: Record<string, string> = {
  'Matrícula confirmada en Maimónides': 'ok', 'Escolaridad confirmada en otra escuela judía': 'info',
  'Escolaridad confirmada en otra escuela': 'neutro', 'Escolaridad sin verificar': 'warn',
};

export default async function Maimonides({ searchParams }: { searchParams: { programa?: string; ciclo?: string; esc?: string; seg?: string; error?: string } }) {
  const { sb } = await requireUser();
  const { data: progs } = await sb.from('programas').select('id, nombre, institucion_id, edad_min, edad_max').eq('tipo', 'educacion').eq('estado', 'activo');
  if (!progs?.length) return <><h1>Piloto Maimónides</h1><p className="sin-dato">No tenés acceso a programas educativos.</p></>;
  const prog = progs.find((p) => p.id === searchParams.programa) ?? progs[0];
  const ciclo = Number(searchParams.ciclo ?? new Date().getFullYear());
  const [{ data: filasRaw, error }, { data: resp }, { data: ind }] = await Promise.all([
    sb.rpc('tablero_maimonides', { p_programa: prog.id, p_ciclo: ciclo }),
    sb.rpc('responsables_programa', { p_programa: prog.id }),
    sb.rpc('indicadores', { p_institucion: prog.institucion_id, p_desde: `${ciclo}-01-01`, p_hasta: new Date().toISOString().slice(0, 10), p_programa: prog.id }),
  ]);
  let filas = (filasRaw as any[]) ?? [];
  if (searchParams.esc) filas = filas.filter((f) => f.escolaridad_estado === searchParams.esc);
  if (searchParams.seg === 'sin_caso') filas = filas.filter((f) => !f.caso_id || f.caso_estado === 'cerrado');
  if (searchParams.seg === 'abierto') filas = filas.filter((f) => f.caso_estado === 'abierto');
  if (searchParams.seg === 'sin_accion') filas = filas.filter((f) => f.caso_estado === 'abierto' && !f.proxima_accion);
  const conteo = (e: string) => ((filasRaw as any[]) ?? []).filter((f) => f.escolaridad_estado === e).length;
  const claves = ['personas_contacto_intentado', 'personas_conversacion', 'entrevistas_realizadas', 'inscripciones_confirmadas', 'compromisos_vencidos', 'casos_sin_proxima_accion'];

  return (
    <>
      <h1>Piloto Maimónides</h1>
      <p className="sub">Edades {prog.edad_min ?? 0} a {prog.edad_max ?? '—'} al 30/06/{ciclo}, más fichas sin fecha de nacimiento. El acercamiento se dirige a adultos responsables.</p>
      {(error || searchParams.error) && <div className="aviso danger">{error?.message ?? searchParams.error}</div>}

      <form className="panel fila">
        <div><label>Programa</label><select name="programa" defaultValue={prog.id}>{progs.map((p) => <option key={p.id} value={p.id}>{p.nombre}</option>)}</select></div>
        <div><label>Ciclo lectivo</label><input type="number" name="ciclo" defaultValue={ciclo} style={{ width: 100 }} /></div>
        <div><label>Escolaridad</label><select name="esc" defaultValue={searchParams.esc ?? ''}><option value="">Todas</option>
          {Object.keys(ESC_CHIP).map((e) => <option key={e} value={e}>{e} ({conteo(e)})</option>)}</select></div>
        <div><label>Seguimiento</label><select name="seg" defaultValue={searchParams.seg ?? ''}><option value="">Todos</option>
          <option value="sin_caso">Sin acercamiento asignado</option><option value="abierto">En curso</option><option value="sin_accion">En curso sin próxima acción</option></select></div>
        <button className="secundario">Filtrar</button>
      </form>

      <section className="panel"><Indicadores filas={((ind as any[]) ?? []).filter((i) => claves.includes(i.codigo))} /></section>

      <section className="panel tabla-wrap">
        <p className="sub">{filas.length} personas</p>
        <table>
          <thead><tr><th>Persona</th><th>Edad</th><th>Escolaridad {ciclo}</th><th>Seguimiento</th><th>Próxima acción</th></tr></thead>
          <tbody>{filas.map((f) => (
            <tr key={f.persona_id}>
              <td><Link href={`/personas/${f.persona_id}`}>{f.apellidos ? `${f.apellidos}, ` : ''}{f.nombres}</Link>
                {f.adultos_responsables === 0 && <div><span className="chip warn">sin adulto responsable</span></div>}
                {f.no_contactar && <div><span className="chip danger">familia pidió no contacto</span></div>}</td>
              <td className={f.edad === null ? 'sin-dato' : ''}>{edad(f.edad, f.precision_fecha)}</td>
              <td><span className={`chip ${ESC_CHIP[f.escolaridad_estado] ?? 'neutro'}`}>{f.escolaridad_estado}</span>
                {f.escolaridad_detalle && <div className="sub" style={{ margin: 0 }}>{f.escolaridad_detalle}</div>}</td>
              <td>{f.caso_id ? <><Link href={`/casos/${f.caso_id}`}>{f.etapa_nombre}</Link><div className="sub" style={{ margin: 0 }}>{f.responsable}</div></> : (
                f.escolaridad_estado === 'Matrícula confirmada en Maimónides' ? <span className="sin-dato">no aplica</span> :
                <details><summary>Asignar acercamiento</summary>
                  <form action={asignar.bind(null, prog.id, f.persona_id)} style={{ marginTop: '.5rem', minWidth: 260 }}>
                    <div className="campo"><label>Responsable</label><select name="responsable">{(resp as any[])?.map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}</select></div>
                    <div className="campo"><label>Motivo</label><input name="motivo" defaultValue={`Piloto Maimónides ${ciclo}: presentar la propuesta a la familia`} required /></div>
                    <div className="campo"><label>Primera acción</label><input name="accion" defaultValue="Contactar al adulto responsable" required /></div>
                    <div className="campo"><label>Vence</label><input type="date" name="vence" defaultValue={hoyMas(7)} required /></div>
                    <button>Asignar</button>
                  </form></details>)}</td>
              <td>{f.proxima_accion ? <>{f.proxima_accion}<div className={`sub`} style={{ margin: 0 }}>{f.vence_el < new Date().toISOString().slice(0, 10) ? <span className="chip danger">vencida {fecha(f.vence_el)}</span> : fecha(f.vence_el)}</div></>
                : f.caso_estado === 'abierto' ? <span className="chip warn">sin próxima acción</span> : <span className="sin-dato">—</span>}</td>
            </tr>))}</tbody>
        </table>
      </section>
    </>
  );
}
