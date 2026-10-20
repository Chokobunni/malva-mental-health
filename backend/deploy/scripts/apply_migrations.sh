#!/usr/bin/env bash
# ============================================================
# Malva — terapkan migrasi SQL ke database produksi
# ============================================================
# Backend TIDAK menjalankan migrasi otomatis saat start
# (lihat docs/CI_CD.md §9), jadi skema hanya berubah bila skrip ini
# dijalankan. CI juga tidak menyalin folder migrations/ ke VM — yang
# dikirim hanya binary — sehingga berkas .sql harus disalin terpisah.
#
# Pemakaian:
#   sudo ./apply_migrations.sh --list
#       Tampilkan migrasi yang tersedia (tidak perlu akses database).
#
#   sudo ./apply_migrations.sh 015
#       Terapkan satu migrasi (cocokkan awalan nama berkas).
#
#   sudo ./apply_migrations.sh --all
#       Terapkan SEMUA migrasi berurutan (perilaku docs/CI_CD.md §9).
#       Aman karena migrasi di repo idempoten, tetapi tetap lebih berisiko
#       daripada menyebut nomor secara eksplisit.
#
#   sudo ./apply_migrations.sh --check
#       Hanya periksa kesehatan skema, tidak mengubah apa pun.
#
# Kenapa sudo: berkas /etc/malva/malva-api.env milik root dan berisi
# kredensial database. Skrip membacanya untuk mendapatkan URL koneksi,
# jadi dijalankan sebagai root agar tidak perlu menyalin kredensial
# ke baris perintah (yang akan tersimpan di histori shell).
#
# Variabel lingkungan:
#   MALVA_DATABASE_URL    URL koneksi Postgres. Bila kosong, dibaca dari
#                         berkas env service (MALVA_ENV_FILE).
#   MALVA_ENV_FILE        Default /etc/malva/malva-api.env
#   MALVA_MIGRATIONS_DIR  Default /opt/malva/app/backend/migrations,
#                         fallback ke folder repo relatif skrip ini.
# ============================================================
set -euo pipefail

SERVICE_ENV_FILE="${MALVA_ENV_FILE:-/etc/malva/malva-api.env}"

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# --- 1. Tentukan folder migrasi -------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_VM_DIR="/opt/malva/app/backend/migrations"
# Skrip ada di backend/deploy/scripts/, jadi migrasi dua tingkat di atas.
REPO_DIR="$(cd "$SCRIPT_DIR/../../migrations" 2>/dev/null && pwd || true)"

MIG_DIR="${MALVA_MIGRATIONS_DIR:-}"
if [ -z "$MIG_DIR" ]; then
  if [ -d "$DEFAULT_VM_DIR" ]; then
    MIG_DIR="$DEFAULT_VM_DIR"
  elif [ -n "$REPO_DIR" ] && [ -d "$REPO_DIR" ]; then
    MIG_DIR="$REPO_DIR"
  else
    die "Folder migrasi tidak ditemukan. Set MALVA_MIGRATIONS_DIR."
  fi
fi
[ -d "$MIG_DIR" ] || die "Folder migrasi tidak ada: $MIG_DIR"

DB_URL=""
MODE="${1:-}"

# --- 2. Ambil URL koneksi database ----------------------------------------
# Nilai diambil dari variabel lingkungan, atau dari berkas env service.
# Nilai TIDAK pernah dicetak agar kredensial tidak bocor ke log.
resolve_db_url() {
  local url="${MALVA_DATABASE_URL:-}"
  if [ -n "$url" ]; then
    DB_URL="$url"
    return 0
  fi

  if [ -r "$SERVICE_ENV_FILE" ]; then
    url="$(grep -E '^[[:space:]]*MALVA_DATABASE_URL=' "$SERVICE_ENV_FILE" \
      | tail -n1 | cut -d= -f2- \
      | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
  fi

  if [ -z "$url" ]; then
    if [ "$(id -u)" -ne 0 ]; then
      die "Tidak bisa membaca $SERVICE_ENV_FILE sebagai user biasa.
Berkas env milik root — jalankan ulang dengan sudo:
  sudo $0 $MODE"
    fi
    die "Variabel MALVA_DATABASE_URL tidak ditemukan di $SERVICE_ENV_FILE.
Tambahkan variabel itu ke berkas tersebut, lalu jalankan ulang skrip."
  fi

  DB_URL="$url"
}

# Dipanggil hanya oleh mode yang benar-benar menyentuh database.
require_db() {
  command -v psql >/dev/null 2>&1 \
    || die "psql tidak terpasang. sudo apt-get install -y postgresql-client"
  resolve_db_url
}

# Hentikan pada error SQL pertama, jangan lanjut diam-diam.
psql_run() { psql "$DB_URL" -v ON_ERROR_STOP=1 -q "$@"; }

