import Link from 'next/link';
import { requireUser } from '@/lib/supabase/server';
import { edad, SIN_DATO } from '@/lib/format';

export default async function Personas({ searchParams }: { searchParams: { q?: string; filtro?: string } }) {
  const { sb } = await requireUser();
  const { data, error } = await sb.rpc('buscar_personas', { q: searchParams.q || null, limite: 200 });
  let filas = (data as any[]) ?? [];
  if (searchParams.filtro === 'sin_contacto') filas = filas.filter((p) => !p.telefono && !p.email);
  if (searchParams.filtro === 'sin_fecha') filas = filas.filter((p) => !p.fecha_nacimiento);
  if (searchParams.filtro === 'no_contactar') filas = filas.filter((p) => p.no_contactar);

  return (
    <>
      <div className="fila" style={{ justifyContent: 'space-between' }}>
        <div><h1>Personas</h1><p className="sub">Fichas visibles según tus permisos. Buscá por nombre, apellido, teléfono o correo.</p></div>
        <Link className="boton" href="/personas/nueva">Agregar persona</Link>
      </div>
      <form className="fila panel">
        <div style={{ flex: 2 }}><label htmlFor="q">Buscar</label><input id="q" name="q" defaultValue={searchParams.q} style={{ width: '100%' }} /></div>
        <div><label htmlFor="filtro">Mostrar</label>
          <select id="filtro" name="filtro" defaultValue={searchParams.filtro ?? ''}>
            <option value="">Todas</option><option value="sin_contacto">Sin contacto cargado</option>
            <option value="sin_fecha">Sin fecha de nacimiento</option><option value="no_contactar">Pidieron no ser contactadas</option>
          </select></div>
        <button type="submit">Buscar</button>
      </form>
      {error && <div className="aviso danger">{error.message}</div>}
      <div className="panel tabla-wrap">
        <p className="sub">{filas.length} resultados{filas.length === 200 ? ' (se muestran los primeros 200; refiná la búsqueda)' : ''}</p>
        <table>
          <thead><tr><th>Nombre</th><th>Edad</th><th>Teléfono</th><th>Correo</th><th></th></tr></thead>
          <tbody>{filas.map((p) => (
            <tr key={p.id}>
              <td><Link href={`/personas/${p.id}`}>{p.apellidos ? `${p.apellidos}, ` : ''}{p.nombres}</Link>{p.nombre_preferido && <span className="sub"> ({p.nombre_preferido})</span>}</td>
              <td className={p.edad === null ? 'sin-dato' : ''}>{edad(p.edad, p.precision_fecha)}</td>
              <td className={!p.telefono ? 'sin-dato' : ''}>{p.telefono ?? SIN_DATO}</td>
              <td className={!p.email ? 'sin-dato' : ''}>{p.email ?? SIN_DATO}</td>
              <td>{p.no_contactar && <span className="chip danger">No contactar</span>}</td>
            </tr>))}</tbody>
        </table>
      </div>
    </>
  );
}
