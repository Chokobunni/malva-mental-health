$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$javaBin = Join-Path $env:ProgramFiles 'Android/Android Studio/jbr/bin'
if (-not (Test-Path -LiteralPath (Join-Path $javaBin 'javac.exe'))) {
    throw 'Set up the Android Studio JDK before running this native policy regression.'
}
$testOutput = Join-Path ([System.IO.Path]::GetTempPath()) ('malva-notification-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testOutput | Out-Null
& (Join-Path $javaBin 'javac.exe') -d $testOutput (Join-Path $repoRoot 'android/app/src/main/java/id/malva/app/NotificationTransportPolicy.java') (Join-Path $repoRoot 'scripts/tests/NotificationTransportPolicyTest.java')
if ($LASTEXITCODE -ne 0) { throw 'Native notification test compilation failed.' }
& (Join-Path $javaBin 'java.exe') -cp $testOutput NotificationTransportPolicyTest
if ($LASTEXITCODE -ne 0) { throw 'Native notification transport regression failed.' }
Write-Output 'Native notification transport regression passed.'
