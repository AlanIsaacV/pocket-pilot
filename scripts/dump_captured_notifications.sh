#!/usr/bin/env bash
# =============================================================================
# dump_captured_notifications.sh
#
# Extrae las notificaciones bancarias que el BankNotificationListenerService
# capturó en el device Android y las vuelca a un archivo JSON listo para usar
# como fixture de pruebas del ParserEngine.
#
# Pre-requisitos:
#   - adb en PATH y device conectado por USB con depuración activa.
#   - Build DEBUG de Pocket Pilot instalado (release no permite `run-as`).
#     applicationId del debug build: app.pocketpilot.debug
#
# Uso:
#   ./scripts/dump_captured_notifications.sh                    # default BBVA
#   ./scripts/dump_captured_notifications.sh com.bancomer.mbanking
#
# Output:
#   frontend/test_data/captured_raw.json         (shape exacto de la tabla)
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_FILTER="${1:-bancomer}"        # filtra package_name LIKE %arg%
APP_ID="app.pocketpilot.debug"
OUT="${REPO_ROOT}/frontend/test_data/captured_raw.json"
# Copia permanente (fuera del repo: contiene PII y sirve de backup ante
# pérdida de datos del device — ver postmortem 2026-07-18). Incluye -wal/-shm:
# con journal_mode=WAL los commits recientes viven en el sidecar, no en el .db.
BACKUP_DIR="${HOME}/.pocket_pilot/db_backups"
mkdir -p "$BACKUP_DIR"
TMP_DB="${BACKUP_DIR}/pocket_pilot-$(date +%Y%m%d-%H%M%S).db"

echo "→ Verificando device..."
adb shell echo ok > /dev/null

echo "→ Verificando que ${APP_ID} está instalado..."
if ! adb shell pm list packages | grep -q "${APP_ID}"; then
    echo "  ✘ ${APP_ID} no encontrado. Verifica con:"
    echo "    adb shell pm list packages | grep pocket"
    exit 1
fi

echo "→ Extrayendo pocket_pilot.db (+wal/shm) del data dir privado..."
adb shell "run-as ${APP_ID} cat databases/pocket_pilot.db" > "$TMP_DB"
adb shell "run-as ${APP_ID} cat databases/pocket_pilot.db-wal" > "${TMP_DB}-wal" 2>/dev/null || true
adb shell "run-as ${APP_ID} cat databases/pocket_pilot.db-shm" > "${TMP_DB}-shm" 2>/dev/null || true
echo "  (backup permanente: ${TMP_DB})"
DB_SIZE=$(stat -f%z "$TMP_DB" 2>/dev/null || stat -c%s "$TMP_DB")
if [ "$DB_SIZE" -lt 1024 ]; then
    echo "  ✘ DB extraída es sospechosamente pequeña (${DB_SIZE} bytes). ¿Es debug build?"
    exit 1
fi

echo "→ Volcando captured_notifications con package_name LIKE '%${PACKAGE_FILTER}%'..."
mkdir -p "$(dirname "$OUT")"

# json_group_array + json_object construyen un JSON array bien formado.
sqlite3 "$TMP_DB" "
SELECT json_group_array(
    json_object(
        'id',           id,
        'package_name', package_name,
        'title',        title,
        'text',         text,
        'big_text',     big_text,
        'posted_at',    posted_at,
        'status',       status
    )
)
FROM captured_notifications
WHERE package_name LIKE '%${PACKAGE_FILTER}%'
ORDER BY posted_at DESC;
" | python3 -m json.tool > "$OUT"

COUNT=$(python3 -c "import json; print(len(json.load(open('$OUT'))))")
echo "✓ Volcadas ${COUNT} notificaciones a:"
echo "  $OUT"
echo
echo "Siguiente paso: revisar el archivo, descartar duplicados/no-transaccionales"
echo "y mover los casos representativos a frontend/test_data/bbva_mx_real_notifications.json"
echo "con campos expected.{matched, pattern_id, transaction_type, fields} llenados a mano."
