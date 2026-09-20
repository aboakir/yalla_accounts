param([Parameter(Mandatory=$true)][ValidateSet('windows','android')][string]$Target)
$ErrorActionPreference = 'Stop'
$Source = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Push-Location $Source
try {
    & flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Locked dependency resolution failed.' }
    & flutter analyze --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Analyzer error gate failed.' }
    & flutter test --no-pub --concurrency=4 --timeout=60s
    if ($LASTEXITCODE -ne 0) { throw 'Regression gate failed; no build produced.' }
    if ($Target -eq 'windows') {
        & flutter build windows --release --no-pub --dart-define=YALLA_OWNER_LOCAL_FULL_ACCESS=true
    } else {
        # Personal test APK only. Production signing requirements are not weakened.
        & flutter build apk --debug --no-pub --dart-define=YALLA_OWNER_LOCAL_FULL_ACCESS=true
    }
    if ($LASTEXITCODE -ne 0) { throw 'Platform build failed.' }
    Write-Host 'Owner-only build completed. Do not distribute this build to customers.'
} finally {
    Pop-Location
}
