import { redirect } from 'next/navigation';
import { supabaseServer } from '@/lib/supabase/server';

async function ingresar(form: FormData) {
  'use server';
  const sb = supabaseServer();
  const { error } = await sb.auth.signInWithPassword({
    email: String(form.get('email') ?? ''),
    password: String(form.get('password') ?? ''),
  });
  if (error) redirect('/login?error=1');
  redirect('/');
}

export default function Login({ searchParams }: { searchParams: { error?: string } }) {
  return (
    <main style={{ maxWidth: 380, margin: '10vh auto' }}>
      <h1>CRM Comunitario Tucumán</h1>
      <p className="sub">Acceso para equipos autorizados. Las cuentas las crea la administración.</p>
      {searchParams.error && <div className="aviso danger">Correo o contraseña incorrectos.</div>}
      <form action={ingresar} className="panel">
        <div className="campo"><label htmlFor="email">Correo</label><input id="email" name="email" type="email" required autoComplete="username" /></div>
        <div className="campo"><label htmlFor="password">Contraseña</label><input id="password" name="password" type="password" required autoComplete="current-password" /></div>
        <button type="submit">Ingresar</button>
      </form>
    </main>
  );
}
