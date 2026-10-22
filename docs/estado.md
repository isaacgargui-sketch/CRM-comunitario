# Estado de la entrega

## Terminado
- **Base de datos completa de la Etapa 1** (6 migraciones): personas, contactos, domicilios, hogares, vínculos, instituciones, programas, participaciones, escolaridad, casos con recorrido por programa, interacciones, barreras, tareas, preferencias de contacto, fuentes, lotes, filas importadas, procedencia, discrepancias, candidatos a duplicado, fusiones, solicitudes de titulares, auditoría.
- **Seguridad en servidor**: RLS en todas las tablas, roles por institución y programa, privilegios por defecto de Supabase endurecidos, sin acceso anónimo.
- **Importación**: validación, normalización de teléfonos (Argentina), correos y fechas (incluye mes/año, solo año y número de serie de Excel), detección de duplicados sin fusión automática, revisión manual, reimportación sin duplicar, informe de errores, reversión de lotes.
- **Fusión auditable y reversible.**
- **Seguimiento**: casos, etapas, interacciones, barreras comunicadas, tareas con responsable y vencimiento, historial.
- **Protecciones**: bloqueo de contacto saliente ante pedido de no contacto; contacto con menores solo vía adultos responsables o autorizados; exportación ordinaria sin información restringida y con marca de no contacto.
- **Módulo rabínico** en la base, aislado (sin interfaz, a propósito).
- **Indicadores** con definición, período y denominador.
- **Interfaz** del primer circuito: inicio, personas, alta, ficha, importación (asistente y revisión), tablero Maimónides, caso, duplicados.

## Verificado
`tests/run.sh` aplica todo sobre una base limpia y comprueba:

| Criterio | Resultado |
|---|---|
| Alta con datos mínimos | ✔ |
| Importación incompleta (fila sin nombre al informe; fecha inválida queda sin dato) | ✔ |
| Reimportación sin duplicación (mismo archivo rechazado; filas repetidas se vinculan) | ✔ |
| Teléfono familiar compartido sin fusión ni candidato automático | ✔ |
| Conservación del historial escolar y regla “No encontrado en la matrícula importada de…” | ✔ |
| Fusión y reversión (los datos posteriores quedan en la ficha conservada) | ✔ |
| Reversión de lote que conserva fichas con datos verificados después | ✔ |
| Tarea sin responsable o sin vencimiento rechazada | ✔ |
| Restricciones efectivas en la API (programas ajenos, estadísticas, anónimo, TRUNCATE) | ✔ |
| Administración operativa sin acceso al módulo rabínico ni a otorgarse el rol | ✔ |
| Exportación sin información restringida y con no contactar | ✔ |
| Respeto de no contacto | ✔ |
| Contacto con menores solo vía adultos responsables | ✔ |
| Coherencia de indicadores con los registros | ✔ |

La interfaz compila (`next build` y `tsc` sin errores). **No se probó contra un proyecto Supabase real** desde este entorno: la primera puesta en marcha debe incluir un recorrido completo con los archivos de `plantillas/demo_*`.

## Limitaciones conocidas
- La detección de duplicados compara solo con fichas visibles para quien importa. Una persona cargada por otra institución sin alcance compartido puede duplicarse; se resuelve definiendo acuerdos de alcance entre instituciones.
- La normalización de teléfonos crea una clave de comparación, no un número para marcar; no distingue fijo de celular.
- `xlsx` 0.18.5 (npm) tiene avisos de seguridad conocidos. Antes de producción: `npm i https://cdn.sheetjs.com/xlsx-0.20.3/xlsx-0.20.3.tgz`. El riesgo actual es bajo porque solo se leen archivos de instituciones autorizadas, en el navegador.
- Next.js 14.2.35 es la última de su rama, pero `npm audit` aún informa avisos (denegación de servicio y otros) cuya corrección está en ramas nuevas. Planificar la migración a la versión estable vigente antes de abrir el sistema a más usuarios.
- Indicadores de “estadísticas” sin umbral mínimo de anonimato.

## Pendiente
**Etapa 1 (para cerrar):** pantallas de hogares, programas y usuarios (hoy se gestionan por SQL), vistas guardadas, agenda semanal, edición de datos básicos de la ficha, gestión de solicitudes de titulares en la interfaz, procedimiento de supresión/anonimización, política de conservación aplicada en la base.

**Etapa 2:** recorridos completos de participación comunitaria (actividades, asistencia, continuidad) y de adultos mayores en la interfaz; almacenamiento privado de archivos; umbral de anonimato en estadísticas.

**Etapa 3:** reportes avanzados e integraciones autorizadas (siempre respetando preferencias de contacto).

**Módulo rabínico:** interfaz y habilitación solo después de aplicar las medidas de `permisos.md` (proyecto separado y/o cifrado del lado del cliente). Hasta entonces, no cargar información.

## Decisiones institucionales y legales antes de usar datos reales
No se afirma cumplimiento legal automático. A validar con asesoría legal y las comisiones directivas:
1. **Autorización de uso** de cada archivo (quién la da, para qué propósito, qué instituciones lo comparten) y acta o constancia.
2. **Ley 25.326 de Protección de Datos Personales**: la pertenencia a una comunidad religiosa puede revelar convicciones religiosas, que la ley trata como datos sensibles; revisar la base legal del tratamiento, la información a las personas y la posible inscripción de la base ante la Agencia de Acceso a la Información Pública.
3. **Datos de menores**: criterio de consentimiento de adultos responsables.
4. **Transferencia internacional**: el alojamiento propuesto está en Brasil (Supabase) y servicios de EE. UU.; revisar requisitos y cláusulas contractuales.
5. **Política de conservación y eliminación** (plazos por tipo de dato) y procedimiento para acceso, rectificación y supresión.
6. **Quién administra la infraestructura** y quién designa a la autoridad rabínica en el sistema.
7. **Contratación** de los planes pagos (Supabase Pro, hosting) y titularidad de las cuentas a nombre de la institución.
