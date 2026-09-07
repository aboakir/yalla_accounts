param(
  [string]$ProjectRoot = "E:\flutter_projects\yalla_accounts",
  [int]$Port = 8787
)

$ErrorActionPreference = 'Stop'
$Runtime = Join-Path $ProjectRoot 'server\yalla_licensing_server\runtime'
$Downloads = Join-Path $env:USERPROFILE 'Downloads'
$Tools = Join-Path $env:USERPROFILE '.yalla_accounts\tools'
$Cloudflared = Join-Path $Tools 'cloudflared.exe'
$EmptyConfig = Join-Path $Tools 'c06-empty.yml'
$ServerOut = Join-Path $Runtime 'data\c06-server.out.log'
$ServerErr = Join-Path $Runtime 'data\c06-server.err.log'
$TunnelOut = Join-Path $Runtime 'data\c06-tunnel.out.log'
$TunnelErr = Join-Path $Runtime 'data\c06-tunnel.err.log'
$ProcFile = Join-Path $Runtime 'data\c06-processes.json'
$ContextFile = Join-Path $Downloads 'YALLA_C06_TEST_CONTEXT.txt'

if (-not (Test-Path (Join-Path $ProjectRoot 'pubspec.yaml'))) {
  throw "ProjectRoot غير صحيح: $ProjectRoot"
}
if (-not (Test-Path (Join-Path $Runtime 'server.mjs'))) {
  throw 'C06 licensing runtime غير موجود. طبّق YALLA_C06_FINAL_PREP_FIX1 أولاً.'
}

$node = Get-Command node -ErrorAction SilentlyContinue
if ($null -eq $node) { throw 'Node.js غير موجود في PATH.' }
$nodeVersion = (& node --version).Trim()
Write-Host "Node: $nodeVersion"

New-Item -ItemType Directory -Force -Path (Join-Path $Runtime 'data') | Out-Null
New-Item -ItemType Directory -Force -Path $Tools | Out-Null
Set-Content -Encoding ASCII -Path $EmptyConfig -Value ""

# Stop previous C06 processes from this runtime only.
if (Test-Path $ProcFile) {
  try {
    $old = Get-Content $ProcFile -Raw | ConvertFrom-Json
    foreach ($pidValue in @($old.serverPid, $old.tunnelPid)) {
      if ($pidValue) {
        Stop-Process -Id ([int]$pidValue) -Force -ErrorAction SilentlyContinue
      }
    }
  } catch {}
}

