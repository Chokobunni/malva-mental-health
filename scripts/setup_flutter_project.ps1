param(
  [string]$Platforms = "android,web,windows",
  [string]$ProjectName = "malva_mental_health"
)

$ErrorActionPreference = "Stop"
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$backupRoot = Join-Path $projectRoot ".malva_source_backup"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "Flutter SDK is not available in PATH. Install Flutter first, then run this script again."
}

if (Test-Path $backupRoot) {
  Remove-Item -LiteralPath $backupRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot "lib") -Destination (Join-Path $backupRoot "lib") -Recurse
Copy-Item -LiteralPath (Join-Path $projectRoot "test") -Destination (Join-Path $backupRoot "test") -Recurse
Copy-Item -LiteralPath (Join-Path $projectRoot "pubspec.yaml") -Destination (Join-Path $backupRoot "pubspec.yaml")
Copy-Item -LiteralPath (Join-Path $projectRoot "analysis_options.yaml") -Destination (Join-Path $backupRoot "analysis_options.yaml")

Push-Location $projectRoot
try {
  flutter create . --platforms=$Platforms --project-name=$ProjectName
}
finally {
  Pop-Location
}

Remove-Item -LiteralPath (Join-Path $projectRoot "lib") -Recurse -Force
Remove-Item -LiteralPath (Join-Path $projectRoot "test") -Recurse -Force
Copy-Item -LiteralPath (Join-Path $backupRoot "lib") -Destination (Join-Path $projectRoot "lib") -Recurse
Copy-Item -LiteralPath (Join-Path $backupRoot "test") -Destination (Join-Path $projectRoot "test") -Recurse
Copy-Item -LiteralPath (Join-Path $backupRoot "pubspec.yaml") -Destination (Join-Path $projectRoot "pubspec.yaml") -Force
Copy-Item -LiteralPath (Join-Path $backupRoot "analysis_options.yaml") -Destination (Join-Path $projectRoot "analysis_options.yaml") -Force

Push-Location $projectRoot
try {
  flutter pub get
  Write-Host "Malva Flutter project is ready. Run: flutter run"
}
finally {
  Pop-Location
}
