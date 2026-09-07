param(
  [string]$ProjectRoot = "E:\flutter_projects\yalla_accounts"
)
$ErrorActionPreference = 'Stop'
$Runtime = Join-Path $ProjectRoot 'server\yalla_licensing_server\runtime'
$ProcFile = Join-Path $Runtime 'data\c06-processes.json'
if (-not (Test-Path $ProcFile)) {
  Write-Host 'No C06 process state found.'
  exit 0
}
$state = Get-Content $ProcFile -Raw | ConvertFrom-Json
foreach ($pidValue in @($state.serverPid, $state.tunnelPid)) {
  if ($pidValue) {
    Stop-Process -Id ([int]$pidValue) -Force -ErrorAction SilentlyContinue
  }
}
Remove-Item $ProcFile -Force -ErrorAction SilentlyContinue
Write-Host 'C06 test server/tunnel stopped.' -ForegroundColor Green
