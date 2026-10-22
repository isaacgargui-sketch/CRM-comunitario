import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireUser } from '@/lib/supabase/server';
import { fecha, fechaHora, SIN_DATO } from '@/lib/format';
import * as A from './actions';

const RESULTADO: Record<string, string> = {
  persona_creada: 'Fichas nuevas', vinculada_existente: 'Vinculadas a fichas existentes',
  repetida_en_reimportacion: 'Ya importadas antes (sin duplicar)', omitida: 'Omitidas', error: 'Con error',
};

export default async function Lote({ params, searchParams }: { params: { lote: string }; searchParams: { error?: string } }) {
  const { sb } = await requireUser();
  const { data: l } = await sb.from('lotes_importacion').select('*, fuentes(nombre)').eq('id', params.lote).maybeSingle();
  if (!l) notFound();
  const { data: filas } = await sb.from('filas_importacion').select('*').eq('lote_id', l.id).order('nro_fila');
  const todas = filas ?? [];
  const pendientes = todas.filter((f) => f.decision === null && f.errores.length === 0);
  const conCandidatos = todas.filter((f) => f.errores.length === 0 && (f.candidatos as any[]).length > 0);
  const ids = Array.from(new Set(conCandidatos.flatMap((f) => (f.candidatos as any[]).map((c) => c.persona_id))));
  const { data: personas } = ids.length ? await sb.rpc('personas_resumen', { ids }) : { data: [] };
  const per = (id: string) => (personas as any[]).find((p) => p.id === id);
  const conProblemas = todas.filter((f) => f.errores.length || f.advertencias.length);
  const n = (d: any) => d.datos_normalizados ?? {};

  return (
    <>
      <p className="sub" style={{ marginBottom: '.25rem' }}><Link href="/importar">Importaciones</Link></p>
      <h1>{l.archivo_nombre}</h1>
      <p className="sub">{(l as any).fuentes?.nombre} · datos al {fecha(l.fecha_datos)} · {l.tipo === 'matricula' ? `matrícula ${l.matricula_escuela} ${l.matricula_ciclo}` : 'listado de personas'} · propósito: {l.proposito} · cargado {fechaHora(l.creado_en)}</p>
      {searchParams.error && <div className="aviso danger">{searchParams.error}</div>}

      {l.estado === 'borrador' && (
        <section className="panel">
          <h2>Revisión antes de confirmar</h2>
          <p>{todas.length} filas · {todas.filter((f) => f.decision === 'crear').length} fichas nuevas · {todas.filter((f) => f.decision === 'vincular').length} a vincular · {todas.filter((f) => f.decision === 'omitir').length} omitidas · {todas.filter((f) => f.errores.length).length} con error · <strong>{pendientes.length} por revisar</strong></p>
          <div className="fila">
            <form action={A.confirmar.bind(null, l.id)}><button disabled={pendientes.length > 0}>Confirmar importación</button></form>
            {pendientes.length > 0 && <form action={A.crearPendientes.bind(null, l.id)}><button className="secundario">Crear las {pendientes.length} pendientes como fichas nuevas</button></form>}
            <a className="boton secundario" href={`/importar/${l.id}/informe`}>Descargar informe de errores</a>
            <form action={A.cancelar.bind(null, l.id)}><button className="secundario">Descartar lote</button></form>
          </div>
        </section>)}

      {l.estado !== 'borrador' && (
        <section className="panel">
          <h2>{l.estado === 'confirmado' ? 'Importación confirmada' : 'Lote revertido'}</h2>
          <div className="kpis">{Object.entries((l.resumen ?? {}) as Record<string, any>).filter(([k]) => k !== 'reversion').map(([k, v]) => (
            <div className="kpi" key={k}><div className="d">{RESULTADO[k] ?? k}</div><div className="v">{v}</div></div>))}</div>
          {l.resumen?.reversion && <p style={{ marginTop: '1rem' }}>Reversión: {l.resumen.reversion.personas_eliminadas} fichas eliminadas; {l.resumen.reversion.personas_conservadas_por_datos_posteriores} conservadas porque tienen datos posteriores válidos. Motivo: {l.motivo_reversion}</p>}
          <div className="fila" style={{ marginTop: '1rem' }}>
            <a className="boton secundario" href={`/importar/${l.id}/informe`}>Descargar informe de errores</a>
            {l.estado === 'confirmado' && (
              <form action={A.revertir.bind(null, l.id)} className="fila">
                <input name="motivo" placeholder="Motivo de la reversión" required aria-label="Motivo" />
                <button className="peligro">Revertir lote</button>
              </form>)}
          </div>
        </section>)}

      {conCandidatos.length > 0 && (
        <section className="panel">
          <h2>Posibles coincidencias</h2>
          <p className="sub">Compartir teléfono, apellido o domicilio no prueba que sea la misma persona. Decidí fila por fila.</p>
          {conCandidatos.map((f) => (
            <div key={f.id} style={{ borderTop: '1px solid var(--line)', padding: '.75rem 0' }}>
              <div className="fila" style={{ justifyContent: 'space-between' }}>
                <div><strong>Fila {f.nro_fila}:</strong> {n(f).nombres} {n(f).apellidos ?? ''} · nac. {n(f).fecha_nacimiento ? fecha(n(f).fecha_nacimiento) : SIN_DATO} · {n(f).telefono_original ?? 'sin teléfono'}</div>
                <span className={`chip ${f.decision ? 'ok' : 'warn'}`}>{f.decision ?? 'por revisar'}</span>
              </div>
              {(f.candidatos as any[]).map((c) => { const p = per(c.persona_id); return (
                <div key={c.persona_id} className="fila" style={{ margin: '.4rem 0 0 1rem' }}>
                  <span>{p ? <Link href={`/personas/${p.id}`}>{p.nombre}</Link> : 'ficha'} · nac. {p?.fecha_nacimiento ? fecha(p.fecha_nacimiento) : SIN_DATO} · {c.motivos.join('; ')}</span>
                  {l.estado === 'borrador' && <form action={A.resolver.bind(null, l.id, f.id, 'vincular', c.persona_id)}><button className="secundario">Es esta persona</button></form>}
                </div>); })}
              {l.estado === 'borrador' && (
                <div className="fila" style={{ margin: '.4rem 0 0 1rem' }}>
                  <form action={A.resolver.bind(null, l.id, f.id, 'crear', null)}><button className="secundario">Es otra persona: crear ficha</button></form>
                  <form action={A.resolver.bind(null, l.id, f.id, 'omitir', null)}><button className="secundario">Omitir fila</button></form>
                </div>)}
            </div>))}
        </section>)}

      <section className="panel tabla-wrap">
        <h2>Errores y advertencias</h2>
        {!conProblemas.length ? <p className="sin-dato">Sin errores ni advertencias.</p> : (
          <table><thead><tr><th>Fila</th><th>Errores</th><th>Advertencias</th><th>Datos originales</th></tr></thead>
            <tbody>{conProblemas.map((f) => (
              <tr key={f.id}><td>{f.nro_fila}</td><td>{f.errores.join('; ')}</td><td>{f.advertencias.join('; ')}</td>
                <td className="sub">{Object.values(f.datos_originales as Record<string, string>).filter(Boolean).join(' · ')}</td></tr>))}</tbody></table>)}
      </section>
    </>
  );
}
