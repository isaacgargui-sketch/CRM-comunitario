import { redirect } from 'next/navigation';
import { requireUser } from '@/lib/supabase/server';

async function crear(form: FormData) {
  'use server';
  const { sb } = await requireUser();
  const [inst, fuente] = String(form.get('fuente')).split('|');
  const { data, error } = await sb.rpc('crear_persona', {
    p_institucion: inst, p_fuente: fuente, p_nombres: String(form.get('nombres') ?? ''),
    p_apellidos: String(form.get('apellidos') ?? '') || null, p_nombre_preferido: String(form.get('preferido') ?? '') || null,
    p_fecha: String(form.get('fecha') ?? '') || null,
  });
  if (error) redirect(`/personas/nueva?error=${encodeURIComponent(error.message)}`);
  redirect(`/personas/${data}`);
}

export default async function Nueva({ searchParams }: { searchParams: { error?: string } }) {
  const { sb } = await requireUser();
  const { data: fuentes } = await sb.from('fuentes').select('id, nombre, institucion_id, instituciones(nombre)').order('nombre');
  return (
    <>
      <h1>Agregar persona</h1>
      <p className="sub">Solo el nombre es obligatorio. Lo que no sepas, dejalo vacío: se mostrará como “sin dato”.</p>
      {searchParams.error && <div className="aviso danger">{searchParams.error}</div>}
      <form action={crear} className="panel" style={{ maxWidth: 560 }}>
        <div className="campo"><label htmlFor="fuente">Origen del dato</label>
          <select id="fuente" name="fuente" required>
            {fuentes?.map((f: any) => <option key={f.id} value={`${f.institucion_id}|${f.id}`}>{f.instituciones?.nombre} · {f.nombre}</option>)}
          </select></div>
        <div className="campo"><label htmlFor="nombres">Nombres</label><input id="nombres" name="nombres" required /></div>
        <div className="campo"><label htmlFor="apellidos">Apellidos</label><input id="apellidos" name="apellidos" /></div>
        <div className="campo"><label htmlFor="preferido">Nombre preferido</label><input id="preferido" name="preferido" /></div>
        <div className="campo"><label htmlFor="fecha">Fecha de nacimiento (dd/mm/aaaa, mm/aaaa o aaaa)</label><input id="fecha" name="fecha" /></div>
        <button type="submit">Guardar ficha</button>
      </form>
    </>
  );
}
