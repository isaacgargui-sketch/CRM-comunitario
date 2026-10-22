// Valores PÚBLICOS del proyecto Supabase (pensados para el navegador; la seguridad la dan los permisos de la base).
// Si las variables de entorno están cargadas, tienen prioridad. Nunca poner aquí la clave service_role/secret.
export const SUPABASE_URL =
  process.env.NEXT_PUBLIC_SUPABASE_URL?.trim() || 'https://tagvkkacmgoynywbhwne.supabase.co';
export const SUPABASE_KEY =
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim() || 'sb_publishable_weXcjI_6cUsSLCKNrvrpYQ_yY38ClOv';
