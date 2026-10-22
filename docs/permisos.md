# Roles y permisos

Todos los permisos se aplican en PostgreSQL (Row Level Security y funciones con control explícito). La interfaz solo refleja lo que la base permite: llamar a la API directamente con un token de usuario da el mismo resultado.

Los roles se asignan **por institución** (y opcionalmente por programa). Una persona es visible para un usuario solo si la ficha tiene alcance en una institución donde ese usuario tiene un rol operativo.

## Matriz

| Acción | Admin. operativa | Equipo educativo | Coord. comunitaria | Acompañamiento | Autoridad rabínica | Estadísticas |
|---|---|---|---|---|---|---|
| Ver ficha básica, contactos, vínculos | ✔ | ✔ | ✔ | ✔ | ✔ (solo lectura) | ✘ |
| Editar ficha, contactos, vínculos, preferencias | ✔ | ✔ | ✔ | ✔ | ✘ | ✘ |
| Dar altas | ✔ | ✔ | ✔ | ✔ | ✘ | ✘ |
| Ver y cargar escolaridad | ✔ | ✔ | ✘ | ✘ | ✘ | ✘ |
| Importar archivos | ✔ | ✔ | ✘ | ✘ | ✘ | ✘ |
| Revertir lotes, fusionar, exportar fichas | ✔ | ✘ | ✘ | ✘ | ✘ | ✘ |
| Casos e interacciones del programa educativo | ✔ | ✔ | ✘ | ✘ | ✘ | ✘ |
| Casos e interacciones del programa comunitario | ✔ | ✘ | ✔ | ✘ | ✘ | ✘ |
| Casos e interacciones de adultos mayores | ✔ | ✘ | ✘ | ✔ | ✘ | ✘ |
| Indicadores agregados | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| Gestionar roles de su institución (salvo el rabínico) | ✔ | ✘ | ✘ | ✘ | ✘ | ✘ |
| Módulo rabínico | **✘** | ✘ | ✘ | ✘ | ✔ | ✘ |
| Ver auditoría (sin valores) | ✔ | ✘ | ✘ | ✘ | ✘ | ✘ |

Notas:
- Un caso de un programa al que no tenés acceso **no existe** para vos: no aparece en la ficha, la cronología ni los indicadores de detalle.
- Nadie puede borrar interacciones, casos ni historial desde la API; `TRUNCATE` está revocado.
- Un usuario desactivado (`usuarios.activo = false`) pierde todo acceso aunque conserve su sesión.
- Estadísticas ve solo agregados. **Pendiente:** umbral mínimo para no mostrar conteos muy bajos que permitan identificar personas.

## Módulo rabínico

**Qué hace la aplicación:** registra estado del procedimiento (sin revisión, pendiente, finalizado), autoridad, fecha, referencia documental y la conclusión **con el vocabulario que define la propia autoridad**. No calcula, sugiere ni infiere nada. “Sin revisión” y “pendiente” no implican conclusión.

**Aislamiento implementado:**
- Esquema separado `rabinico`, no expuesto en la API pública hasta habilitarlo.
- Políticas que solo admiten el rol `autoridad_rabinica`. La administración operativa **no** tiene acceso funcional.
- La administración no puede otorgar ese rol (ni a sí misma): la política de `asignaciones_rol` lo impide.
- Ninguna búsqueda, tablero, indicador, notificación ni exportación ordinaria consulta ese esquema (verificado en las pruebas).
- Auditoría propia del módulo.

**Límite que hay que conocer:** quien administra la infraestructura (dueños del proyecto en Supabase, la conexión `postgres` y la clave `service_role`) puede leer cualquier tabla, incluido este módulo, porque esos accesos ignoran RLS. También las copias de seguridad completas lo contienen. Ningún sistema puede impedirle eso a quien controla el servidor.

**Medidas adicionales disponibles (recomendadas antes de habilitar el módulo):**
1. **Proyecto separado** para el módulo rabínico, cuya cuenta de administración pertenezca solo a quien designe la autoridad rabínica. Es la medida más clara.
2. **Cifrado del lado del cliente** de conclusión y referencia, con una clave que custodia la autoridad: la base solo guarda texto cifrado.
3. Cuentas de infraestructura nominativas con MFA, mínimo número de personas, y regla de dos personas para asignar el rol.
4. No cargar documentos: solo referencias a dónde los guarda la autoridad.
5. Excluir el esquema `rabinico` de las copias generales (o cifrarlas con una clave separada).

Procedimiento sugerido para asignar el rol (lo ejecuta infraestructura, con constancia escrita de la autoridad):
```sql
insert into asignaciones_rol (usuario_id, rol, institucion_id)
select id, 'autoridad_rabinica', '<id Kehilá>' from auth.users where email = '<correo>';
```
