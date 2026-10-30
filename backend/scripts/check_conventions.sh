#!/usr/bin/env bash
# ============================================================
# Malva — gate konvensi kode (R1.4 minimal edit, R4.3 waktu WIB)
# ============================================================
# Dipakai di CI (.github/workflows/backend-ci.yml) dan bisa dijalankan
# manual: bash scripts/check_conventions.sh
#
# Yang diperiksa:
#   1. gofmt bersih (semua berkas .go harus sudah diformat).
#   2. Larangan .UTC() di internal/ (kecuali _test.go): aplikasi WIB-only,
#      tidak boleh ada konversi UTC di kode produksi.
#   3. Larangan time.Parse("2006-01-02", ...) / time.Parse(layout, ...) untuk
#      tanggal bisnis di internal/server & internal/store (kecuali _test.go);
#      wajib time.ParseInLocation(..., clock.Location()).
#   4. time.Now() hanya boleh di berkas allowlist untuk internal/server &
#      internal/store (kecuali _test.go). Timestamp bisnis wajib clock.Now().
#      Daftar allowlist ada di bagian bawah berkas ini (format "# allow: ...").
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

# --- 2. Larangan .UTC() di internal/ --------------------------------------
utc_hits="$(grep -rn --include='*.go' '\.UTC()' internal 2>/dev/null | grep -v '_test\.go' || true)"
if [ -n "$utc_hits" ]; then
  printf 'ERROR: internal/ tidak boleh memakai .UTC(); pakai clock.Now()/clock.Location() (WIB-only):\n' >&2
  printf '%s\n' "$utc_hits" >&2
  fail=1
fi

# --- 3. Larangan time.Parse tanggal bisnis di server & store --------------
parse_hits="$(grep -rnE --include='*.go' 'time\.Parse\("2006-01-02"|time\.Parse\(layout,' \
  internal/server internal/store 2>/dev/null | grep -v '_test\.go' || true)"
if [ -n "$parse_hits" ]; then
  printf 'ERROR: pakai time.ParseInLocation(..., clock.Location()) untuk tanggal bisnis:\n' >&2
  printf '%s\n' "$parse_hits" >&2
  fail=1
fi

# --- 4. time.Now() hanya di berkas allowlist (server & store) -------------
allow_files="$(grep -E '^# allow: .+\.go:' scripts/check_conventions.sh \
  | sed -E 's/^# allow: ([^:]+):.*/\1/' | sort -u)"
now_hits="$(grep -rn --include='*.go' 'time\.Now()' internal/server internal/store 2>/dev/null \
  | grep -v '_test\.go' || true)"
bad_now=""
if [ -n "$now_hits" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    f="${line%%:*}"
    if ! printf '%s\n' "$allow_files" | grep -qxF "$f"; then
      bad_now="${bad_now}${line}"$'\n'
    fi
  done <<< "$now_hits"
fi
if [ -n "$bad_now" ]; then
  printf 'ERROR: time.Now() di luar allowlist. Pakai clock.Now() untuk timestamp bisnis,\n' >&2
  printf 'atau tambahkan "# allow: <path>:<alasan>" bila memang durasi/instant/ID unik:\n' >&2
  printf '%s' "$bad_now" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  printf 'OK: format bersih, kebijakan WIB-only (.UTC()/time.Parse/time.Now) dipatuhi.\n'
fi
exit "$fail"

# ============================================================
# Allowlist time.Now() — sengaja DIPERTAHANKAN karena durasi/instant/ID unik,
# BUKAN timestamp bisnis yang disimpan atau ditampilkan.
# Format: "# allow: <path>:<alasan singkat>"
# ============================================================
# allow: internal/server/handlers_booking.go: cek slot masa depan (instant) + UnixNano id unik
# allow: internal/server/server.go: jendela rate limiter (instant) + fallback id unik
# allow: internal/server/handlers_care_packages.go: cek jendela sesi berjalan (instant)
# allow: internal/server/handlers_upload.go: nama berkas unik (UnixMilli)
