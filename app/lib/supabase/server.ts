import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';

export function supabaseServer() {
  const store = cookies();
  return createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
    cookies: {
      getAll: () => store.getAll(),
      setAll: (items: { name: string; value: string; options: CookieOptions }[]) => {
        try { items.forEach(({ name, value, options }) => store.set(name, value, options)); } catch { /* en Server Components no se escriben cookies */ }
      },
    },
  });
}

/** Devuelve cliente y usuario; redirige a /login si no hay sesión. */
export async function requireUser() {
  const sb = supabaseServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) redirect('/login');
  return { sb, user };
}
