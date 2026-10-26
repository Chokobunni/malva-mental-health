#!/usr/bin/env bash
# ============================================================
# Malva — ambang minimum coverage per paket (R12.1 versi bertarget)
# ============================================================
# Kenapa per paket, bukan total: test internal/store adalah integration test
# ke Postgres nyata dan di-skip bila DB tidak tersedia, sehingga coverage
# total berubah drastis antara lokal (tanpa DB) dan CI (dengan DB).
# Ambang global jadi tidak bermakna. Karena itu yang dijaga adalah paket
# yang hermetic (tidak butuh DB) — di situ angka coverage bisa dipercaya.
#
# Ambang = angka saat gate ini dipasang (2026-10-27) dikurangi margin ±10
# poin, supaya tidak rapuh terhadap penambahan kode kecil.
#
# Pemakaian: bash scripts/check_coverage.sh coverage.out
# ============================================================
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

FILE="${1:-coverage.out}"
if [ ! -f "$FILE" ]; then
  printf 'ERROR: berkas coverage tidak ditemukan: %s\n' "$FILE" >&2
  printf 'Jalankan dulu: go test -coverprofile=%s ./...\n' "$FILE" >&2
  exit 1
fi

awk '
BEGIN {
  n = split("auth:55 clock:90 config:85 inference:70 logging:60 notify:30 payment:40 screening:75 security:15", fl, " ")
  for (i = 1; i <= n; i++) {
    split(fl[i], kv, ":")
    order[i] = kv[1]
    floor[kv[1]] = kv[2] + 0
  }
}
NR == 1 { next }
{
  split($1, a, ":")
  f = a[1]
  m = split(f, parts, "/")
  pkg = parts[m - 1]
  total[pkg] += $2 + 0
  if ($3 + 0 > 0) covered[pkg] += $2 + 0
}
END {
  fail = 0
  printf "%-12s %8s %10s  %s\n", "PAKET", "COVERAGE", "MINIMUM", "STATUS"
  for (i = 1; i <= n; i++) {
    p = order[i]
    if (!(p in total)) {
      printf "%-12s %8s %10d%%  SKIP (tidak ada di coverage.out)\n", p, "-", floor[p]
      continue
    }
    pct = total[p] ? 100 * covered[p] / total[p] : 0
    ok = (pct + 0 >= floor[p])
    if (!ok) fail = 1
    printf "%-12s %7.1f%% %9d%%  %s\n", p, pct, floor[p], (ok ? "OK" : "GAGAL")
  }
  if (fail) {
    printf "\nERROR: ada paket di bawah ambang minimum. Tambahkan test, atau\n" > "/dev/stderr"
    printf "turunkan ambang di scripts/check_coverage.sh BILA penurunan disengaja.\n" > "/dev/stderr"
  } else {
    printf "\nOK: semua paket hermetic memenuhi ambang minimum.\n"
  }
  exit fail
}
' "$FILE"