# --- 3. Pemeriksaan skema -------------------------------------------------
# Migrasi 015 mengubah CHECK constraint medication_logs. Bila constraint
# lama masih aktif, log "partial" akan DITOLAK database walau handler sudah
# menerimanya. Keberadaan 'partial' di definisi constraint dipakai sebagai
# penanda bahwa migrasi benar-benar terpakai (bukan hanya "tidak error").
check_schema() {
  log "== Pemeriksaan skema =="

  local table_exists
  table_exists="$(psql_run -tAc \
    "SELECT to_regclass('public.medication_logs') IS NOT NULL;")"
  if [ "$table_exists" != "t" ]; then
    log "  medication_logs        : BELUM ADA (migrasi 003 belum jalan)"
    return 0
  fi

  local defs
  defs="$(psql_run -tAc \
    "SELECT pg_get_constraintdef(oid) FROM pg_constraint
     WHERE conrelid = 'medication_logs'::regclass AND contype = 'c'
       AND pg_get_constraintdef(oid) LIKE '%status%';")"

  if [ -z "$defs" ]; then
    log "  medication_logs.status : TIDAK ada CHECK constraint (perlu 015)"
  elif printf '%s' "$defs" | grep -q "partial"; then
    log "  medication_logs.status : OK — 'partial' diterima"
  else
    log "  medication_logs.status : MASIH MENOLAK 'partial' (015 belum jalan)"
    log "    definisi saat ini: $defs"
  fi

  # Migrasi 014 (unique index jadwal) gagal bila masih ada baris duplikat.
  if [ "$(psql_run -tAc \
      "SELECT to_regclass('public.professional_schedules') IS NOT NULL;")" = "t" ]; then
    local dups
    dups="$(psql_run -tAc \
      "SELECT count(*) FROM (
         SELECT 1 FROM professional_schedules
         GROUP BY professional_id, day_of_week, start_time, end_time
         HAVING count(*) > 1) d;")"
    if [ "${dups:-0}" = "0" ]; then
      log "  professional_schedules : OK — tidak ada jadwal duplikat"
    else
      log "  professional_schedules : $dups kombinasi duplikat (014 akan gagal)"
      log "    bersihkan dulu dengan backend/admin_scripts/fix_duplicate_schedules.sql"
    fi
  fi

  # Migrasi 016: earnings.session_id + unique parsial. Tanpa kolom ini,
  # penyelesaian sesi akan gagal saat mencatat pendapatan; tanpa unique index,
  # satu sesi bisa tercatat dua kali bila tombol "selesai" terkirim ganda.
  if [ "$(psql_run -tAc \
      "SELECT to_regclass('public.earnings') IS NOT NULL;")" = "t" ]; then
    if [ "$(psql_run -tAc \
        "SELECT count(*) FROM information_schema.columns
         WHERE table_name = 'earnings' AND column_name = 'session_id';")" = "1" ]; then
      log "  earnings.session_id    : OK — kolom ada"
    else
      log "  earnings.session_id    : BELUM ADA (016 belum jalan)"
    fi
    if [ "$(psql_run -tAc \
        "SELECT count(*) FROM pg_indexes
         WHERE tablename = 'earnings'
           AND indexname = 'earnings_session_unique';")" = "1" ]; then
      log "  earnings.session_unique: OK — pendapatan per sesi tidak bisa ganda"
    else
      log "  earnings.session_unique: BELUM ADA (016 belum jalan)"
    fi
  fi
}

# --- 4. Aksi --------------------------------------------------------------
list_migrations() {
  log "Folder migrasi: $MIG_DIR"
  log ""
  local f
  for f in "$MIG_DIR"/*.sql; do
    [ -e "$f" ] || continue
    printf '  %s\n' "$(basename "$f")"
  done
}

apply_one() {
  local file="$1"
  log "-> $(basename "$file")"
  psql_run -f "$file"
  log "   selesai"
}

apply_all() {
  local f applied=0
  for f in "$MIG_DIR"/*.sql; do
    [ -e "$f" ] || continue
    apply_one "$f"
    applied=$((applied + 1))
  done
  log ""
  log "Total migrasi diterapkan: $applied"
}

# --- 5. Main --------------------------------------------------------------
case "$MODE" in
  --list)
    list_migrations
    ;;
  --check)
    require_db
    check_schema
    ;;
  --all)
    require_db
    log "Menerapkan SEMUA migrasi di $MIG_DIR"
    apply_all
    log ""
    check_schema
    ;;
  ""|-h|--help)
    sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    # Cocokkan awalan nama berkas: "015", "015_medication..." atau nama penuh.
    matches="$(find "$MIG_DIR" -maxdepth 1 -name "${MODE}*.sql" | sort)"
    if [ -z "$matches" ]; then
      log "Tidak ada migrasi cocok '$MODE'. Yang tersedia:"
      list_migrations
      exit 1
    fi
    count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
    if [ "$count" -gt 1 ]; then
      die "'$MODE' cocok dengan lebih dari satu berkas:
$matches
Sebutkan nomor yang lebih spesifik."
    fi
    require_db
    log "Menerapkan migrasi: $(basename "$matches")"
    apply_one "$matches"
    log ""
    check_schema
    ;;
esac
