#!/usr/bin/env bash
set -Eeuo pipefail

MALVA_BASE_URL="${MALVA_BASE_URL:-http://127.0.0.1:8080}"
MALVA_VALIDATE_MUTATING="${MALVA_VALIDATE_MUTATING:-0}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

check_header() {
  local headers="$1"
  local name="$2"
  local expected="$3"
  if ! printf "%s" "$headers" | grep -qi "^${name}: ${expected}"; then
    echo "Missing or invalid security header: ${name}: ${expected}" >&2
    exit 1
  fi
}

require_command curl
require_command grep

echo "Checking health: ${MALVA_BASE_URL}/healthz"
curl -fsS "${MALVA_BASE_URL}/healthz" | grep -q '"status":"ok"'

echo "Checking security headers"
headers="$(curl -fsSI "${MALVA_BASE_URL}/")"
check_header "$headers" "X-Content-Type-Options" "nosniff"
check_header "$headers" "X-Frame-Options" "DENY"
check_header "$headers" "Referrer-Policy" "no-referrer"

if [[ "${MALVA_BASE_URL}" == https://* ]]; then
  echo "HTTPS base URL detected."
else
  echo "Warning: base URL is not HTTPS. This is acceptable only for local/dev validation." >&2
fi

if [[ "$MALVA_VALIDATE_MUTATING" != "1" ]]; then
  echo "Non-mutating validation passed."
  echo "Set MALVA_VALIDATE_MUTATING=1 to run register/login/screening smoke test."
  exit 0
fi

require_command sed

timestamp="$(date +%s)"
email="smoke+${timestamp}@malva.local"
professional_email="smoke-professional+${timestamp}@malva.local"
professional_id="${timestamp}000000"
password="MalvaSmoke123!"

echo "Running mutating API smoke test with ${email}"
auth_response="$(
  curl -fsS -X POST "${MALVA_BASE_URL}/v1/auth/register" \
    -H "Content-Type: application/json" \
    -d "{\"role\":\"patient\",\"email\":\"${email}\",\"password\":\"${password}\",\"display_name\":\"Smoke Test\"}"
)"

token="$(printf "%s" "$auth_response" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"
refresh_token="$(printf "%s" "$auth_response" | sed -n 's/.*"refresh_token":"\([^"]*\)".*/\1/p')"
patient_user_id="$(printf "%s" "$auth_response" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
if [[ -z "$token" ]]; then
  echo "Could not extract access token from register response." >&2
  exit 1
fi
if [[ -z "$refresh_token" ]]; then
  echo "Could not extract refresh token from register response." >&2
  exit 1
fi
if [[ -z "$patient_user_id" ]]; then
  echo "Could not extract patient user id from register response." >&2
  exit 1
fi

refresh_response="$(
  curl -fsS -X POST "${MALVA_BASE_URL}/v1/auth/refresh" \
    -H "Content-Type: application/json" \
    -d "{\"refresh_token\":\"${refresh_token}\"}"
)"
token="$(printf "%s" "$refresh_response" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"
refresh_token="$(printf "%s" "$refresh_response" | sed -n 's/.*"refresh_token":"\([^"]*\)".*/\1/p')"
if [[ -z "$token" || -z "$refresh_token" ]]; then
  echo "Refresh token smoke test failed." >&2
  exit 1
fi

professional_auth_response="$(
  curl -fsS -X POST "${MALVA_BASE_URL}/v1/auth/register" \
    -H "Content-Type: application/json" \
    -d "{\"role\":\"professional\",\"email\":\"${professional_email}\",\"password\":\"${password}\",\"display_name\":\"Smoke Professional\",\"professional_id\":\"${professional_id}\"}"
)"
professional_token="$(printf "%s" "$professional_auth_response" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"
professional_refresh_token="$(printf "%s" "$professional_auth_response" | sed -n 's/.*"refresh_token":"\([^"]*\)".*/\1/p')"
if [[ -z "$professional_token" || -z "$professional_refresh_token" ]]; then
  echo "Could not extract professional tokens from register response." >&2
  exit 1
fi

curl -fsS -X POST "${MALVA_BASE_URL}/v1/patient-professional-links" \
  -H "Authorization: Bearer ${token}" \
  -H "Content-Type: application/json" \
  -d "{\"professional_id\":\"${professional_id}\"}" \
  | grep -q '"link"'

screening_response="$(
  curl -fsS -X POST "${MALVA_BASE_URL}/v1/screenings" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d '{"source":"production_smoke_test","is_initial":true,"phq9":[0,1,1,0,1,0,0,0,0],"gad7":[0,1,1,0,1,0,0]}'
)"
printf "%s" "$screening_response" | grep -q '"screening"'
screening_id="$(printf "%s" "$screening_response" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
if [[ -z "$screening_id" ]]; then
  echo "Could not extract screening id from screening response." >&2
  exit 1
fi

curl -fsS "${MALVA_BASE_URL}/v1/screenings?limit=5" \
  -H "Authorization: Bearer ${token}" \
  | grep -q '"screenings"'

curl -fsS "${MALVA_BASE_URL}/v1/patient-professional-links" \
  -H "Authorization: Bearer ${token}" \
  | grep -q "${professional_id}"

curl -fsS "${MALVA_BASE_URL}/v1/screenings?patient_id=${patient_user_id}&limit=5" \
  -H "Authorization: Bearer ${professional_token}" \
  | grep -q '"screenings"'

curl -fsS -X POST "${MALVA_BASE_URL}/v1/screenings/${screening_id}/review" \
  -H "Authorization: Bearer ${professional_token}" \
  -H "Content-Type: application/json" \
  -d '{"status":"reviewed","note":"Smoke test review"}' \
  | grep -q '"review"'

curl -fsS -X POST "${MALVA_BASE_URL}/v1/professional-notes" \
  -H "Authorization: Bearer ${professional_token}" \
  -H "Content-Type: application/json" \
  -d "{\"patient_id\":\"${patient_user_id}\",\"body\":\"Smoke clinical note\",\"visibility\":\"private\"}" \
  | grep -q '"note"'

curl -fsS -X POST "${MALVA_BASE_URL}/v1/follow-ups" \
  -H "Authorization: Bearer ${professional_token}" \
  -H "Content-Type: application/json" \
  -d "{\"patient_id\":\"${patient_user_id}\",\"body\":\"Smoke follow-up message\",\"status\":\"sent\"}" \
  | grep -q '"follow_up"'

curl -fsS "${MALVA_BASE_URL}/v1/follow-ups?limit=5" \
  -H "Authorization: Bearer ${token}" \
  | grep -q 'Smoke follow-up message'

curl -fsS -X POST "${MALVA_BASE_URL}/v1/mood-checkins" \
  -H "Authorization: Bearer ${token}" \
  -H "Content-Type: application/json" \
  -d '{"mood":"okay","sleep_hours":7.0,"energy":6,"anxiety":3,"irritability":2,"note":"Smoke mood"}' \
  | grep -q '"mood"'

curl -fsS -X POST "${MALVA_BASE_URL}/v1/diary-entries" \
  -H "Authorization: Bearer ${token}" \
  -H "Content-Type: application/json" \
  -d '{"mood":"good","title":"Smoke diary","note":"Smoke diary note","shared_with_professionals":true}' \
  | grep -q '"diary"'

curl -fsS -X POST "${MALVA_BASE_URL}/v1/medications" \
  -H "Authorization: Bearer ${token}" \
  -H "Content-Type: application/json" \
  -d '{"name":"Smoke Medication","dosage":"10 mg","form":"Tablet","reminder_time":"08:00","relation_to_meal":"Setelah makan","current_stock":10,"alert_below":2,"source":"Smoke"}' \
  | grep -q '"medication"'

curl -fsS -X POST "${MALVA_BASE_URL}/v1/medication-logs" \
  -H "Authorization: Bearer ${token}" \
  -H "Content-Type: application/json" \
  -d '{"medication_name":"Smoke Medication","status":"taken"}' \
  | grep -q '"medication_log"'

curl -fsS "${MALVA_BASE_URL}/v1/timeline?patient_id=${patient_user_id}&limit=10" \
  -H "Authorization: Bearer ${professional_token}" \
  | grep -q '"events"'

curl -fsS "${MALVA_BASE_URL}/v1/audit-logs?patient_id=${patient_user_id}&limit=10" \
  -H "Authorization: Bearer ${professional_token}" \
  | grep -q '"audit_logs"'

curl -fsS -X POST "${MALVA_BASE_URL}/v1/auth/logout" \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"${refresh_token}\"}" \
  | grep -q '"logged_out"'

curl -fsS -X POST "${MALVA_BASE_URL}/v1/auth/logout" \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"${professional_refresh_token}\"}" \
  | grep -q '"logged_out"'

echo "Mutating production smoke test passed."
