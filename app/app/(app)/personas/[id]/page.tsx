import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireUser } from '@/lib/supabase/server';
import { edad, ESTADO_DATO, fecha, fechaHora, hoyMas, nacimiento, SIN_DATO } from '@/lib/format';
import * as A from './actions';

const chipDato = (e: string) =>
  <span className={`chip ${e === 'confirmado' ? 'ok' : e === 'desactualizado' ? 'danger' : 'neutro'}`}>{ESTADO_DATO[e] ?? e}</span>;

const CAT_ESC: Record<string, string> = { maimonides: 'Maimónides', otra_judia: 'Otra escuela judía', otra: 'Otra escuela', sin_verificar: 'Sin verificar' };
const CAT_VIN: Record<string, string> = { parentesco: 'Parentesco', adulto_responsable: 'Adulto responsable', contacto_autorizado: 'Contacto autorizado' };

export default async function Ficha({ params, searchParams }: { params: { id: string }; searchParams: { error?: string; vq?: string } }) {
  const { sb } = await requireUser();
  const id = params.id;
  const { data: p } = await sb.from('personas_v').select('*').eq('id', id).maybeSingle();
  if (!p) notFound();

  const [contactos, domicilios, vinA, vinB, esc, casos, crono, prefs, discs, alcance, progs] = await Promise.all([
    sb.from('medios_contacto').select('*').eq('persona_id', id).order('vigente', { ascending: false }).order('creado_en'),
    sb.from('domicilios').select('*').eq('persona_id', id),
    sb.from('vinculos').select('*').eq('persona_id', id).eq('vigente', true),
    sb.from('vinculos').select('*').eq('persona_relacionada_id', id).eq('vigente', true),
    sb.from('escolaridad').select('*').eq('persona_id', id).order('ciclo_lectivo', { ascending: false }),
    sb.from('casos').select('id, etapa, estado, motivo, abierto_en, tipo_programa, programas(nombre), usuarios!casos_responsable_id_fkey(nombre)').eq('persona_id', id).order('abierto_en', { ascending: false }),
    sb.rpc('cronologia_persona', { p_persona: id }),
    sb.from('preferencias_contacto').select('*').eq('persona_id', id).eq('vigente', true),
    sb.from('discrepancias').select('*').eq('persona_id', id).eq('estado', 'pendiente'),
    sb.from('persona_institucion').select('instituciones(nombre), lotes_importacion(archivo_nombre, fecha_datos)').eq('persona_id', id),
    sb.from('programas').select('id, nombre').eq('estado', 'activo'),
  ]);
  const { data: etapas } = await sb.from('catalogo_etapas').select('tipo_programa, codigo, nombre');
  const nombreEtapa = (t: string, c: string) => etapas?.find((e) => e.tipo_programa === t && e.codigo === c)?.nombre ?? c;
  const otrosIds = [...(vinA.data ?? []).map((v) => v.persona_relacionada_id), ...(vinB.data ?? []).map((v) => v.persona_id)];
  const { data: otros } = otrosIds.length ? await sb.rpc('personas_resumen', { ids: otrosIds }) : { data: [] };
  const nom = (pid: string) => (otros as any[])?.find((o) => o.id === pid)?.nombre ?? 'Ficha sin acceso';
  const { data: busqueda } = searchParams.vq ? await sb.rpc('buscar_personas', { q: searchParams.vq, limite: 8 }) : { data: null };
  const noContactar = (prefs.data ?? []).some((x) => !x.permitido && x.canal === 'todos');

  return (
    <>
      <p className="sub" style={{ marginBottom: '.25rem' }}><Link href="/personas">Personas</Link></p>
      <h1>{p.nombres} {p.apellidos ?? ''}</h1>
      <p className="sub">
        {p.nombre_preferido && <>Prefiere “{p.nombre_preferido}” · </>}
        Nacimiento: {nacimiento(p.fecha_nacimiento, p.precision_fecha)} {chipDato(p.fecha_nacimiento_estado)} · Edad: {edad(p.edad, p.precision_fecha)}
        {p.estado_registro !== 'activo' && <> · <span className="chip warn">{p.estado_registro}</span></>}
      </p>
      {searchParams.error && <div className="aviso danger">{searchParams.error}</div>}
      {noContactar && <div className="aviso danger">Pidió no ser contactada. No se registran contactos salientes.</div>}
      {(discs.data ?? []).length > 0 && (
        <div className="aviso warn">
          <strong>Datos en conflicto por revisar</strong>
          {(discs.data ?? []).map((d) => (
            <div key={d.id} className="fila" style={{ marginTop: '.4rem' }}>
              <span>{d.campo}: cargado “{d.valor_existente}”, el archivo dice “{d.valor_nuevo}”.</span>
              <form action={A.resolverDiscrepancia.bind(null, id, d.id, false)}><button className="secundario">Mantener</button></form>
              <form action={A.resolverDiscrepancia.bind(null, id, d.id, true)}><button className="secundario">Usar el nuevo</button></form>
            </div>))}
        </div>)}

      <div className="grid2">
        <section className="panel">
          <h2>Contacto</h2>
          {!(contactos.data ?? []).length && <p className="sin-dato">{SIN_DATO}</p>}
          <table><tbody>{(contactos.data ?? []).map((c) => (
            <tr key={c.id} style={{ opacity: c.vigente ? 1 : .55 }}>
              <td>{c.tipo === 'telefono' ? 'Tel.' : 'Correo'}</td>
              <td>{c.valor_original}{c.preferido && <span className="chip info"> preferido</span>}</td>
              <td>{chipDato(c.estado)}</td>
              <td className="fila">{c.vigente && c.estado !== 'confirmado' &&
                <form action={A.verificarContacto.bind(null, id, c.id)}><button className="secundario">Verificado</button></form>}
                {c.vigente && <form action={A.contactoDesactualizado.bind(null, id, c.id)}><button className="secundario">Ya no sirve</button></form>}</td>
            </tr>))}</tbody></table>
          <form action={A.agregarContacto.bind(null, id)} className="fila" style={{ marginTop: '.75rem' }}>
            <select name="tipo" aria-label="Tipo"><option value="telefono">Teléfono</option><option value="email">Correo</option></select>
            <input name="valor" required aria-label="Valor" placeholder="Número o correo" />
            <label className="fila" style={{ margin: 0 }}><input type="checkbox" name="preferido" /> preferido</label>
            <button>Agregar</button>
          </form>
          <h3 style={{ marginTop: '1rem' }}>Domicilios</h3>
          {(domicilios.data ?? []).length ? (domicilios.data ?? []).map((d) => <div key={d.id}>{d.direccion_original} {chipDato(d.estado)}</div>)
            : <p className="sin-dato">{SIN_DATO}</p>}
        </section>

        <section className="panel">
          <h2>Preferencias de contacto</h2>
          {(prefs.data ?? []).length === 0 && <p className="sin-dato">Sin preferencias registradas (no implica autorización ni rechazo).</p>}
          {(prefs.data ?? []).map((x) => (
            <div key={x.id} className="fila" style={{ marginBottom: '.4rem' }}>
              <span className={`chip ${x.permitido ? 'ok' : 'danger'}`}>{x.permitido ? 'Acepta' : 'No acepta'} · {x.canal}</span>
              <span className="sub" style={{ margin: 0 }}>{x.proposito ?? ''} — {x.fuente}, {fecha(x.documentado_en)}</span>
              <form action={A.dejarSinEfectoPreferencia.bind(null, id, x.id)}><button className="secundario">Dejar sin efecto</button></form>
            </div>))}
          <form action={A.registrarPreferencia.bind(null, id)} style={{ marginTop: '.75rem' }}>
            <div className="fila">
              <select name="permitido" aria-label="Permiso"><option value="no">No contactar</option><option value="si">Acepta contacto</option></select>
              <select name="canal" aria-label="Canal"><option value="todos">Todos los canales</option><option value="telefono">Teléfono</option><option value="whatsapp">WhatsApp</option><option value="email">Correo</option><option value="presencial">Presencial</option></select>
            </div>
            <div className="fila" style={{ marginTop: '.5rem' }}>
              <input name="proposito" placeholder="Propósito o alcance" />
              <input name="fuente" placeholder="Cómo se pidió (llamada, nota…)" required />
              <button>Registrar</button>
            </div>
          </form>
        </section>
      </div>

      <section className="panel">
        <h2>Vínculos</h2>
        <p className="sub">Parentesco, adulto responsable y contacto autorizado son registros distintos. No se deducen por apellido, domicilio ni teléfono.</p>
        <table><tbody>
          {(vinA.data ?? []).map((v) => (
            <tr key={v.id}><td><Link href={`/personas/${v.persona_relacionada_id}`}>{nom(v.persona_relacionada_id)}</Link></td>
              <td>{v.detalle}</td><td>{CAT_VIN[v.categoria]}</td><td>{chipDato(v.estado)}</td>
              <td><form action={A.finalizarVinculo.bind(null, id, v.id)}><button className="secundario">Finalizar</button></form></td></tr>))}
          {(vinB.data ?? []).map((v) => (
            <tr key={v.id}><td><Link href={`/personas/${v.persona_id}`}>{nom(v.persona_id)}</Link></td>
              <td>esta persona es: {v.detalle}</td><td>{CAT_VIN[v.categoria]}</td><td>{chipDato(v.estado)}</td><td /></tr>))}
        </tbody></table>
        {!otrosIds.length && <p className="sin-dato">{SIN_DATO}</p>}
        <form className="fila" style={{ marginTop: '.75rem' }}>
          <input name="vq" defaultValue={searchParams.vq} placeholder="Buscar persona para vincular" aria-label="Buscar persona" />
          <button className="secundario">Buscar</button>
        </form>
        {(busqueda as any[] | null)?.filter((b) => b.id !== id).map((b) => (
          <form key={b.id} action={A.agregarVinculo.bind(null, id, b.id)} className="fila" style={{ marginTop: '.5rem' }}>
            <strong>{b.nombres} {b.apellidos}</strong><span className="sub" style={{ margin: 0 }}>{edad(b.edad, b.precision_fecha)}</span>
            <span>es</span>
            <input name="detalle" required placeholder="madre, tío, tutora legal…" aria-label="Detalle" />
            <select name="categoria" aria-label="Categoría"><option value="parentesco">Parentesco</option><option value="adulto_responsable">Adulto responsable</option><option value="contacto_autorizado">Contacto autorizado</option></select>
            <label className="fila" style={{ margin: 0 }}><input type="checkbox" name="verificado" /> verificado</label>
            <button>Vincular</button>
          </form>))}
      </section>

      <section className="panel">
        <h2>Escolaridad</h2>
        {esc.error || (esc.data ?? []).length === 0
          ? <p className="sin-dato">Sin escolaridad registrada o sin permiso para verla. La ausencia de registro no indica falta de escolaridad.</p>
          : <div className="tabla-wrap"><table>
            <thead><tr><th>Ciclo</th><th>Escuela</th><th>Nivel y grado</th><th>Estado</th><th>Fuente</th></tr></thead>
            <tbody>{(esc.data ?? []).map((e) => (
              <tr key={e.id}><td>{e.ciclo_lectivo}</td><td>{CAT_ESC[e.categoria]}{e.escuela_nombre ? ` · ${e.escuela_nombre}` : ''}</td>
                <td>{[e.nivel, e.grado_sala].filter(Boolean).join(' · ') || <span className="sin-dato">{SIN_DATO}</span>}</td>
                <td>{chipDato(e.estado)}</td><td className="sub">{e.nota ?? ''} {e.verificado_en ? `(verif. ${fecha(e.verificado_en)})` : ''}</td></tr>))}</tbody>
          </table></div>}
        <form action={A.agregarEscolaridad.bind(null, id)} className="fila" style={{ marginTop: '.75rem' }}>
          <input name="ciclo" type="number" defaultValue={new Date().getFullYear()} style={{ width: 90 }} aria-label="Ciclo lectivo" />
          <select name="categoria" aria-label="Escuela"><option value="otra">Otra escuela</option><option value="otra_judia">Otra escuela judía</option><option value="maimonides">Maimónides</option></select>
          <input name="escuela" placeholder="Nombre de la escuela" />
          <select name="nivel" aria-label="Nivel"><option value="">Nivel</option><option value="inicial">Inicial</option><option value="primario">Primario</option><option value="secundario">Secundario</option></select>
          <input name="grado" placeholder="Grado o sala" style={{ width: 110 }} />
          <select name="estado" aria-label="Estado"><option value="pendiente_verificacion">Sin verificar</option><option value="confirmado">Confirmado</option></select>
          <input name="fuente" placeholder="Fuente (p. ej. lo dijo la madre)" required />
          <button>Registrar</button>
        </form>
      </section>

      <section className="panel">
        <h2>Seguimiento</h2>
        {(casos.data ?? []).length === 0 && <p className="sin-dato">Sin casos visibles para tus programas.</p>}
        <table><tbody>{(casos.data ?? []).map((c: any) => (
          <tr key={c.id}><td><Link href={`/casos/${c.id}`}>{c.programas?.nombre}</Link></td>
            <td>{nombreEtapa(c.tipo_programa, c.etapa)}</td><td><span className={`chip ${c.estado === 'abierto' ? 'info' : 'neutro'}`}>{c.estado}</span></td>
            <td>{c.usuarios?.nombre}</td><td className="sub">desde {fecha(c.abierto_en)}</td></tr>))}</tbody></table>
        <details style={{ marginTop: '.75rem' }}><summary>Abrir un caso de seguimiento</summary>
          <form action={A.abrirCaso.bind(null, id)} style={{ marginTop: '.5rem', maxWidth: 560 }}>
            <div className="campo"><label>Programa</label><select name="programa">{progs.data?.map((g) => <option key={g.id} value={g.id}>{g.nombre}</option>)}</select></div>
            <div className="campo"><label>Motivo documentado</label><input name="motivo" required /></div>
            <div className="campo"><label>Primera acción</label><input name="accion" required /></div>
            <div className="campo"><label>Vence</label><input name="vence" type="date" defaultValue={hoyMas(7)} required /></div>
            <p className="sub">Quedás como responsable; podés reasignarlo desde el caso.</p>
            <button>Abrir caso</button>
          </form></details>
      </section>

      <section className="panel">
        <h2>Cronología</h2>
        {!(crono.data as any[])?.length ? <p className="sin-dato">Sin interacciones visibles.</p> : (
          <div className="linea">{(crono.data as any[]).map((e, i) => (
            <div className="ev" key={i}>
              <div className="meta">{fechaHora(e.fecha)} · {e.programa}{e.usuario ? ` · ${e.usuario}` : ''}</div>
              <div><Link href={`/casos/${e.caso_id}`}>{e.titulo}</Link></div>
              {e.detalle && <div className="sub" style={{ margin: 0 }}>{e.detalle}</div>}
            </div>))}</div>)}
      </section>

      <section className="panel">
        <h2>Procedencia</h2>
        {(alcance.data ?? []).map((a: any, i) => (
          <div key={i}>{a.instituciones?.nombre}{a.lotes_importacion ? ` · importado de ${a.lotes_importacion.archivo_nombre} (${fecha(a.lotes_importacion.fecha_datos)})` : ' · carga manual'}</div>))}
        <p className="sub">Alta: {fechaHora(p.creado_en)} · última actualización: {fechaHora(p.actualizado_en)}</p>
      </section>
    </>
  );
}
