#!/usr/bin/env bash
# ============================================================
# Malva — gate konvensi kode (R1.4 minimal edit, R4.3 waktu WIB)
# ============================================================
# Dipakai di CI (.github/workflows/backend-ci.yml) dan bisa dijalankan
# manual: bash scripts/check_conventions.sh
#
# Yang diperiksa:
#   1. gofmt bersih (semua berkas .go harus sudah diformat).
#   2. Layer data (internal/store) dilarang memakai time.Now() langsung;
#      wajib clock.Now() agar tanggal bisnis mengikuti WIB.
#      time.Now() TETAP boleh di paket lain untuk durasi/deadline/ticker.
# ============================================================
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail=0

# --- 1. Format ------------------------------------------------------------
unformatted="$(gofmt -l . 2>/dev/null || true)"
if [ -n "$unformatted" ]; then
  printf 'ERROR: berkas berikut belum diformat. Jalankan: gofmt -w .\n' >&2
  printf '%s\n' "$unformatted" >&2
  fail=1
fi

# --- 2. Kebijakan timestamp di layer data ---------------------------------
# Hanya berkas non-test: test boleh memakai time.Now() untuk menyiapkan data.
hits="$(grep -rn --include='*.go' 'time\.Now()' internal/store 2>/dev/null \
  | grep -v '_test\.go' || true)"
if [ -n "$hits" ]; then
  printf 'ERROR: internal/store wajib memakai clock.Now(), bukan time.Now():\n' >&2
  printf '%s\n' "$hits" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  printf 'OK: format bersih, kebijakan clock.Now() di internal/store dipatuhi.\n'
fi
exit "$fail"
