import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { SUPABASE_KEY, SUPABASE_URL } from './lib/supabase/config';

// Renueva la sesión y redirige a /login si no hay usuario.
// El control de acceso real está en la base (RLS) y en cada página (requireUser):
// si este paso fallara, la página igual exige sesión, por eso nunca se deja caer la app.
export async function middleware(req: NextRequest) {
  let res = NextResponse.next({ request: req });
  try {
    const sb = createServerClient(SUPABASE_URL, SUPABASE_KEY, {
      cookies: {
        getAll: () => req.cookies.getAll(),
        setAll: (items: { name: string; value: string; options: CookieOptions }[]) => {
          items.forEach(({ name, value }) => req.cookies.set(name, value));
          res = NextResponse.next({ request: req });
          items.forEach(({ name, value, options }) => res.cookies.set(name, value, options));
        },
      },
    });
    const { data: { user } } = await sb.auth.getUser();
    if (!user && !req.nextUrl.pathname.startsWith('/login')) {
      return NextResponse.redirect(new URL('/login', req.url));
    }
  } catch (e) {
    console.error('middleware: no se pudo verificar la sesión', e instanceof Error ? e.message : 'error');
  }
  return res;
}

export const config = { matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'] };
