#!/usr/bin/env bash
# ============================================================
# Malva — gate isolasi platform (anti-regresi)
# ============================================================
# Menjaga agar kode BERSAMA (lib/src/{screens,services,widgets,providers,...})
# tidak menyentuh API khusus platform. Dijalankan di flutter-ci.yml (T05) dan
# bisa dijalankan lokal.
#
# Kenapa gate ini ada: `flutter build web` TIDAK menangkap `dart:io` — ia lolos
# kompilasi dan baru meledak saat runtime. Build hijau BUKAN bukti web sehat.
# Gate statis ini menangkap pola sebelum sampai ke produksi.
#
# Pemakaian:
#   bash scripts/check_platform_isolation.sh            # gagal hanya pada
#                                                        # pelanggaran BARU
#   bash scripts/check_platform_isolation.sh --strict   # gagal juga bila masih
#                                                        # ada pengecualian
#                                                        # sementara (target T05)
#
# Aturan allowlist yang menyusut (WEB_ARCHITECTURE §6.2): setiap tugas boleh
# memuat daftar pengecualian sementara, dan HANYA boleh MENGHAPUS entri.
# Menambah entri baru = penolakan review.
#
# Kunci allowlist = "<cek>|<berkas>|<paket>" untuk cek plugin, dan
# "<cek>|<berkas>" untuk cek lain. Untuk cek plugin, paket HARUS ikut dikunci:
# berkas yang diizinkan memakai `image_picker` TIDAK otomatis boleh menambah
# `firebase_messaging` (lubang yang ditutup di T02).
# ============================================================
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

STRICT=0
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1 ;;
    *)
      echo "argumen tidak dikenal: $arg" >&2
      exit 2
      ;;
  esac
done

fail=0
exempt_hits=0

# ── Allowlist sementara (status: setelah T03 — dart:io KOSONG) ───────────
# Kunci: "<cek>|<berkas>" atau "<cek>|<berkas>|<paket>". Nilai: alasan + tugas.
# Cek 1 = dart:io · 2 = kIsWeb · 3 = plugin khusus platform · 4 = Platform.is.
declare -A ALLOW=(
  # ── Cek 1: dart:io di luar lib/src/platform/io/ ──
  # KOSONG — export_service & therapy_library kini lewat FileExporter.
  # ── Cek 2: kIsWeb di luar lapisan platform ──
  # (kosong)
  # ── Cek 3: plugin khusus platform diimpor kode bersama (dikunci PER PAKET) ──
  ["3|lib/src/screens/professional_dashboard_screen.dart|share_plus"]="T03-lanjut: pakai FileExporter"
  ["3|lib/src/services/medication_reminder_service.dart|flutter_local_notifications"]="di balik ReminderScheduler io/"
  ["3|lib/src/services/push_notification_service.dart|flutter_local_notifications"]="T03-lanjut: jadi PushRegistrar io/"
  ["3|lib/src/services/push_notification_service.dart|firebase_messaging"]="T03-lanjut: jadi PushRegistrar io/"
  ["3|lib/src/services/google_auth_service.dart|google_sign_in"]="T03-lanjut: lewat GoogleClientConfig"
  ["3|lib/src/providers/location_provider.dart|geolocator"]="di luar lingkup T03: port geolokasi"
  ["3|lib/src/screens/safety/emergency_dashboard_screen.dart|geolocator"]="di luar lingkup T03: port geolokasi"
  ["3|lib/src/screens/record_screen.dart|file_picker"]="di luar lingkup T03: FilePickerPort"
  # ── Cek 4: Platform.is / defaultTargetPlatform ──
  ["4|lib/src/services/push_notification_service.dart"]="T03-lanjut: capability via port"
)

record() { # $1=cek $2=berkas $3=deskripsi [$4=paket]
  local key
  if [ -n "${4:-}" ]; then
    key="$1|$2|$4"
  else
    key="$1|$2"
  fi
  if [[ -n "${ALLOW[$key]:-}" ]]; then
    printf '\033[33m• ALLOW (cek %s) %s — %s [%s]\033[0m\n' \
      "$1" "$2" "$3" "${ALLOW[$key]}"
    exempt_hits=$((exempt_hits + 1))
  else
    printf '\033[31m✗ PELANGGARAN (cek %s) %s — %s\033[0m\n' "$1" "$2" "$3"
    fail=1
  fi
}

# ── 1. dart:io hanya di lib/src/platform/io/ ──────────────────────────────
# Tangkap `import 'dart:io'`, `import "dart:io"`, dan `export 'dart:io'`
# (kutip tunggal maupun ganda) — versi lama hanya menangkap kutip tunggal.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  record 1 "$f" "dart:io (import/export)"
done < <(grep -rlE --include='*.dart' \
  "(^|[[:space:]])(import|export)[[:space:]]+['\"]dart:io['\"]" lib \
  | grep -v '^lib/src/platform/io/' || true)

# ── 2. kIsWeb hanya di platform/ + firebase_options.dart ─────────────────
while IFS= read -r f; do
  [ -n "$f" ] || continue
  record 2 "$f" "kIsWeb"
done < <(grep -rl --include='*.dart' 'kIsWeb' lib \
  | grep -v '^lib/src/platform/' | grep -v '^lib/firebase_options.dart' || true)

# ── 3. Plugin khusus platform hanya boleh diimpor dari platform/ ─────────
for pkg in flutter_local_notifications path_provider share_plus image_picker \
           google_sign_in geolocator file_picker firebase_messaging \
           flutter_secure_storage; do
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    record 3 "$f" "package:$pkg" "$pkg"
  done < <(grep -rl --include='*.dart' "package:$pkg/" lib \
    | grep -v '^lib/src/platform/' || true)
done

# ── 4. Tidak ada Platform.isX / defaultTargetPlatform di luar platform/ ──
while IFS= read -r f; do
  [ -n "$f" ] || continue
  record 4 "$f" "Platform.is/defaultTargetPlatform"
done < <(grep -rl --include='*.dart' -E 'Platform\.is|defaultTargetPlatform' lib \
  | grep -v '^lib/src/platform/' | grep -v '^lib/firebase_options.dart' || true)

echo
echo "Pengecualian sementara aktif: $exempt_hits hit (target T05: 0)."

if [ "$fail" -ne 0 ]; then
  echo
  echo "Isolasi platform DILANGGAR — ada pelanggaran BARU di luar allowlist."
  echo "Pindahkan logika khusus platform ke lib/src/platform/{io,web}/ dan"
  echo "akses lewat port di lib/src/platform/contracts/ports.dart."
  exit 1
fi

if [ "$STRICT" -eq 1 ] && [ "$exempt_hits" -ne 0 ]; then
  echo
  echo "STRICT: masih ada $exempt_hits pengecualian sementara."
  echo "Hapus entri allowlist seiring tugas T02/T03 menyelesaikan migrasi."
  exit 1
fi

echo "OK: tidak ada pelanggaran baru. Isolasi platform sehat."
exit 0
