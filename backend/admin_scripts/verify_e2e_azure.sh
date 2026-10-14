#!/usr/bin/env bash
#
# verify_e2e_azure.sh — Verifikasi end-to-end backend Malva di Azure VM.
#
# Dirancang untuk dijalankan DI DALAM VM. Read-only, kecuali satu uji tulis
# (toggle `is_active` satu baris jadwal) yang WAJIB dikembalikan ke nilai asli.
# Skrip tidak pernah menjalankan DELETE.
#
# Contoh pemakaian:
#   ssh -i ~/.ssh/malva_azure malva@api.malva.web.id \
#     'MALVA_TEST_PRO_IDENTIFIER=STR-1234567890123456 \
#      MALVA_TEST_PRO_PASSWORD=<password-demo> bash -s' \
#     < backend/admin_scripts/verify_e2e_azure.sh
#
# Bagian:
#   A. Skema       — keberadaan tabel/kolom fitur baru (migrasi 013 + 012).
#   B. Snapshot    — hitungan data (read-only).
#   C. Routing API — /healthz 200; endpoint ber-auth harus 401 (404 = route hilang).
#   D. Alur pro    — login, cek is_active, toggle satu baris jadwal, restore.
#   E. Ringkasan   — PASS/FAIL/SKIP; exit non-zero bila ada FAIL.
#
# Konfigurasi (env var):
#   MALVA_DATABASE_URL        URL DB. Bila kosong -> source /etc/malva/malva-api.env
#   MALVA_API_BASE            default http://127.0.0.1:8080
#   MALVA_TEST_PRO_IDENTIFIER identitas profesional (STR/SIP/kode profesi)
#   MALVA_TEST_PRO_PASSWORD   password profesional (TIDAK di-hardcode di file ini)
#
# Catatan: sengaja TIDAK memakai `set -e` agar satu kegagalan tidak
# menghentikan seluruh run.

set -uo pipefail

# ---------------------------------------------------------------- konfigurasi
API_BASE="${MALVA_API_BASE:-http://127.0.0.1:8080}"
API_BASE="${API_BASE%/}"
DB_URL="${MALVA_DATABASE_URL:-}"
PRO_IDENTIFIER="${MALVA_TEST_PRO_IDENTIFIER:-}"
PRO_PASSWORD="${MALVA_TEST_PRO_PASSWORD:-}"
CURL_MAX_TIME=15

# ---------------------------------------------------------------- penghitung
PASS=0
FAIL=0
SKIP=0
FAIL_MSGS=()

c_green=''; c_red=''; c_yellow=''; c_reset=''
if [[ -t 1 ]]; then
  c_green=$'\033[32m'; c_red=$'\033[31m'; c_yellow=$'\033[33m'; c_reset=$'\033[0m'
fi

