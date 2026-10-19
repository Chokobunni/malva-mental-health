#!/usr/bin/env bash
# ============================================================
# Malva — refresh status.json untuk halaman /status.html
# ============================================================
# Halaman status di website bersifat statis, sedangkan healthz berada di
# origin lain (api.malva.web.id) sehingga TIDAK bisa di-fetch langsung oleh
# browser bila CORS belum mengizinkan origin website. Karena itu backend
# memeriksa API dari sisi server lalu menulis potretan (snapshot) ke berkas
# JSON yang di-serve dari origin yang sama dengan website.
#
# Pakai:
#   ./status_snapshot.sh                      # tulis ke /var/www/malva/status.json
#   ./status_snapshot.sh ./status.json        # path lain
#   MALVA_API_URL=http://127.0.0.1:8080 ./status_snapshot.sh
#
# Jalankan berkala, misalnya setiap 1 menit:
#   * * * * * /opt/malva/app/backend/deploy/scripts/status_snapshot.sh
# ============================================================
set -euo pipefail

API_URL="${MALVA_API_URL:-https://api.malva.web.id}"
# Urutan prioritas: argumen pertama, lalu env STATUS_JSON_PATH, lalu default VM.
OUT="${1:-${STATUS_JSON_PATH:-/var/www/malva/status.json}}"
OUT_DIR="$(cd "$(dirname "$OUT")" && pwd)"
OUT_NAME="$(basename "$OUT")"
OUT="$OUT_DIR/$OUT_NAME"

CHECKED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

START_MS="$(date +%s%3N)"
HTTP_CODE="$(curl -s -S -o "$BODY_FILE" -w '%{http_code}' --max-time 15 "$API_URL/healthz" || echo 000)"
END_MS="$(date +%s%3N)"
LATENCY_MS=$((END_MS - START_MS))

API_STATUS="down"
if [ "$HTTP_CODE" = "200" ]; then
  # Body sehat: {"status":"ok"} — hanya status "ok" yang dianggap operasional.
  if grep -q '"status"[[:space:]]*:[[:space:]]*"ok"' "$BODY_FILE"; then
    API_STATUS="operational"
  else
    API_STATUS="degraded"
  fi
elif [ "$HTTP_CODE" = "000" ]; then
  API_STATUS="down"
else
  API_STATUS="degraded"
fi

# Tulis atomik agar pembaca tidak pernah melihat setengah file.
TMP_OUT="$(mktemp "$OUT_DIR/status.XXXXXX.json")"
trap 'rm -f "$BODY_FILE" "$TMP_OUT"' EXIT
cat > "$TMP_OUT" <<JSON
{
  "checked_at": "$CHECKED_AT",
  "api_status": "$API_STATUS",
  "api_http_code": "$HTTP_CODE",
  "api_latency_ms": $LATENCY_MS,
  "components": {
    "api": "$API_STATUS",
    "website": "operational",
    "database": "not_probed"
  },
  "source": "$API_URL/healthz"
}
JSON
mv "$TMP_OUT" "$OUT"

echo "status.json diperbarui -> $OUT ($API_STATUS, ${HTTP_CODE}, ${LATENCY_MS}ms)"