Push-Location $Runtime
try {
  Write-Host "`n[1/6] Initialize C06 Ed25519 authority" -ForegroundColor Cyan
  & node .\init_c06.mjs
  if ($LASTEXITCODE -ne 0) { throw 'C06 authority initialization failed.' }

  Write-Host "`n[2/6] Runtime selftest" -ForegroundColor Cyan
  & node .\selftest.mjs
  if ($LASTEXITCODE -ne 0) { throw 'C06 licensing runtime selftest failed.' }

  Write-Host "`n[3/6] Start local licensing server" -ForegroundColor Cyan
  foreach ($p in @($ServerOut,$ServerErr,$TunnelOut,$TunnelErr)) {
    Remove-Item $p -Force -ErrorAction SilentlyContinue
  }
  $serverArgs = @('.\server.mjs')
  $serverEnv = @{
    YALLA_C06_HOST = '127.0.0.1'
    YALLA_C06_PORT = "$Port"
  }
  # Start-Process has no -Environment on Windows PowerShell 5.1, so use cmd /c SET.
  $serverCmd = "set YALLA_C06_HOST=127.0.0.1&& set YALLA_C06_PORT=$Port&& node server.mjs"
  $serverProc = Start-Process -FilePath 'cmd.exe' `
    -ArgumentList @('/d','/s','/c',"`"$serverCmd`"") `
    -WorkingDirectory $Runtime `
    -RedirectStandardOutput $ServerOut `
    -RedirectStandardError $ServerErr `
    -WindowStyle Hidden `
    -PassThru

  $localHealth = "http://127.0.0.1:$Port/health"
  $localOk = $false
  for ($i=0; $i -lt 40; $i++) {
    try {
      $health = Invoke-RestMethod -Uri $localHealth -TimeoutSec 2
      if ($health.ok -eq $true) { $localOk = $true; break }
    } catch {}
    Start-Sleep -Milliseconds 500
  }
  if (-not $localOk) {
    Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue
    $err = if (Test-Path $ServerErr) { Get-Content $ServerErr -Raw } else { '' }
    throw "Local licensing server failed to start. $err"
  }

  Write-Host "`n[4/6] Ensure cloudflared" -ForegroundColor Cyan
  if (-not (Test-Path $Cloudflared)) {
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -notmatch 'AMD64|x86_64') {
      throw "Automatic cloudflared download currently expects Windows AMD64. Architecture: $arch"
    }
    $downloadUrl = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
    Write-Host 'Downloading cloudflared for C06 test tunnel...'
    Invoke-WebRequest -Uri $downloadUrl -OutFile $Cloudflared -UseBasicParsing
  }
  & $Cloudflared --version
  if ($LASTEXITCODE -ne 0) { throw 'cloudflared executable failed.' }

  Write-Host "`n[5/6] Start HTTPS Quick Tunnel" -ForegroundColor Cyan
  $tunnelProc = Start-Process -FilePath $Cloudflared `
    -ArgumentList @('tunnel','--config',$EmptyConfig,'--no-autoupdate','--url',"http://127.0.0.1:$Port") `
    -WorkingDirectory $Runtime `
    -RedirectStandardOutput $TunnelOut `
    -RedirectStandardError $TunnelErr `
    -WindowStyle Hidden `
    -PassThru

  $publicUrl = $null
  for ($i=0; $i -lt 120; $i++) {
    $all = ''
    if (Test-Path $TunnelOut) { $all += (Get-Content $TunnelOut -Raw -ErrorAction SilentlyContinue) }
    if (Test-Path $TunnelErr) { $all += "`n" + (Get-Content $TunnelErr -Raw -ErrorAction SilentlyContinue) }
    $m = [regex]::Match($all, 'https://[a-z0-9-]+\.trycloudflare\.com')
    if ($m.Success) { $publicUrl = $m.Value.TrimEnd('/'); break }
    if ($tunnelProc.HasExited) { break }
    Start-Sleep -Milliseconds 500
  }
  if (-not $publicUrl) {
    Stop-Process -Id $tunnelProc.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue
    $err = if (Test-Path $TunnelErr) { Get-Content $TunnelErr -Raw } else { '' }
    throw "Could not obtain TryCloudflare URL. $err"
  }

  $remoteOk = $false
  for ($i=0; $i -lt 30; $i++) {
    try {
      $remoteHealth = Invoke-RestMethod -Uri "$publicUrl/health" -TimeoutSec 5
      if ($remoteHealth.ok -eq $true) { $remoteOk = $true; break }
    } catch {}
    Start-Sleep -Milliseconds 700
  }
  if (-not $remoteOk) {
    Stop-Process -Id $tunnelProc.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue
    throw 'Public HTTPS tunnel health check failed.'
  }

  Write-Host "`n[6/6] Write C06 context" -ForegroundColor Cyan
  $activationCode = (Get-Content (Join-Path $Runtime 'secrets\C06_ACTIVATION_CODE.txt') -Raw).Trim()
  $trustedHash = (Get-Content (Join-Path $Runtime 'secrets\C06_TRUSTED_KEY_SHA256.txt') -Raw).Trim()

  $content = @"
YALLA C06 TEST CONTEXT
======================
MODE=C06_TEST_ONLY
CREATED_AT=$((Get-Date).ToString('o'))

YALLA_LICENSING_BASE_URL=$publicUrl
YALLA_LICENSE_TRUSTED_KEY_SHA256=$trustedHash
YALLA_STORE_DISTRIBUTION=true
YALLA_PRIVACY_URL=$publicUrl/privacy
YALLA_TERMS_URL=$publicUrl/terms
YALLA_ACCOUNT_DELETION_URL=$publicUrl/account-deletion

C06_ACTIVATION_CODE=$activationCode

CODEMAGIC ENVIRONMENT VARIABLES
-------------------------------
YALLA_LICENSING_BASE_URL=$publicUrl
YALLA_LICENSE_TRUSTED_KEY_SHA256=$trustedHash
YALLA_STORE_DISTRIBUTION=true
YALLA_PRIVACY_URL=$publicUrl/privacy
YALLA_TERMS_URL=$publicUrl/terms
YALLA_ACCOUNT_DELETION_URL=$publicUrl/account-deletion

SERVER_PID=$($serverProc.Id)
TUNNEL_PID=$($tunnelProc.Id)

IMPORTANT
---------
Keep this Windows PC online and keep both processes running during the Codemagic build and the iPhone C06 test.
Quick Tunnel is TEST-ONLY and must not be used for production release.
"@
  Set-Content -Path $ContextFile -Value $content -Encoding UTF8

  @{
    serverPid = $serverProc.Id
    tunnelPid = $tunnelProc.Id
    publicUrl = $publicUrl
    contextFile = $ContextFile
    startedAt = (Get-Date).ToString('o')
  } | ConvertTo-Json | Set-Content -Path $ProcFile -Encoding UTF8

  Write-Host "`nC06 TEST SERVER: READY" -ForegroundColor Green
  Write-Host "HTTPS URL: $publicUrl"
  Write-Host "Trusted key: $trustedHash"
  Write-Host "Activation code: $activationCode" -ForegroundColor Yellow
  Write-Host "Context file: $ContextFile"
  Write-Host 'Keep this PC online until the iPhone test is finished.'
} finally {
  Pop-Location
}