ok()      { PASS=$((PASS + 1)); printf '%s[OK]%s   %s\n'   "$c_green"  "$c_reset" "$*"; }
fail()    { FAIL=$((FAIL + 1)); FAIL_MSGS+=("$*"); printf '%s[FAIL]%s %s\n' "$c_red" "$c_reset" "$*"; }
skip()    { SKIP=$((SKIP + 1)); printf '%s[SKIP]%s %s\n'   "$c_yellow" "$c_reset" "$*"; }
info()    { printf '         %s\n' "$*"; }
section() { printf '\n==== %s ====\n' "$*"; }
have()    { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- util HTTP
# Semua panggilan API mem-bypass proxy (API default = 127.0.0.1 di VM).
CURL_OPTS=(--noproxy '*' --max-time "$CURL_MAX_TIME")

http_code() { # $@ = arg curl (tanpa url). Cetak kode HTTP; 000 bila gagal.
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' "${CURL_OPTS[@]}" "$@" 2>/dev/null)
  printf '%s' "${code:-000}"
}

LAST_CODE=""
LAST_BODY=""
api_request() { # $1=method $2=url ; sisa = arg curl. Set LAST_CODE & LAST_BODY.
  local method="$1" url="$2"; shift 2
  local tf; tf=$(mktemp)
  LAST_CODE=$(curl -s -o "$tf" -w '%{http_code}' "${CURL_OPTS[@]}" \
    -X "$method" "$@" "$url" 2>/dev/null)
  LAST_CODE="${LAST_CODE:-000}"
  LAST_BODY=$(<"$tf")
  rm -f "$tf"
}

# ---------------------------------------------------------------- util DB
if [[ -z "$DB_URL" && -f /etc/malva/malva-api.env ]]; then
  # Muat DB URL dari file env API. `set +u` karena file dapat mereferensikan
  # variabel lain yang belum tentu diset.
  set +u
  # shellcheck disable=SC1091
  source /etc/malva/malva-api.env
  set -u
  DB_URL="${MALVA_DATABASE_URL:-}"
fi

PSQL=""
have psql && PSQL="psql"
DB_READY=0
[[ -n "$PSQL" && -n "$DB_URL" ]] && DB_READY=1

db_scalar() { # $1 = SQL -> nilai tunggal (boleh kosong)
  [[ "$DB_READY" == "1" ]] || return 1
  "$PSQL" "$DB_URL" -X -A -t -q -P pager=off -c "$1" 2>/dev/null
}

db_block() { # $1 = SQL -> keluaran multi-baris (boleh kosong)
  [[ "$DB_READY" == "1" ]] || return 1
  "$PSQL" "$DB_URL" -X -A -t -q -P pager=off -c "$1" 2>/dev/null
}

# ---------------------------------------------------------------- trap restore
# Jadwal yang diubah di bagian D WAJIB dikembalikan walau gagal di tengah.
TOKEN=""
RESTORE_BODY=""
NEED_RESTORE=0

restore_schedules() {
  if [[ "$NEED_RESTORE" == "1" && -n "$RESTORE_BODY" && -n "$TOKEN" ]]; then
    printf '\n%s[INFO]%s Mengembalikan jadwal profesional ke nilai asli (trap)...\n' \
      "$c_yellow" "$c_reset"
    curl -s -o /dev/null "${CURL_OPTS[@]}" -X PUT \
      "$API_BASE/v1/professional/schedules" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' \
      -d "$RESTORE_BODY" 2>/dev/null
  fi
}
trap restore_schedules EXIT
trap 'restore_schedules; exit 130' INT TERM

# ---------------------------------------------------------------- banner
db_target="(tidak diset)"
if [[ -n "$DB_URL" ]]; then
  db_target=$(printf '%s' "$DB_URL" | sed -E 's#^[^@]*@##')
fi
cred_state="tidak diset"
[[ -n "$PRO_IDENTIFIER" && -n "$PRO_PASSWORD" ]] && cred_state="diset"

printf '########################################################\n'
printf '# Verifikasi E2E backend Malva — Azure VM\n'
printf '# API base   : %s\n' "$API_BASE"
printf '# DB target  : %s\n' "$db_target"
printf '# psql       : %s\n' "${PSQL:-TIDAK ADA}"
printf '# kredensial : %s\n' "$cred_state"
printf '# waktu      : %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf '########################################################\n'

# ================================================================ A. SKEMA
section "A. Skema (keberadaan tabel/kolom fitur baru)"

if [[ "$DB_READY" != "1" ]]; then
  skip "A: tidak bisa cek skema (psql/DB URL tidak tersedia)"
else
  check_table() { # $1 = nama tabel
    local name="$1" v
    v=$(db_scalar "SELECT to_regclass('public.$name') IS NOT NULL")
    if [[ "$v" == "t" ]]; then ok "A: tabel $name ada"
    else fail "A: tabel $name HILANG"; fi
  }
  check_column() { # $1 = tabel, $2 = kolom
    local table="$1" col="$2" v
    v=$(db_scalar "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='$table' AND column_name='$col')")
    if [[ "$v" == "t" ]]; then ok "A: kolom $table.$col ada"
    else fail "A: kolom $table.$col HILANG"; fi
  }

  check_table  "care_refunds"
  check_table  "payment_events"
  check_column "care_packages"          "refunded_amount"
  check_column "care_sessions"          "cancelled_by"
  check_column "professional_schedules" "is_active"
  check_column "payments"               "gateway"
  check_column "payments"               "snap_token"
  check_column "payments"               "redirect_url"
  info "(kolom payments.* adalah langkah 5 migrasi 013 — wajib dijalankan sebagai role admin 'malva')"
fi

# ================================================================ B. SNAPSHOT
section "B. Snapshot data (read-only)"

if [[ "$DB_READY" != "1" ]]; then
  skip "B: tidak bisa ambil snapshot (psql/DB URL tidak tersedia)"
else
  snapshot() { # $1 = label, $2 = SQL
    local label="$1" sql="$2" out
    out=$(db_block "$sql")
    if [[ -z "$out" ]]; then
      skip "B: $label (tidak ada hasil / tabel tidak ada)"
    else
      ok "B: $label"
      while IFS= read -r line; do info "$line"; done <<<"$out"
    fi
  }
  snapshot "user per role"        "SELECT role::text, COUNT(*) FROM users GROUP BY role ORDER BY role"
  snapshot "jadwal aktif/nonaktif" "SELECT is_active, COUNT(*) FROM professional_schedules GROUP BY is_active ORDER BY is_active"
  snapshot "jumlah paket (care_packages)" "SELECT COUNT(*) FROM care_packages"
  snapshot "jumlah payments"      "SELECT COUNT(*) FROM payments"
  if [[ "$(db_scalar "SELECT to_regclass('public.care_refunds') IS NOT NULL")" == "t" ]]; then
    snapshot "jumlah care_refunds" "SELECT COUNT(*) FROM care_refunds"
  fi
  if [[ "$(db_scalar "SELECT to_regclass('public.payment_events') IS NOT NULL")" == "t" ]]; then
    snapshot "jumlah payment_events" "SELECT COUNT(*) FROM payment_events"
  fi
fi

# ================================================================ C. ROUTING API
section "C. Routing API (tanpa auth)"

if ! have curl; then
  skip "C: curl tidak tersedia — bagian C & D dilewati"
else
  code=$(http_code "$API_BASE/healthz")
  if [[ "$code" == "200" ]]; then ok "C: GET /healthz -> 200"
  else fail "C: GET /healthz -> $code (harap 200; API tidak siap?)"; fi

  expect_401() { # $1 = path, $2 = label
    local path="$1" label="$2" code
    code=$(http_code "$API_BASE$path")
    if [[ "$code" == "401" ]]; then ok "C: GET $path -> 401 (route terdaftar, auth ditegakkan)"
    elif [[ "$code" == "404" ]]; then fail "C: GET $path -> 404 (route HILANG)"
    elif [[ "$code" == "200" ]]; then
      fail "C: GET $path -> 200 (route tidak terproteksi / fallthrough ke handler root)"
    else fail "C: GET $path -> $code (harap 401)"; fi
  }
  expect_401 "/v1/care-refunds"   "refund list"
  expect_401 "/v1/care-packages"  "care packages"
fi

# ================================================================ D. ALUR PRO
section "D. Alur terautentikasi profesional"

if [[ -z "$PRO_IDENTIFIER" || -z "$PRO_PASSWORD" ]]; then
  skip "D: kredensial tidak diset (MALVA_TEST_PRO_IDENTIFIER/MALVA_TEST_PRO_PASSWORD) — bagian D dilewati"
elif ! have curl; then
  skip "D: curl tidak tersedia"
elif ! have python3; then
  skip "D: python3 tidak tersedia (dibutuhkan untuk parsing JSON)"
else
  PY_HELPER=$(mktemp)
  cat > "$PY_HELPER" <<'PYEOF'
import sys, json

def proj(r, active):
    st = (r.get("start_time") or "")
    en = (r.get("end_time") or "")
    return {
        "day_of_week": r.get("day_of_week"),
        "start_time": st[:5],
        "end_time": en[:5],
        "slot_duration_minutes": r.get("slot_duration_minutes") or 30,
        "is_active": bool(active),
    }

mode = sys.argv[1] if len(sys.argv) > 1 else "probe"
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
rows = d.get("schedules") or []
missing = sum(1 for r in rows if "is_active" not in r)

if mode == "probe":
    if rows:
        r = rows[0]
        print("\t".join([
            str(len(rows)), str(missing), str(r.get("day_of_week")),
            (r.get("start_time") or "")[:5], (r.get("end_time") or "")[:5],
            "true" if r.get("is_active") else "false",
        ]))
    else:
        print("\t".join([str(len(rows)), str(missing), "", "", "", ""]))
elif mode == "state":
    for r in rows:
        print("%s|%s|%s|%s" % (r.get("day_of_week"),
                               (r.get("start_time") or "")[:5],
                               (r.get("end_time") or "")[:5],
                               "true" if r.get("is_active") else "false"))
elif mode == "firststate":
    print(("true" if rows[0].get("is_active") else "false") if rows else "none")
elif mode == "toggle":
    out = [proj(r, (not r.get("is_active")) if i == 0 else r.get("is_active"))
           for i, r in enumerate(rows)]
    print(json.dumps({"schedules": out}))
elif mode == "restore":
    print(json.dumps({"schedules": [proj(r, r.get("is_active")) for r in rows]}))
PYEOF

  # --- D.1 login
  login_body=$(MALVA_ID="$PRO_IDENTIFIER" MALVA_PW="$PRO_PASSWORD" python3 -c '
import json, os
print(json.dumps({"professional_identifier": os.environ["MALVA_ID"],
                  "password": os.environ["MALVA_PW"]}))')
  api_request POST "$API_BASE/v1/auth/login" -H 'Content-Type: application/json' -d "$login_body"
  if [[ "$LAST_CODE" != "200" ]]; then
    fail "D: login profesional gagal -> HTTP $LAST_CODE"
    info "respons: ${LAST_BODY:0:200}"
  else
    TOKEN=$(printf '%s' "$LAST_BODY" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("access_token","") or "")
except Exception: print("")')
    if [[ -z "$TOKEN" ]]; then
      fail "D: login 200 tetapi access_token tidak ada di respons"
    else
      ok "D: login profesional berhasil (access_token diterima)"

      # --- D.2 GET jadwal & cek is_active
      api_request GET "$API_BASE/v1/professional/schedules" -H "Authorization: Bearer $TOKEN"
      sched_code="$LAST_CODE"
      sched_json="$LAST_BODY"
      if [[ "$sched_code" != "200" ]]; then
        fail "D: GET /v1/professional/schedules -> HTTP $sched_code (harap 200)"
      else
        probe=$(printf '%s' "$sched_json" | python3 "$PY_HELPER" probe 2>/dev/null)
        IFS=$'\t' read -r sc_count sc_missing f_day f_start f_end f_active <<<"$probe"
        if [[ -z "${sc_count:-}" ]]; then
          fail "D: respons jadwal bukan JSON valid"
        else
          if [[ "$sc_missing" == "0" ]]; then
            ok "D: setiap baris jadwal mengekspos is_active (baris=$sc_count)"
          else
            fail "D: $sc_missing baris jadwal TIDAK mengekspos is_active (total=$sc_count)"
          fi
        fi

        # --- D.3 toggle satu baris, cek persist, lalu restore
        if [[ "${sc_count:-0}" -ge 1 ]]; then
          state_before=$(printf '%s' "$sched_json" | python3 "$PY_HELPER" state 2>/dev/null)
          toggle_body=$(printf '%s' "$sched_json" | python3 "$PY_HELPER" toggle 2>/dev/null)
          RESTORE_BODY=$(printf '%s' "$sched_json" | python3 "$PY_HELPER" restore 2>/dev/null)
          NEED_RESTORE=1

          info "baris uji: dow=$f_day $f_start-$f_end (is_active awal=$f_active)"

          api_request PUT "$API_BASE/v1/professional/schedules" \
            -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$toggle_body"
          if [[ "$LAST_CODE" != "200" ]]; then
            fail "D: PUT toggle jadwal -> HTTP $LAST_CODE (harap 200)"
          else
            api_request GET "$API_BASE/v1/professional/schedules" -H "Authorization: Bearer $TOKEN"
            after_active=$(printf '%s' "$LAST_BODY" | python3 "$PY_HELPER" firststate 2>/dev/null)
            if [[ -n "$after_active" && "$after_active" != "$f_active" ]]; then
              ok "D: toggle persist — is_active baris uji berubah $f_active -> $after_active"
            else
              fail "D: toggle TIDAK persist (is_active tetap '$after_active', harap != '$f_active')"
            fi
          fi

          # Restore eksplisit + verifikasi.
          api_request PUT "$API_BASE/v1/professional/schedules" \
            -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$RESTORE_BODY"
          if [[ "$LAST_CODE" != "200" ]]; then
            fail "D: PUT restore jadwal -> HTTP $LAST_CODE (harap 200)"
          else
            api_request GET "$API_BASE/v1/professional/schedules" -H "Authorization: Bearer $TOKEN"
            state_after=$(printf '%s' "$LAST_BODY" | python3 "$PY_HELPER" state 2>/dev/null)
            restored_active=$(printf '%s' "$LAST_BODY" | python3 "$PY_HELPER" firststate 2>/dev/null)
            if [[ "$state_after" == "$state_before" && "$restored_active" == "$f_active" ]]; then
              ok "D: jadwal dikembalikan ke nilai asli (is_active=$restored_active, semua baris cocok)"
              NEED_RESTORE=0
            else
              fail "D: jadwal TIDAK kembali ke nilai asli — trap akan mencoba restore lagi"
            fi
          fi
        else
          skip "D: tidak ada baris jadwal untuk diuji toggle"
        fi
      fi

      # --- D.4 daftar refund (auth) harus 200
      api_request GET "$API_BASE/v1/care-refunds" -H "Authorization: Bearer $TOKEN"
      if [[ "$LAST_CODE" == "200" ]]; then ok "D: GET /v1/care-refunds (auth) -> 200"
      elif [[ "$LAST_CODE" == "404" ]]; then fail "D: GET /v1/care-refunds -> 404 (route HILANG)"
      else fail "D: GET /v1/care-refunds -> $LAST_CODE (harap 200)"; fi

      # --- D.5 daftar paket (auth) harus 200
      api_request GET "$API_BASE/v1/care-packages" -H "Authorization: Bearer $TOKEN"
      if [[ "$LAST_CODE" == "200" ]]; then ok "D: GET /v1/care-packages (auth) -> 200"
      elif [[ "$LAST_CODE" == "404" ]]; then fail "D: GET /v1/care-packages -> 404 (route HILANG)"
      else fail "D: GET /v1/care-packages -> $LAST_CODE (harap 200)"; fi
    fi
  fi
  rm -f "$PY_HELPER"
fi

# ================================================================ E. RINGKASAN
section "E. Ringkasan"

printf ' +----------------+-------+\n'
printf ' | %-14s | %5d |\n' "PASS" "$PASS"
printf ' | %-14s | %5d |\n' "FAIL" "$FAIL"
printf ' | %-14s | %5d |\n' "SKIP" "$SKIP"
printf ' +----------------+-------+\n'

if [[ "$FAIL" -gt 0 ]]; then
  printf '\nKegagalan:\n'
  for msg in ${FAIL_MSGS[@]+"${FAIL_MSGS[@]}"}; do
    printf '  - %s\n' "$msg"
  done
  printf '\nHASIL: GAGAL (%d FAIL)\n' "$FAIL"
  exit 1
fi

printf '\nHASIL: LULUS (tidak ada FAIL)\n'
exit 0
