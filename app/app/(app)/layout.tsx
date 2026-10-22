import Link from 'next/link';
import { redirect } from 'next/navigation';
import { requireUser, supabaseServer } from '@/lib/supabase/server';

async function salir() {
  'use server';
  await supabaseServer().auth.signOut();
  redirect('/login');
}

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const { sb, user } = await requireUser();
  const { data: yo } = await sb.from('usuarios').select('nombre').eq('id', user.id).maybeSingle();
  return (
    <div className="shell">
      <nav className="nav" aria-label="Principal">
        <div className="marca">CRM Comunitario<small>{yo?.nombre ?? user.email}</small></div>
        <Link href="/">Inicio</Link>
        <Link href="/personas">Personas</Link>
        <Link href="/maimonides">Piloto Maimónides</Link>
        <div className="grupo">Calidad de datos</div>
        <Link href="/importar">Importaciones</Link>
        <Link href="/duplicados">Duplicados</Link>
        <form action={salir} style={{ marginTop: '1rem' }}><button className="secundario" type="submit">Salir</button></form>
      </nav>
      <main>{children}</main>
    </div>
  );
}
