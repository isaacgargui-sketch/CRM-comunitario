#!/usr/bin/env bash
# Aplica migraciones sobre una base limpia y corre las pruebas de aceptación.
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${DB:-crm_test}
PSQL="psql -v ON_ERROR_STOP=1 -q -X"
dropdb --if-exists "$DB"; createdb "$DB"
$PSQL -d "$DB" -f tests/auth_stub.sql
for f in supabase/migrations/*.sql; do echo "→ $f"; $PSQL -d "$DB" -f "$f"; done
$PSQL -d "$DB" -f supabase/seed.sql
$PSQL -d "$DB" -f tests/pruebas.sql
echo "✔ Todas las pruebas pasaron"
