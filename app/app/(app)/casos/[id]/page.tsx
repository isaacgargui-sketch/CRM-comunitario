import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireUser } from '@/lib/supabase/server';
import { BARRERAS, CANALES, edad, fecha, fechaHora, hoyMas, RESULTADOS } from '@/lib/format';
import * as A from './actions';

export default async function Caso({ params, searchParams }: { params: { id: string }; searchParams: { error?: string } }) {
  const { sb } = await requireUser();
  const { data: c } = await sb.from('casos').select('*, programas(nombre)').eq('id', params.id).maybeSingle();
  if (!c) notFound(); // sin permiso o inexistente: no se revela nada
  const [{ data: p }, { data: etapas }, { data: tareas }, { data: hist }, { data: inter }, { data: resp }, { data: vin }, { data: barr }] = await Promise.all([
    c.persona_id ? sb.from('personas_v').select('*').eq('id', c.persona_id).maybeSingle() : Promise.resolve({ data: null }),
    sb.from('catalogo_etapas').select('*').eq('tipo_programa', c.tipo_programa).order('orden'),
    sb.from('tareas').select('*, usuarios!tareas_responsable_id_fkey(nombre)').eq('caso_id', c.id).order('vence_el'),
    sb.from('caso_historial').select('*').eq('caso_id', c.id).order('en', { ascending: false }),
    sb.from('interacciones').select('*, personas!interacciones_persona_id_fkey(nombres, apellidos), usuarios(nombre)').eq('caso_id', c.id).order('fecha', { ascending: false }),
    sb.rpc('responsables_programa', { p_programa: c.programa_id }),
    c.persona_id ? sb.from('vinculos').select('persona_relacionada_id, categoria, detalle').eq('persona_id', c.persona_id).eq('vigente', true).in('categoria', ['adulto_responsable', 'contacto_autorizado']) : Promise.resolve({ data: [] }),
    sb.from('barreras').select('tipo, detalle, creado_en').eq('caso_id', c.id),
  ]);
  const ids = (vin ?? []).map((v: any) => v.persona_relacionada_id);
  const { data: adultos } = ids.length ? await sb.rpc('personas_resumen', { ids }) : { data: [] };
  const menorOSinDato = !p || p.edad === null ? c.tipo_programa === 'educacion' : p.edad < 18;
  const interlocutores = [
    ...(menorOSinDato ? [] : p ? [{ id: p.id, nombre: `${p.nombres} ${p.apellidos ?? ''} (la persona)` }] : []),
    ...(vin ?? []).map((v: any) => ({ id: v.persona_relacionada_id, nombre: `${(adultos as any[])?.find((a) => a.id === v.persona_relacionada_id)?.nombre ?? 'sin acceso'} (${v.detalle})` })),
  ];
  const nombreEtapa = (cod: string | null) => etapas?.find((e) => e.codigo === cod)?.nombre ?? cod;
  const pendientes = (tareas ?? []).filter((t) => ['pendiente', 'en_curso'].includes(t.estado));
  const hoy = new Date().toISOString().slice(0, 10);

  return (
    <>
      <p className="sub" style={{ marginBottom: '.25rem' }}>{(c as any).programas?.nombre}</p>
      <h1>{p ? <Link href={`/personas/${p.id}`}>{p.nombres} {p.apellidos ?? ''}</Link> : 'Caso de hogar'}</h1>
      <p className="sub">{p && <>Edad: {edad(p.edad, p.precision_fecha)} · </>}Etapa: <strong>{nombreEtapa(c.etapa)}</strong> · <span className={`chip ${c.estado === 'abierto' ? 'info' : 'neutro'}`}>{c.estado}</span> · abierto {fecha(c.abierto_en)}{c.motivo_cierre ? ` · motivo: ${c.motivo_cierre}` : ''}</p>
      {searchParams.error && <div className="aviso danger">{searchParams.error}</div>}
      {p?.no_contactar && <div className="aviso danger">Esta persona pidió no ser contactada.</div>}
      {menorOSinDato && interlocutores.length === 0 && <div className="aviso warn">No hay adultos responsables ni contactos autorizados vinculados. Registralos en la ficha antes de contactar.</div>}

      <div className="grid2">
        <section className="panel">
          <h2>Motivo y responsable</h2>
          <p>{c.motivo}</p>
          <form action={A.reasignar.bind(null, c.id)} className="fila">
            <select name="responsable" defaultValue={c.responsable_id} aria-label="Responsable">{(resp as any[])?.map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}</select>
            <button className="secundario">Reasignar</button>
          </form>
          {(barr ?? []).length > 0 && <><h3 style={{ marginTop: '1rem' }}>Barreras comunicadas por la familia</h3>
            {(barr ?? []).map((b, i) => <span key={i} className="chip neutro" style={{ marginRight: '.25rem' }}>{BARRERAS.find(([k]) => k === b.tipo)?.[1]}{b.detalle ? `: ${b.detalle}` : ''}</span>)}</>}
        </section>

        <section className="panel">
          <h2>Tareas</h2>
          {!pendientes.length && c.estado === 'abierto' && <div className="aviso warn">Caso sin próxima acción.</div>}
          {(tareas ?? []).map((t: any) => (
            <div key={t.id} style={{ borderTop: '1px solid var(--line)', padding: '.5rem 0' }}>
              <div className="fila" style={{ justifyContent: 'space-between' }}>
                <span>{t.accion}</span>
                <span className={`chip ${t.estado === 'cumplida' ? 'ok' : t.estado === 'cancelada' ? 'neutro' : t.vence_el < hoy ? 'danger' : 'info'}`}>{t.estado} · {fecha(t.vence_el)}</span>
              </div>
              <div className="sub" style={{ margin: 0 }}>{t.usuarios?.nombre}{t.resultado ? ` · ${t.resultado}` : ''}</div>
              {['pendiente', 'en_curso'].includes(t.estado) && (
                <form action={A.cumplirTarea.bind(null, c.id, t.id)} className="fila" style={{ marginTop: '.3rem' }}>
                  <input name="resultado" placeholder="Resultado" required aria-label="Resultado" /><button className="secundario">Marcar cumplida</button>
                </form>)}
            </div>))}
          <details style={{ marginTop: '.5rem' }}><summary>Agregar tarea</summary>
            <form action={A.nuevaTarea.bind(null, c.id)} style={{ marginTop: '.5rem' }}>
              <div className="campo"><label>Acción</label><input name="accion" required /></div>
              <div className="fila">
                <div><label>Vence</label><input type="date" name="vence" defaultValue={hoyMas(7)} required /></div>
                <div><label>Responsable</label><select name="responsable" defaultValue={c.responsable_id}>{(resp as any[])?.map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}</select></div>
                <div><label>Prioridad</label><select name="prioridad" defaultValue="normal"><option value="baja">Baja</option><option value="normal">Normal</option><option value="alta">Alta</option></select></div>
                <button>Agregar</button>
              </div>
            </form></details>
        </section>
      </div>

      {c.estado !== 'cerrado' && (
        <section className="panel">
          <h2>Registrar contacto</h2>
          <p className="sub">Resumen operativo: qué se habló y qué se acordó. Sin valoraciones personales ni datos de salud.</p>
          <form action={A.registrar.bind(null, c.id)}>
            <div className="fila">
              <div><label>Con quién</label><select name="interlocutor" required>{interlocutores.map((i) => <option key={i.id} value={i.id}>{i.nombre}</option>)}</select></div>
              <div><label>Canal</label><select name="canal">{CANALES.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></div>
              <div><label>Sentido</label><select name="direccion"><option value="saliente">Lo iniciamos nosotros</option><option value="entrante">Lo inició la familia</option></select></div>
              <div><label>Resultado</label><select name="resultado">{RESULTADOS.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></div>
              <div><label>Fecha</label><input type="datetime-local" name="fecha" /></div>
            </div>
            <div className="campo" style={{ marginTop: '.5rem' }}><label>Resumen (máx. 600 caracteres)</label><textarea name="resumen" maxLength={600} required /></div>
            <div className="fila">
              <div><label>Nueva etapa</label><select name="etapa" defaultValue=""><option value="">Sin cambio ({nombreEtapa(c.etapa)})</option>
                {etapas?.map((e) => <option key={e.codigo} value={e.codigo}>{e.nombre}</option>)}</select></div>
              <div style={{ flex: 1 }}><label>Motivo (obligatorio al pausar o cerrar)</label><input name="motivo" style={{ width: '100%' }} /></div>
            </div>
            {c.tipo_programa === 'educacion' && (
              <fieldset style={{ border: 0, padding: 0, margin: '.75rem 0' }}>
                <label>Barreras que la familia comunicó en este contacto (solo si las dijo)</label>
                <div className="fila">{BARRERAS.map(([k, v]) => <label key={k} className="fila" style={{ color: 'var(--ink)', margin: 0 }}><input type="checkbox" name="barrera" value={k} /> {v}</label>)}
                  <input name="barrera_detalle" placeholder="Detalle si es “otra”" /></div>
              </fieldset>)}
            <div className="fila" style={{ marginTop: '.5rem' }}>
              {pendientes.length > 0 && <div><label>Completa la tarea</label><select name="completar" defaultValue={pendientes[0]?.id}><option value="">Ninguna</option>{pendientes.map((t) => <option key={t.id} value={t.id}>{t.accion}</option>)}</select></div>}
              <div style={{ flex: 1 }}><label>Próximo paso</label><input name="prox_accion" style={{ width: '100%' }} placeholder="p. ej. Proponer entrevista" /></div>
              <div><label>Vence</label><input type="date" name="prox_vence" defaultValue={hoyMas(7)} /></div>
              <div><label>Responsable</label><select name="prox_resp" defaultValue={c.responsable_id}>{(resp as any[])?.map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}</select></div>
            </div>
            <button style={{ marginTop: '.75rem' }} disabled={!interlocutores.length}>Guardar contacto</button>
          </form>
        </section>)}

      <section className="panel">
        <h2>Historial</h2>
        <div className="linea">
          {[...(inter ?? []).map((i: any) => ({ en: i.fecha, t: `${CANALES.find(([k]) => k === i.canal)?.[1]} con ${i.personas?.nombres ?? ''} ${i.personas?.apellidos ?? ''} · ${RESULTADOS.find(([k]) => k === i.resultado)?.[1]}`, d: i.resumen, u: i.usuarios?.nombre })),
            ...(hist ?? []).map((h) => ({ en: h.en, t: `Etapa: ${nombreEtapa(h.etapa_nueva)}${h.estado_nuevo !== 'abierto' ? ` (${h.estado_nuevo})` : ''}`, d: h.motivo, u: '' }))]
            .sort((a, b) => (a.en < b.en ? 1 : -1))
            .map((e, i) => <div className="ev" key={i}><div className="meta">{fechaHora(e.en)}{e.u ? ` · ${e.u}` : ''}</div><div>{e.t}</div>{e.d && <div className="sub" style={{ margin: 0 }}>{e.d}</div>}</div>)}
        </div>
      </section>
    </>
  );
}
