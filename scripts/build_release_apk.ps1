# ============================================================
# Build APK release Malva - dengan SEMUA --dart-define yang WAJIB.
#
# PENTING: tanpa --dart-define=MALVA_GOOGLE_CLIENT_ID, tombol
# "Continue with Google" akan gagal dengan pesan
# "Login Google belum dikonfigurasi di aplikasi ini."
# (lihat lib/src/config/google_config.dart + google_auth_service.dart)
#
# Pakai (dari mana saja):
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

# Skrip WAJIB berjalan dari root repo. Sebelumnya, memanggil skrip ini dari
# direktori lain membuat `flutter pub get` gagal ("No pubspec.yaml file found")
# tetapi APK LAMA masih ada di build/, sehingga skrip tetap menyalin APK basi
# ke Desktop dan melaporkan "BERHASIL build". Itu false success yang berbahaya:
# APK tanpa perubahan terbaru bisa dipasang ke perangkat.
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pubspec = Join-Path $repoRoot "pubspec.yaml"
if (-not (Test-Path $pubspec)) {
  Write-Host "pubspec.yaml tidak ditemukan di $repoRoot" -ForegroundColor Red
  exit 1
}

Push-Location $repoRoot
try {
  Write-Host "=== Build APK Malva ===" -ForegroundColor Cyan
  Write-Host "  Repo             : $repoRoot"
  Write-Host "  API_BASE_URL     : $ApiBaseUrl"
  Write-Host "  GOOGLE_CLIENT_ID : $GoogleClientId"
  Write-Host "  TARGET_PLATFORM  : $TargetPlatform"
  Write-Host ""

  $apk = [System.IO.Path]::GetFullPath(
    (Join-Path $repoRoot "build\app\outputs\flutter-apk\app-release.apk"))

  # APK lama TIDAK dihapus (lingkungan build memblokir penghapusan artefak).
  # Kesegaran file diverifikasi lewat LastWriteTime setelah build, sehingga APK
  # basi tidak bisa lolos dan dilaporkan sebagai "BERHASIL build".
  $buildStarted = Get-Date

  flutter pub get
  if ($LASTEXITCODE -ne 0) {
    Write-Host "flutter pub get GAGAL (exit $LASTEXITCODE)." -ForegroundColor Red
    exit 1
  }

  flutter build apk --release --target-platform $TargetPlatform --dart-define=MALVA_API_BASE_URL=$ApiBaseUrl --dart-define=MALVA_GOOGLE_CLIENT_ID=$GoogleClientId
  if ($LASTEXITCODE -ne 0) {
    Write-Host "flutter build apk GAGAL (exit $LASTEXITCODE)." -ForegroundColor Red
    exit 1
  }

  if (-not (Test-Path $apk)) {
    Write-Host "APK tidak ditemukan setelah build. Periksa output di atas." -ForegroundColor Red
    exit 1
  }

  $apkInfo = Get-Item $apk
  if ($apkInfo.LastWriteTime -lt $buildStarted) {
    Write-Host "APK yang ada lebih lama dari proses build - kemungkinan build tidak benar-benar jalan." -ForegroundColor Red
    exit 1
  }

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
  Write-Host ('  Waktu : ' + $apkInfo.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
} finally {
  Pop-Location
}
