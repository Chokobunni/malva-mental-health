#!/usr/bin/env bash
# ============================================================
# Malva — gate WIB-only untuk kode Dart (R8: zona waktu WIB-only)
# ============================================================
# Dipakai di CI (.github/workflows/flutter-ci.yml, job analyze) dan bisa
# dijalankan manual dari root repo: bash scripts/check_wib_dart.sh
#
# Aplikasi hanya untuk Indonesia: semua waktu adalah WIB (Asia/Jakarta),
# apa pun zona perangkat. Sumber tunggal ada di lib/src/time/wib.dart.
#
# Yang diperiksa (di dalam lib/, berkas non-generated):
#   1. Larangan `.toLocal()` — hasil bergantung zona perangkat.
#   2. Larangan `DateTime.now()` — jam perangkat, bukan WIB.
#   3. Larangan `.toUtc()` — UTC tidak boleh muncul di logika aplikasi.
#
# Penjelasan pengecualian:
#   - lib/src/time/wib.dart adalah SATU-SATUNYA berkas yang boleh membaca
#     zona/jam perangkat (`DateTime.now()` sebagai instant + `tz`), karena
#     di situlah konversi ke WIB dilakukan secara terpusat. `.toLocal()` dan
#     `.toUtc()` tetap dilarang bahkan di sana.
#   - Header HTTP `Date` (GMT/RFC1123) di server_clock.dart adalah format
#     kabel protokol, bukan logika bisnis — dibaca mentah, lalu hasilnya
#     dibungkus toWib(). Kata "GMT"/"RFC1123" diizinkan; `.toUtc()`
#     tetap dilarang.
# ============================================================
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail=0

# --- 1. Larangan .toLocal() -------------------------------------------
hits="$(grep -rn --include='*.dart' '\.toLocal()' lib 2>/dev/null || true)"
if [ -n "$hits" ]; then
  printf 'ERROR: .toLocal() bergantung zona perangkat. Pakai toWib() dari lib/src/time/wib.dart:\n' >&2
  printf '%s\n' "$hits" >&2
  fail=1
fi

# --- 2. Larangan DateTime.now() (kecuali wib.dart) ---------------------
hits="$(grep -rn --include='*.dart' 'DateTime\.now()' lib 2>/dev/null \
  | grep -v 'lib/src/time/wib.dart' || true)"
if [ -n "$hits" ]; then
  printf 'ERROR: DateTime.now() membaca jam perangkat. Pakai wibNow() dari lib/src/time/wib.dart:\n' >&2
  printf '%s\n' "$hits" >&2
  fail=1
fi

# --- 3. Larangan .toUtc() ----------------------------------------------
hits="$(grep -rn --include='*.dart' '\.toUtc()' lib 2>/dev/null || true)"
if [ -n "$hits" ]; then
  printf 'ERROR: .toUtc() dilarang — aplikasi tidak memakai UTC sama sekali. Pakai toWib():\n' >&2
  printf '%s\n' "$hits" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  printf 'OK: Dart WIB-only dipatuhi (tanpa .toLocal/DateTime.now/.toUtc).\n'
fi
exit "$fail"
