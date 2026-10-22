# CRM Comunitario Tucumán

Aplicación web para gestionar la relación de la Kehilá Sefaradí de Tucumán y el Colegio Maimónides con personas y familias: mapeo a partir de archivos autorizados, calidad de datos, seguimiento con responsables y fechas, e indicadores honestos.

Esta entrega contiene **la Etapa 1 funcional en su núcleo** (base de datos completa con seguridad en servidor + el primer circuito de punta a punta en la interfaz). No es una maqueta: los datos se guardan en PostgreSQL y los permisos se aplican en la base. Lo que falta está detallado en [`docs/estado.md`](docs/estado.md).

## Contenido

| Carpeta | Qué hay |
|---|---|
| `supabase/migrations/` | Esquema, permisos (RLS), lógica de importación/duplicados/fusiones, recorridos, módulo rabínico, indicadores |
| `supabase/seed.sql` | Instituciones, programas y fuentes **ficticias** para desarrollo |
| `tests/` | Pruebas de aceptación SQL de todos los criterios pedidos (`tests/run.sh`) |
| `app/` | Interfaz Next.js (español, adaptable a celular) |
| `plantillas/` | Plantillas de importación (Excel y CSV) y archivos de demostración ficticios |
| `docs/` | Arquitectura y modelo, matriz de permisos, guía operativa, estado y pendientes |

## Instalación

### 1. Base de datos (Supabase)
1. Crear un proyecto en [supabase.com](https://supabase.com), región **South America (São Paulo)**. Activar MFA en la cuenta de la organización.
2. Aplicar las migraciones **en orden**, con la CLI (`supabase link --project-ref …` y luego `supabase db push`) o pegando cada archivo de `supabase/migrations/` en el SQL Editor.
3. Solo en el entorno de demostración: ejecutar `supabase/seed.sql`.
4. En **Authentication → Providers**: dejar solo Email; en **Authentication → Settings** desactivar *Allow new users to sign up* (las cuentas las crea la administración).
5. En **Settings → API → Exposed schemas**: dejar `public` (no agregar `app` ni `rabinico`).

### 2. Usuarios y roles
Crear cada usuario en **Authentication → Users → Add user**. Luego, en el SQL Editor:

```sql
insert into usuarios (id, nombre, email)
select id, 'Nombre Apellido', email from auth.users where email = 'persona@ejemplo.org';

-- rol: admin_operativo | equipo_educativo | coordinacion_comunitaria | equipo_acompanamiento | estadisticas
insert into asignaciones_rol (usuario_id, rol, institucion_id)
select id, 'equipo_educativo', '22222222-2222-4222-8222-222222222222' from auth.users where email = 'persona@ejemplo.org';
```

El rol `autoridad_rabinica` **no** puede asignarlo la administración desde la aplicación; ver `docs/permisos.md`.

### 3. Aplicación
```bash
cd app
cp .env.example .env.local      # completar URL y clave anon del proyecto
npm ci
npm run dev                     # http://localhost:3000
```

### 4. Despliegue
Recomendado: Vercel (región `gru1`, São Paulo). Importar el repositorio con *Root directory* = `app` y cargar `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_ANON_KEY`. La aplicación **no usa** la clave `service_role`: no la cargues en ningún entorno de la app.

### 5. Pruebas
Con PostgreSQL 15+ local (incluye `unaccent` y `pg_trgm`):
```bash
./tests/run.sh       # crea una base limpia, aplica migraciones, seed y pruebas
```
Las pruebas usan `tests/auth_stub.sql`, que simula la autenticación de Supabase. **No ejecutar ese archivo en Supabase.**

## Copias de seguridad
- Supabase Pro hace copias diarias (retención según plan). La recuperación a un punto en el tiempo (PITR) es un complemento pago.
- Además, una copia propia semanal fuera del proveedor: `scripts/backup.sh` (pg_dump cifrado con GPG). Guardar la clave de cifrado separada de las copias.
- Probar una restauración en un proyecto de prueba al menos cada tres meses y dejar constancia.

## Costos y dependencias por confirmar
Precios de referencia a confirmar en cada sitio al contratar; pueden haber cambiado.

| Servicio | Uso | Referencia |
|---|---|---|
| Supabase Pro | Base, autenticación, copias diarias | ~US$ 25/mes por organización |
| Supabase PITR (opcional) | Restauración a un momento exacto | complemento pago adicional |
| Vercel Pro | Hosting de la app (el plan gratuito es para uso personal no comercial) | ~US$ 20/mes por miembro |
| Dominio | p. ej. `crm.kehila…` | costo anual del registrador |

El plan gratuito de Supabase sirve para la demo con datos ficticios, **no** para datos reales (sin copias de seguridad y con pausa por inactividad).

## Seguridad mínima antes de datos reales
Ver la lista de decisiones institucionales y requisitos legales en `docs/estado.md`. Este software **no** garantiza por sí mismo el cumplimiento de la Ley 25.326 ni de otra normativa.
