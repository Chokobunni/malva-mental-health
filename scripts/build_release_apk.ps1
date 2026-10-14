# ============================================================
# Build APK release Malva — dengan SEMUA --dart-define yang WAJIB.
#
# PENTING: tanpa --dart-define=MALVA_GOOGLE_CLIENT_ID, tombol
# "Continue with Google" akan gagal dengan pesan
# "Login Google belum dikonfigurasi di aplikasi ini."
# (lihat lib/src/config/google_config.dart + google_auth_service.dart)
#
# Pakai (dari root repo):
#   powershell -ExecutionPolicy Bypass -File .\scripts\build_release_apk.ps1
#
# Override bila perlu:
#   ... -ApiBaseUrl "https://api.malva.web.id"
#   ... -GoogleClientId "xxxx.apps.googleusercontent.com"
#   ... -TargetPlatform "android-arm64"
# ============================================================
param(
  [string]$ApiBaseUrl     = "https://api.malva.web.id",
  [string]$GoogleClientId = "910496426601-thlkor62046ftqplmon364p3qhobkntv.apps.googleusercontent.com",
  [string]$TargetPlatform = "android-arm64"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Build APK Malva ===" -ForegroundColor Cyan
Write-Host "  API_BASE_URL     : $ApiBaseUrl"
Write-Host "  GOOGLE_CLIENT_ID : $GoogleClientId"
Write-Host "  TARGET_PLATFORM  : $TargetPlatform"
Write-Host ""

flutter pub get

flutter build apk --release --target-platform $TargetPlatform --dart-define=MALVA_API_BASE_URL=$ApiBaseUrl --dart-define=MALVA_GOOGLE_CLIENT_ID=$GoogleClientId

$apk = [System.IO.Path]::GetFullPath(
  (Join-Path $PSScriptRoot "..\build\app\outputs\flutter-apk\app-release.apk"))
if (Test-Path $apk) {
  # Tanggal dibuat dinamis. Sebelumnya di-hardcode "2026-10-13" sehingga
  # build berikutnya menimpa file lama dengan nama bertanggal salah.
  $dest = Join-Path $env:USERPROFILE (
    "Desktop\Malva-release-{0}.apk" -f (Get-Date -Format "yyyy-MM-dd"))
  Copy-Item $apk $dest -Force
  Write-Host ""
  Write-Host "BERHASIL build." -ForegroundColor Green
  Write-Host "  APK   : $apk"
  Write-Host "  Desktop: $dest" -ForegroundColor Green
  Write-Host ('  SHA1  : ' + (Get-FileHash $dest -Algorithm SHA1).Hash)
  Write-Host ('  Ukuran: ' + [math]::Round((Get-Item $dest).Length / 1MB, 1) + ' MB')
} else {
  Write-Host "APK tidak ditemukan. Periksa output build di atas." -ForegroundColor Red
  exit 1
}
