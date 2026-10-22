#!/usr/bin/env bash
# Copia de seguridad propia, cifrada, fuera del proveedor.
# Uso: SUPABASE_DB_URL="postgresql://..." GPG_RECIPIENT="backup@institucion" ./scripts/backup.sh /ruta/destino
# La URL de conexión se obtiene en Supabase → Settings → Database. No la guardes en el repositorio.
set -euo pipefail
DEST=${1:?Indicá la carpeta de destino}
: "${SUPABASE_DB_URL:?Falta SUPABASE_DB_URL}"
: "${GPG_RECIPIENT:?Falta GPG_RECIPIENT}"
STAMP=$(date +%Y%m%d-%H%M)
pg_dump "$SUPABASE_DB_URL" --format=custom --no-owner --schema=public --schema=rabinico --schema=app \
  | gpg --encrypt --recipient "$GPG_RECIPIENT" --output "$DEST/crm-$STAMP.dump.gpg"
echo "Copia creada: $DEST/crm-$STAMP.dump.gpg"
# Restaurar (en un proyecto de prueba): gpg -d archivo.dump.gpg | pg_restore --no-owner -d "$URL_PRUEBA"
