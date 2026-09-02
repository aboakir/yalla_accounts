param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Fail([string]$Message) { throw $Message }
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { Fail $Message }
}

function Get-FreePort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Wait-Ready([string]$ReadyPath, $Process) {
    for ($i = 0; $i -lt 120; $i++) {
        if (Test-Path -LiteralPath $ReadyPath) { return }
        if ($Process.HasExited) { Fail 'P02 OTP test server exited before ready.' }
        Start-Sleep -Milliseconds 250
        $Process.Refresh()
    }
    Fail 'Timed out waiting for P02 OTP test server.'
}

function Invoke-Json([string]$BaseUrl, [string]$Path, $Body) {
    return Invoke-RestMethod -Uri "$BaseUrl$Path" -Method Post `
        -ContentType 'application/json; charset=utf-8' `
        -Body ($Body | ConvertTo-Json -Depth 8 -Compress) -ErrorAction Stop
}

function Assert-HttpFailure([scriptblock]$Action, [int[]]$AllowedStatus) {
    try {
        [void](& $Action)
        Fail 'Expected HTTP failure but request succeeded.'
    } catch {
        $status = $null
        if ($null -ne $_.Exception.Response) {
            try { $status = [int]$_.Exception.Response.StatusCode } catch {}
        }
        if ($null -eq $status -or $AllowedStatus -notcontains $status) {
            throw
        }
    }
}

$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$server = Join-Path $ProjectPath 'tools\sec015a\dev_yalla_admin_server.ps1'
if (!(Test-Path -LiteralPath $server)) { Fail "Server missing: $server" }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$stateDir = Join-Path $env:TEMP "Yalla_P02_OTP_SELFTEST_$stamp"
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$stdout = Join-Path $stateDir 'server_stdout.txt'
$stderr = Join-Path $stateDir 'server_stderr.txt'
$ready = Join-Path $stateDir 'server_ready.txt'
$port = Get-FreePort
$baseUrl = "http://127.0.0.1:$port"
$proc = $null

try {
    Remove-Item Env:YALLA_SMS_WEBHOOK_URL -ErrorAction SilentlyContinue
    Remove-Item Env:YALLA_SMS_WEBHOOK_TOKEN -ErrorAction SilentlyContinue

    $serverArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$server`" -AdminEmail `"p02.otp@yalla.local`" -Port $port -StateDir `"$stateDir`""
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $serverArgs -PassThru `
        -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    Wait-Ready $ready $proc

    $phone = '+970599123456'
    $start = Invoke-Json $baseUrl '/v1/customer-phone-verification/start' @{ phone = $phone }
    Assert-True (([string]$start.status) -eq 'OTP_SENT') 'OTP start did not return OTP_SENT.'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$start.challenge_id)) 'OTP challenge id missing.'
    Assert-True ($null -eq $start.PSObject.Properties['code']) 'OTP leaked in start response.'
    Assert-True ($null -eq $start.PSObject.Properties['otp']) 'OTP leaked in start response.'

    $challenge = [string]$start.challenge_id
    $code = ''
    for ($i = 0; $i -lt 60 -and [string]::IsNullOrWhiteSpace($code); $i++) {
        if (Test-Path -LiteralPath $stdout) {
            $text = Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue
            $match = [regex]::Match(
                [string]$text,
                "(?m)^\[CUSTOMER_OTP_DEV\] challenge=$([regex]::Escape($challenge)) phone=\+970599123456 code=([0-9]{6})\s*$"
            )
            if ($match.Success) { $code = $match.Groups[1].Value }
        }
        if ([string]::IsNullOrWhiteSpace($code)) { Start-Sleep -Milliseconds 100 }
    }
    Assert-True ($code -match '^[0-9]{6}$') 'Development server OTP diagnostic was not emitted.'

    $statePath = Join-Path $stateDir 'server_state.json'
    $stateBefore = Get-Content -LiteralPath $statePath -Raw
    Assert-True (-not $stateBefore.Contains($code)) 'Plaintext OTP was persisted in server state.'

    $wrongCode = if ($code -eq '000000') { '000001' } else { '000000' }
    Assert-HttpFailure {
        Invoke-Json $baseUrl '/v1/customer-phone-verification/verify' @{
            challenge_id = $challenge
            code = $wrongCode
        }
    } @(401)

    $verified = Invoke-Json $baseUrl '/v1/customer-phone-verification/verify' @{
        challenge_id = $challenge
        code = $code
    }
    Assert-True (([string]$verified.status) -eq 'VERIFIED') 'OTP verify did not return VERIFIED.'
    $token = [string]$verified.verification_token
    Assert-True ($token.Length -ge 32) 'Verification token is missing or too short.'
    Assert-True (([string]$verified.phone) -eq $phone) 'Verified phone binding changed.'

    $stateVerified = Get-Content -LiteralPath $statePath -Raw
    Assert-True (-not $stateVerified.Contains($code)) 'OTP remained in server state after verification.'
    Assert-True (-not $stateVerified.Contains($token)) 'Plaintext verification token was persisted.'

    $consumed = Invoke-Json $baseUrl '/v1/customer-phone-verification/consume' @{
        challenge_id = $challenge
        phone = $phone
        verification_token = $token
    }
    Assert-True (([string]$consumed.status) -eq 'CONSUMED') 'Verification token was not consumed.'

    Assert-HttpFailure {
        Invoke-Json $baseUrl '/v1/customer-phone-verification/consume' @{
            challenge_id = $challenge
            phone = $phone
            verification_token = $token
        }
    } @(409)

    Write-Host 'P02 CUSTOMER PHONE OTP INTEGRATION: PASS' -ForegroundColor Green
    Write-Host 'OTP generated: SERVER ONLY'
    Write-Host 'OTP API leakage: NO'
    Write-Host 'OTP plaintext at rest: NO'
    Write-Host 'Verification token plaintext at rest: NO'
    Write-Host 'One-time consume: PASS'
} finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        try { $proc.WaitForExit(3000) | Out-Null } catch {}
    }
    Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
