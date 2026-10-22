import Link from 'next/link';
import { requireUser } from '@/lib/supabase/server';
import { fecha, fechaHora } from '@/lib/format';
import { Asistente } from './Asistente';

export default async function Importar() {
  const { sb } = await requireUser();
  const [{ data: fuentes }, { data: insts }, { data: lotes }] = await Promise.all([
    sb.from('fuentes').select('id, nombre, institucion_id, proposito_autorizado, instituciones(nombre)').order('nombre'),
    sb.from('instituciones').select('id, nombre').order('nombre'),
    sb.from('lotes_importacion').select('id, archivo_nombre, estado, tipo, fecha_datos, creado_en, resumen, fuentes(nombre)').order('creado_en', { ascending: false }).limit(30),
  ]);
  return (
    <>
      <h1>Importaciones</h1>
      <p className="sub">Solo archivos cuyo uso esté autorizado para este propósito. Nada se fusiona automáticamente.</p>
      <Asistente fuentes={(fuentes as any) ?? []} instituciones={insts ?? []} />
      <section className="panel tabla-wrap">
        <h2>Lotes recientes</h2>
        {!lotes?.length ? <p className="sin-dato">Todavía no hay importaciones.</p> : (
          <table><thead><tr><th>Archivo</th><th>Fuente</th><th>Datos al</th><th>Estado</th><th>Cargado</th></tr></thead>
            <tbody>{lotes.map((l: any) => (
              <tr key={l.id}><td><Link href={`/importar/${l.id}`}>{l.archivo_nombre}</Link>{l.tipo === 'matricula' && <span className="chip info"> matrícula</span>}</td>
                <td>{l.fuentes?.nombre}</td><td>{fecha(l.fecha_datos)}</td>
                <td><span className={`chip ${l.estado === 'confirmado' ? 'ok' : l.estado === 'revertido' ? 'danger' : 'warn'}`}>{l.estado}</span></td>
                <td className="sub">{fechaHora(l.creado_en)}</td></tr>))}</tbody></table>)}
      </section>
    </>
  );
}
