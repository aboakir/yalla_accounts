param(
    [string]$ProjectPath = 'E:\flutter_projects\yalla_accounts',
    [string]$AdminEmail = 'owner@yalla.local',
    [int]$Port = 8787
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Test-LoopbackPortFree([int]$CandidatePort) {
    $probe = $null
    try {
        $probe = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $CandidatePort)
        $probe.Start()
        return $true
    } catch {
        return $false
    } finally {
        if ($null -ne $probe) {
            try { $probe.Stop() } catch {}
        }
    }
}

$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$serverScript = Join-Path $ProjectPath 'tools\sec015a\dev_yalla_admin_server.ps1'
if (-not (Test-Path -LiteralPath $serverScript -PathType Leaf)) { throw "Missing local admin server: $serverScript" }

$stateDir = "$env:USERPROFILE\Downloads\Yalla_Local_Admin_Dev"
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

$selectedPort = $Port
$maxPort = [Math]::Min(65535, $Port + 20)
while ($selectedPort -le $maxPort -and -not (Test-LoopbackPortFree $selectedPort)) {
    Write-Host "[SEC.015A] Port $selectedPort is busy; trying $($selectedPort + 1)..." -ForegroundColor Yellow
    $selectedPort++
}
if ($selectedPort -gt $maxPort) { throw "No free loopback port found in range $Port-$maxPort." }
if ($selectedPort -ne $Port) {
    Write-Host "[SEC.015A] Using free loopback port $selectedPort instead of requested port $Port." -ForegroundColor Yellow
}

$readyPath = Join-Path $stateDir 'server_ready.txt'
$enrollmentPath = Join-Path $stateDir 'Yalla_LOCAL_SUPER_OWNER_ENROLLMENT.txt'
$startupLog = Join-Path $stateDir ("server_startup_{0}.log" -f $selectedPort)
$bootstrapPath = Join-Path $stateDir ("start_server_{0}.ps1" -f $selectedPort)
Remove-Item -LiteralPath $readyPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $startupLog -Force -ErrorAction SilentlyContinue

function Escape-SingleQuoted([string]$Value) { return $Value.Replace("'", "''") }
$serverEsc = Escape-SingleQuoted $serverScript
$emailEsc = Escape-SingleQuoted $AdminEmail
$stateEsc = Escape-SingleQuoted $stateDir
$logEsc = Escape-SingleQuoted $startupLog

$bootstrap = @"
`$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try {
    & '$serverEsc' -AdminEmail '$emailEsc' -Port $selectedPort -StateDir '$stateEsc'
} catch {
    `$detail = (`$_ | Out-String)
    `$detail | Set-Content -LiteralPath '$logEsc' -Encoding UTF8
    Write-Host ''
    Write-Host '[YALLA LOCAL ADMIN DEV SERVER] STARTUP FAILED' -ForegroundColor Red
    Write-Host `$detail -ForegroundColor Red
    Start-Sleep -Seconds 8
    exit 1
}
"@
$bootstrap | Set-Content -LiteralPath $bootstrapPath -Encoding UTF8

$quotedBootstrap = '"' + $bootstrapPath + '"'
$serverArgs = "-NoProfile -ExecutionPolicy Bypass -File $quotedBootstrap"
$server = Start-Process -FilePath 'powershell.exe' -ArgumentList $serverArgs -Verb RunAs -PassThru

try {
    $deadline = (Get-Date).AddSeconds(25)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $readyPath)) {
        if ($server.HasExited) {
            $detail = if (Test-Path -LiteralPath $startupLog) { (Get-Content -LiteralPath $startupLog -Raw) } else { 'No startup log was produced.' }
            throw "Local Yalla admin server exited before becoming ready.`nStartup log: $startupLog`n$detail"
        }
        Start-Sleep -Milliseconds 300
    }
    if (-not (Test-Path -LiteralPath $readyPath)) {
        $detail = if (Test-Path -LiteralPath $startupLog) { (Get-Content -LiteralPath $startupLog -Raw) } else { 'No startup log was produced.' }
        throw "Timed out waiting for local Yalla admin server.`nSelected port: $selectedPort`nStartup log: $startupLog`n$detail"
    }

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host '[SEC.015A] LOCAL SUPER OWNER HARNESS READY' -ForegroundColor Green
    Get-Content -LiteralPath $readyPath
    Write-Host "SELECTED_PORT=$selectedPort" -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green

    $readyText = (Get-Content -LiteralPath $readyPath -Raw)
    if ($readyText -match 'ENROLLED=False' -and (Test-Path -LiteralPath $enrollmentPath)) {
        Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $enrollmentPath + '"') | Out-Null
        Write-Host "Enrollment details opened in Notepad: $enrollmentPath" -ForegroundColor Yellow
    } elseif ($readyText -match 'ENROLLED=True') {
        Write-Host 'Existing local YALLA_SUPER_OWNER enrollment detected and preserved.' -ForegroundColor Green
    }

    Push-Location $ProjectPath
    try {
        & flutter run -d windows `
            --dart-define="YALLA_LICENSING_BASE_URL=http://127.0.0.1:$selectedPort/" `
            --dart-define="YALLA_ALLOW_INSECURE_LOOPBACK_FOR_TESTING=true"
        if ($LASTEXITCODE -ne 0) { throw "flutter run failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
} finally {
    if ($null -ne $server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
    }
}
