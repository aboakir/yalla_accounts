param(
  [string]$ContextFile = "$env:USERPROFILE\Downloads\YALLA_C06_TEST_CONTEXT.txt"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $ContextFile)) { throw "Context file not found: $ContextFile" }
$lines = Get-Content $ContextFile
$map = @{}
foreach ($line in $lines) {
  if ($line -match '^([A-Z0-9_]+)=(.+)$') { $map[$matches[1]] = $matches[2].Trim() }
}
$url = $map['YALLA_LICENSING_BASE_URL']
$hash = $map['YALLA_LICENSE_TRUSTED_KEY_SHA256']
if (-not $url -or -not $hash) { throw 'C06 context is incomplete.' }
$health = Invoke-RestMethod -Uri "$url/health" -TimeoutSec 10
if ($health.ok -ne $true) { throw 'C06 public health check failed.' }
if ($health.authority.public_key_sha256 -ne $hash) { throw 'Trusted key mismatch.' }
Write-Host 'C06 HTTPS endpoint + trust key: VERIFIED' -ForegroundColor Green
Write-Host "URL: $url"
