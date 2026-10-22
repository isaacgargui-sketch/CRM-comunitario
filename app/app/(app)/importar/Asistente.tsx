'use client';
import { useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import * as XLSX from 'xlsx';
import { supabaseBrowser } from '@/lib/supabase/client';

type Fuente = { id: string; nombre: string; institucion_id: string; proposito_autorizado: string; instituciones: { nombre: string } | null };
type Inst = { id: string; nombre: string };

const CAMPOS: [string, string, RegExp][] = [
  ['nombres', 'Nombres', /^(nombres?|first.?name)$/i],
  ['apellidos', 'Apellidos', /^(apellidos?|last.?name|surname)$/i],
  ['nombre_completo', 'Nombre y apellido juntos', /(nombre.*apellido|apellido.*nombre|nombre completo|full.?name)/i],
  ['telefono', 'Teléfono', /(tel|cel|whats|movil|móvil)/i],
  ['email', 'Correo', /(mail|correo)/i],
  ['direccion', 'Dirección', /(direcc|domicilio|calle)/i],
  ['fecha_nacimiento', 'Fecha de nacimiento', /(nacim|f\.?\s?nac|cumple)/i],
  ['nivel', 'Nivel (matrícula)', /^nivel$/i],
  ['grado_sala', 'Grado o sala (matrícula)', /(grado|sala|curso|año)/i],
];
const PASOS = ['Archivo', 'Origen y alcance', 'Vista previa', 'Columnas', 'Validar y revisar'];

const celda = (v: unknown) => v instanceof Date
  ? `${v.getFullYear()}-${String(v.getMonth() + 1).padStart(2, '0')}-${String(v.getDate()).padStart(2, '0')}`
  : String(v ?? '').trim();

async function sha256(buf: ArrayBuffer) {
  const h = await crypto.subtle.digest('SHA-256', buf);
  return Array.from(new Uint8Array(h)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function Asistente({ fuentes, instituciones }: { fuentes: Fuente[]; instituciones: Inst[] }) {
  const router = useRouter();
  const [paso, setPaso] = useState(0);
  const [archivo, setArchivo] = useState<{ nombre: string; hash: string; cab: string[]; filas: string[][] } | null>(null);
  const [fuenteId, setFuenteId] = useState(fuentes[0]?.id ?? '');
  const fuente = fuentes.find((f) => f.id === fuenteId);
  const [proposito, setProposito] = useState(fuentes[0]?.proposito_autorizado ?? '');
  const [fechaDatos, setFechaDatos] = useState(new Date().toISOString().slice(0, 10));
  const [autorizadas, setAutorizadas] = useState<string[]>(fuentes[0] ? [fuentes[0].institucion_id] : []);
  const [tipo, setTipo] = useState<'personas' | 'matricula'>('personas');
  const [mat, setMat] = useState({ escuela: 'Colegio Maimónides', categoria: 'maimonides', ciclo: String(new Date().getFullYear()) });
  const [mapa, setMapa] = useState<Record<string, number>>({});
  const [error, setError] = useState('');
  const [enviando, setEnviando] = useState(false);

  async function leer(f: File) {
    setError('');
    try {
      const buf = await f.arrayBuffer();
      const wb = XLSX.read(buf, { cellDates: true });
      const hoja = wb.Sheets[wb.SheetNames[0]];
      const m = XLSX.utils.sheet_to_json<unknown[]>(hoja, { header: 1, raw: true, defval: '' });
      const [cab, ...resto] = m;
      const filas = resto.map((r) => r.map(celda)).filter((r) => r.some((c) => c !== ''));
      const cabeceras = (cab ?? []).map((c) => celda(c));
      const auto: Record<string, number> = {};
      CAMPOS.forEach(([k, , rx]) => { const i = cabeceras.findIndex((c) => rx.test(c)); if (i >= 0) auto[k] = i; });
      if (auto.nombre_completo !== undefined && auto.nombres !== undefined) delete auto.nombre_completo;
      setMapa(auto);
      setArchivo({ nombre: f.name, hash: await sha256(buf), cab: cabeceras, filas });
      setPaso(1);
    } catch {
      setError('No se pudo leer el archivo. Usá Excel (.xlsx) o CSV con la primera fila como encabezado.');
    }
  }

  const filasMapeadas = useMemo(() => (archivo?.filas ?? []).map((r) => {
    const o: Record<string, unknown> = {};
    CAMPOS.forEach(([k]) => { if (mapa[k] !== undefined) o[k] = r[mapa[k]] ?? ''; });
    if (o.nombre_completo && !o.nombres) {
      // "Apellido, Nombre" se separa por la coma; sin coma se carga todo como nombre (no se adivina el apellido)
      const t = String(o.nombre_completo);
      if (t.includes(',')) { const [a, n] = t.split(','); o.apellidos = a.trim(); o.nombres = n.trim(); } else o.nombres = t;
    }
    delete o.nombre_completo;
    o._original = Object.fromEntries((archivo?.cab ?? []).map((c, i) => [c || `columna_${i + 1}`, r[i] ?? '']));
    return o;
  }), [archivo, mapa]);
  const sinNombre = filasMapeadas.filter((f) => !String(f.nombres ?? '').trim()).length;

  async function preparar() {
    setEnviando(true); setError('');
    const { data, error } = await supabaseBrowser().rpc('importacion_preparar', {
      meta: {
        fuente_id: fuenteId, archivo_nombre: archivo!.nombre, archivo_sha256: archivo!.hash, proposito,
        fecha_datos: fechaDatos, instituciones_autorizadas: autorizadas, tipo,
        ...(tipo === 'matricula' ? { matricula_escuela: mat.escuela, matricula_categoria: mat.categoria, matricula_ciclo: Number(mat.ciclo) } : {}),
      },
      filas: filasMapeadas,
    });
    setEnviando(false);
    if (error) return setError(error.message);
    router.push(`/importar/${data}`);
  }

  return (
    <section className="panel">
      <h2>Nueva importación</h2>
      <ol className="pasos">{PASOS.map((p, i) => <li key={p} className={i === paso ? 'activo' : ''}>{p}</li>)}</ol>
      {error && <div className="aviso danger">{error}</div>}

      {paso === 0 && (
        <div className="campo"><label htmlFor="arch">Archivo Excel o CSV (primera fila: encabezados)</label>
          <input id="arch" type="file" accept=".xlsx,.xls,.csv" onChange={(e) => e.target.files?.[0] && leer(e.target.files[0])} /></div>)}

      {paso === 1 && archivo && (
        <div style={{ maxWidth: 620 }}>
          <p><strong>{archivo.nombre}</strong> · {archivo.filas.length} filas</p>
          <div className="campo"><label>Fuente (institución de origen)</label>
            <select value={fuenteId} onChange={(e) => { const f = fuentes.find((x) => x.id === e.target.value); setFuenteId(e.target.value); setProposito(f?.proposito_autorizado ?? ''); setAutorizadas(f ? [f.institucion_id] : []); }}>
              {fuentes.map((f) => <option key={f.id} value={f.id}>{f.instituciones?.nombre} · {f.nombre}</option>)}</select></div>
          <div className="campo"><label>Propósito autorizado para este archivo</label><input value={proposito} onChange={(e) => setProposito(e.target.value)} required /></div>
          <div className="campo"><label>Fecha a la que corresponden los datos</label><input type="date" value={fechaDatos} onChange={(e) => setFechaDatos(e.target.value)} /></div>
          <div className="campo"><label>Instituciones autorizadas a usar estos datos</label>
            {instituciones.map((i) => (
              <label key={i.id} className="fila" style={{ color: 'var(--ink)' }}><input type="checkbox" checked={autorizadas.includes(i.id)}
                onChange={(e) => setAutorizadas(e.target.checked ? [...autorizadas, i.id] : autorizadas.filter((x) => x !== i.id))} /> {i.nombre}</label>))}</div>
          <div className="campo"><label>Tipo de archivo</label>
            <select value={tipo} onChange={(e) => setTipo(e.target.value as 'personas' | 'matricula')}>
              <option value="personas">Listado de personas</option><option value="matricula">Matrícula escolar (confirma escolaridad)</option></select></div>
          {tipo === 'matricula' && (
            <div className="fila">
              <div><label>Escuela</label><input value={mat.escuela} onChange={(e) => setMat({ ...mat, escuela: e.target.value })} /></div>
              <div><label>Categoría</label><select value={mat.categoria} onChange={(e) => setMat({ ...mat, categoria: e.target.value })}>
                <option value="maimonides">Maimónides</option><option value="otra_judia">Otra escuela judía</option><option value="otra">Otra escuela</option></select></div>
              <div><label>Ciclo lectivo</label><input type="number" value={mat.ciclo} onChange={(e) => setMat({ ...mat, ciclo: e.target.value })} style={{ width: 100 }} /></div>
            </div>)}
          <div className="fila" style={{ marginTop: '1rem' }}>
            <button className="secundario" onClick={() => { setArchivo(null); setPaso(0); }}>Cambiar archivo</button>
            <button disabled={!proposito.trim() || !autorizadas.length} onClick={() => setPaso(2)}>Continuar</button>
          </div>
        </div>)}

      {paso === 2 && archivo && (
        <>
          <div className="tabla-wrap"><table>
            <thead><tr>{archivo.cab.map((c, i) => <th key={i}>{c || `Columna ${i + 1}`}</th>)}</tr></thead>
            <tbody>{archivo.filas.slice(0, 10).map((r, i) => <tr key={i}>{archivo.cab.map((_, j) => <td key={j}>{r[j]}</td>)}</tr>)}</tbody>
          </table></div>
          <p className="sub">Primeras 10 de {archivo.filas.length} filas.</p>
          <div className="fila"><button className="secundario" onClick={() => setPaso(1)}>Volver</button><button onClick={() => setPaso(3)}>Continuar</button></div>
        </>)}

      {paso === 3 && archivo && (
        <div style={{ maxWidth: 620 }}>
          <p className="sub">Indicá qué columna corresponde a cada dato. Lo que no esté en el archivo queda “sin dato”.</p>
          {CAMPOS.filter(([k]) => tipo === 'matricula' || !['nivel', 'grado_sala'].includes(k)).map(([k, label]) => (
            <div className="campo" key={k}><label>{label}</label>
              <select value={mapa[k] ?? ''} onChange={(e) => { const m = { ...mapa }; if (e.target.value === '') delete m[k]; else m[k] = Number(e.target.value); setMapa(m); }}>
                <option value="">— no está en el archivo —</option>
                {archivo.cab.map((c, i) => <option key={i} value={i}>{c || `Columna ${i + 1}`}</option>)}</select></div>))}
          <div className="fila"><button className="secundario" onClick={() => setPaso(2)}>Volver</button>
            <button disabled={mapa.nombres === undefined && mapa.nombre_completo === undefined} onClick={() => setPaso(4)}>Continuar</button></div>
        </div>)}

      {paso === 4 && archivo && (
        <>
          <p>{filasMapeadas.length} filas para validar.{sinNombre > 0 && <> <span className="chip warn">{sinNombre} sin nombre</span> quedarán como error en el informe.</>}</p>
          <p className="sub">Al continuar se validan formatos y se buscan posibles duplicados. Todavía no se guarda ninguna ficha: vas a poder revisar y confirmar.</p>
          <div className="fila"><button className="secundario" onClick={() => setPaso(3)}>Volver</button>
            <button disabled={enviando} onClick={preparar}>{enviando ? 'Validando…' : 'Validar y revisar'}</button></div>
        </>)}
    </section>
  );
}
