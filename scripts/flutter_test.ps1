# scripts/flutter_test.ps1
#
# Jalankan `flutter test` dengan variabel proxy dikosongkan lebih dulu.
#
# Kenapa perlu: di mesin Windows yang punya HTTP_PROXY / HTTPS_PROXY (mis.
# proxy WorkBuddy di 127.0.0.1:xxxxx), `flutter_tester` gagal connect dengan
#   "Unable to connect to flutter_tester process:
#    WebSocketException: Invalid WebSocket upgrade request"
# alasannya Dart memaksa WebSocket ke localhost lewat proxy tersebut.
# Test-nya sendiri sehat - dibuktikan 179 test lulus setelah proxy dibuang.
#
# Pakai:
#   pwsh scripts/flutter_test.ps1                        # semua test
#   pwsh scripts/flutter_test.ps1 test/assessment_test.dart
#   pwsh scripts/flutter_test.ps1 --plain-name "nama test"
#
# Argumen diteruskan apa adanya ke `flutter test`.

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$TestArgs
)

$proxyVars = @(
    'HTTP_PROXY',
    'http_proxy',
    'HTTPS_PROXY',
    'https_proxy',
    'ALL_PROXY',
    'all_proxy'
)
foreach ($name in $proxyVars) {
    Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
}

# Host lokal jangan pernah lewat proxy.
$env:NO_PROXY = '127.0.0.1,localhost'
$env:no_proxy = '127.0.0.1,localhost'

flutter test @TestArgs
exit $LASTEXITCODE
