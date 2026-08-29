param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Fail([string]$Message) {
    throw "[SEC.015C1 SELF-TEST] $Message"
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { Fail $Message }
}

function ConvertFrom-Base32([string]$Text) {
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
    $bits = New-Object System.Text.StringBuilder
    foreach ($ch in $Text.Trim().TrimEnd('=').ToUpperInvariant().ToCharArray()) {
        $idx = $alphabet.IndexOf([string]$ch)
        if ($idx -lt 0) { Fail "Invalid Base32 character: $ch" }
        [void]$bits.Append([Convert]::ToString($idx, 2).PadLeft(5, '0'))
    }
    $bytes = New-Object System.Collections.Generic.List[byte]
    for ($i = 0; $i + 8 -le $bits.Length; $i += 8) {
        $bytes.Add([Convert]::ToByte($bits.ToString($i, 8), 2))
    }
    return $bytes.ToArray()
}

function Get-TotpCode([byte[]]$Secret, [int]$StepOffset = 0) {
    $unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    [Int64]$counter = [Math]::Floor($unix / 30) + $StepOffset
    $counterBytes = [BitConverter]::GetBytes($counter)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($counterBytes) }
    $hmac = New-Object System.Security.Cryptography.HMACSHA1
    $hmac.Key = $Secret
    try { $digest = $hmac.ComputeHash($counterBytes) } finally { $hmac.Dispose() }
    $offset = [int]($digest[$digest.Length - 1] -band 0x0F)
    $binary = (([int]($digest[$offset] -band 0x7F)) -shl 24) -bor
              (([int]$digest[$offset + 1]) -shl 16) -bor
              (([int]$digest[$offset + 2]) -shl 8) -bor
              ([int]$digest[$offset + 3])
    return ($binary % 1000000).ToString('D6')
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
        if ($Process.HasExited) {
            Fail "Local development server exited before ready."
        }
        Start-Sleep -Milliseconds 250
        $Process.Refresh()
    }
    Fail "Timed out waiting for local development server."
}

function Start-LocalServer(
    [string]$ServerScript,
    [string]$Email,
    [int]$Port,
    [string]$StateDir,
    [string]$Stdout,
    [string]$Stderr
) {
    Remove-Item -LiteralPath (Join-Path $StateDir 'server_ready.txt') -Force -ErrorAction SilentlyContinue
    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$ServerScript`" -AdminEmail `"$Email`" -Port $Port -StateDir `"$StateDir`""
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr
    Wait-Ready (Join-Path $StateDir 'server_ready.txt') $proc
    return $proc
}

function Stop-LocalServer($Process) {
    if ($null -ne $Process -and -not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        try { $Process.WaitForExit(3000) | Out-Null } catch {}
    }
}

function New-Session {
    return New-Object Microsoft.PowerShell.Commands.WebRequestSession
}

function Invoke-Json(
    [string]$BaseUrl,
    [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
    [string]$Method,
    [string]$Path,
    $Body = $null,
    [string]$Csrf = ''
) {
    $params = @{
        Uri = "$BaseUrl$Path"
        Method = $Method
        WebSession = $Session
        UseBasicParsing = $true
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $params.ContentType = 'application/json; charset=utf-8'
        $params.Body = ($Body | ConvertTo-Json -Depth 12 -Compress)
    }
    if (-not [string]::IsNullOrWhiteSpace($Csrf)) {
        $params.Headers = @{ 'X-Yalla-CSRF' = $Csrf }
    }
    return Invoke-RestMethod @params
}

function Login-Admin(
    [string]$BaseUrl,
    [string]$Email,
    [string]$Password,
    [byte[]]$TotpSecret
) {
    $session = New-Session
    $login = Invoke-Json $BaseUrl $session 'POST' '/v1/control-center/auth/login' @{
        email = $Email
        password = $Password
    }
    Assert-True (([string]$login.status) -eq 'MFA_REQUIRED') 'Login did not request MFA.'
    $verify = Invoke-Json $BaseUrl $session 'POST' '/v1/control-center/auth/mfa/verify' @{
        challenge_id = [string]$login.challenge_id
        method = 'TOTP'
        proof = @{ code = (Get-TotpCode $TotpSecret) }
    }
    Assert-True (([string]$verify.status) -eq 'AUTHENTICATED') 'MFA verification did not authenticate.'
    $csrf = [string]$verify.csrf_token
    Assert-True (-not [string]::IsNullOrWhiteSpace($csrf)) 'CSRF token missing after MFA.'
    return [pscustomobject]@{ Session=$session; Csrf=$csrf }
}

function Invoke-Action(
    [string]$BaseUrl,
    $Auth,
    [string]$ActionCode,
    [string]$OrganizationId,
    [string]$EntityType,
    [string]$EntityId,
    [hashtable]$RequestedState = @{}
) {
    return Invoke-Json $BaseUrl $Auth.Session 'POST' '/v1/control-center/actions' @{
        action_code = $ActionCode
        organization_id = $OrganizationId
        target_entity_type = $EntityType
        target_entity_id = $EntityId
        reason = "SEC.015C1 gated integration test: $ActionCode"
        requested_state = $RequestedState
    } $Auth.Csrf
}

function Get-Subscription([string]$BaseUrl, $Auth, [string]$SubscriptionId) {
    $payload = Invoke-Json $BaseUrl $Auth.Session 'GET' '/v1/control-center/subscriptions'
    return @($payload.items) | Where-Object { [string]$_.subscription_id -eq $SubscriptionId } | Select-Object -First 1
}

function Get-Device([string]$BaseUrl, $Auth, [string]$DeviceId) {
    $payload = Invoke-Json $BaseUrl $Auth.Session 'GET' '/v1/control-center/devices'
    return @($payload.items) | Where-Object { [string]$_.device_id -eq $DeviceId } | Select-Object -First 1
}

$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$serverScript = Join-Path $ProjectPath 'tools\sec015a\dev_yalla_admin_server.ps1'
if (-not (Test-Path -LiteralPath $serverScript)) { Fail "Server script not found: $serverScript" }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$downloads = Join-Path $env:USERPROFILE 'Downloads'
$stateDir = Join-Path $downloads "Yalla_SEC015C1_SELFTEST_STATE_$stamp"
$resultPath = Join-Path $downloads "Yalla_SEC015C1_SELFTEST_RESULT_$stamp.txt"
$stdout = Join-Path $stateDir 'server_stdout.txt'
$stderr = Join-Path $stateDir 'server_stderr.txt'
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

$email = 'sec015c1.selftest@yalla.local'
$password = 'Sec015C1!Integration2026'
$port = Get-FreePort
$baseUrl = "http://127.0.0.1:$port"
$proc = $null
$totpSecret = $null
$orgId = ''
$subId = ''
$deviceId = "DEV-SEC015C1-$stamp"

try {
    Write-Host '[SEC.015C1 SELF-TEST] Starting isolated local server...' -ForegroundColor Cyan
    $proc = Start-LocalServer $serverScript $email $port $stateDir $stdout $stderr

    $enrollmentFile = Join-Path $stateDir 'Yalla_LOCAL_SUPER_OWNER_ENROLLMENT.txt'
    Assert-True (Test-Path -LiteralPath $enrollmentFile) 'Enrollment file was not generated.'
    $secretLine = Get-Content -LiteralPath $enrollmentFile | Where-Object { $_ -like 'Enrollment Secret:*' } | Select-Object -First 1
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$secretLine)) 'Enrollment secret line missing.'
    $enrollmentSecret = ([string]$secretLine).Substring(([string]$secretLine).IndexOf(':') + 1).Trim()

    $enrollSession = New-Session
    $start = Invoke-Json $baseUrl $enrollSession 'POST' '/v1/control-center/auth/enrollment/start' @{
        email = $email
        enrollment_secret = $enrollmentSecret
    }
    # Windows PowerShell 5.1 can return the JSON string correctly while a terse
    # cast/member expression makes the URI extraction brittle. Read the named
    # property explicitly, parse the query deterministically, and fall back to
    # the LOCAL DEVELOPMENT server's intentional enrollment diagnostic only.
    $uri = ''
    $uriProperty = $start.PSObject.Properties['totp_provisioning_uri']
    if ($null -ne $uriProperty -and $null -ne $uriProperty.Value) {
        $uri = [string]$uriProperty.Value
    }

    $base32Secret = ''
    if (-not [string]::IsNullOrWhiteSpace($uri)) {
        $secretMatch = [regex]::Match($uri, '(?:[?&])secret=([A-Za-z2-7]+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($secretMatch.Success) {
            $base32Secret = $secretMatch.Groups[1].Value.ToUpperInvariant()
        }
    }

    if ([string]::IsNullOrWhiteSpace($base32Secret)) {
        for ($i = 0; $i -lt 50 -and [string]::IsNullOrWhiteSpace($base32Secret); $i++) {
            if (Test-Path -LiteralPath $stdout) {
                $stdoutText = Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue
                if (-not [string]::IsNullOrWhiteSpace($stdoutText)) {
                    $stdoutMatch = [regex]::Match(
                        $stdoutText,
                        '(?im)^\[ENROLLMENT\] TOTP secret for Authenticator:\s*([A-Z2-7]+)\s*$'
                    )
                    if ($stdoutMatch.Success) {
                        $base32Secret = $stdoutMatch.Groups[1].Value.ToUpperInvariant()
                    }
                }
            }
            if ([string]::IsNullOrWhiteSpace($base32Secret)) { Start-Sleep -Milliseconds 100 }
        }
    }

    Assert-True (-not [string]::IsNullOrWhiteSpace($base32Secret)) 'TOTP provisioning secret missing from enrollment response and local development diagnostic.'
    $totpSecret = ConvertFrom-Base32 $base32Secret

    $complete = Invoke-Json $baseUrl $enrollSession 'POST' '/v1/control-center/auth/enrollment/complete' @{
        challenge_id = [string]$start.challenge_id
        new_password = $password
        mfa_method = 'TOTP'
        mfa_proof = @{ code = (Get-TotpCode $totpSecret) }
    }
    Assert-True (([string]$complete.status) -eq 'ENROLLED') 'Enrollment did not complete.'

    $auth = Login-Admin $baseUrl $email $password $totpSecret
    $created = Invoke-Json $baseUrl $auth.Session 'POST' '/v1/control-center/customer-onboarding/create' @{
        organization_name = 'SEC015C1 Integration Workshop'
        owner_email = 'owner.sec015c1@example.test'
        country_code = 'PS'
        plan_code = 'LOCAL_PRO'
        max_users = 5
        max_devices = 2
        trial_days = 14
    } $auth.Csrf
    $orgId = [string]$created.organization_id
    $subId = [string]$created.subscription_id
    Assert-True (-not [string]::IsNullOrWhiteSpace($orgId)) 'Organization ID missing after provisioning.'
    Assert-True (-not [string]::IsNullOrWhiteSpace($subId)) 'Subscription ID missing after provisioning.'

    $sub = Get-Subscription $baseUrl $auth $subId
    Assert-True (([string]$sub.status) -eq 'TRIAL') 'Cycle did not start at TRIAL.'

    [void](Invoke-Action $baseUrl $auth 'SUBSCRIPTION.ACTIVATE' $orgId 'subscription' $subId)
    $sub = Get-Subscription $baseUrl $auth $subId
    Assert-True (([string]$sub.status) -eq 'ACTIVE') 'TRIAL -> ACTIVE failed.'
    $beforeExtend = [DateTimeOffset]::Parse([string]$sub.expires_at)

    [void](Invoke-Action $baseUrl $auth 'SUBSCRIPTION.EXTEND' $orgId 'subscription' $subId @{ extension_days = 21 })
    $sub = Get-Subscription $baseUrl $auth $subId
    $afterExtend = [DateTimeOffset]::Parse([string]$sub.expires_at)
    Assert-True ($afterExtend -gt $beforeExtend) 'ACTIVE -> EXTENDED period failed.'
    Assert-True ([int]$sub.last_period_extension_days -eq 21) 'Extension days were not persisted.'

    [void](Invoke-Action $baseUrl $auth 'SUBSCRIPTION.MARK_PAID' $orgId 'subscription' $subId)
    $sub = Get-Subscription $baseUrl $auth $subId
    Assert-True (([string]$sub.billing_status) -eq 'PAID') 'Mark Paid failed.'

    [void](Invoke-Action $baseUrl $auth 'SUBSCRIPTION.MARK_UNPAID' $orgId 'subscription' $subId)
    $sub = Get-Subscription $baseUrl $auth $subId
    Assert-True (([string]$sub.billing_status) -eq 'UNPAID') 'Mark Unpaid failed.'

    [void](Invoke-Action $baseUrl $auth 'SUBSCRIPTION.SUSPEND' $orgId 'subscription' $subId)
    $sub = Get-Subscription $baseUrl $auth $subId
    Assert-True (([string]$sub.status) -eq 'SUSPENDED') 'ACTIVE -> FROZEN failed.'

    [void](Invoke-Action $baseUrl $auth 'SUBSCRIPTION.REACTIVATE' $orgId 'subscription' $subId)
    $sub = Get-Subscription $baseUrl $auth $subId
    Assert-True (([string]$sub.status) -eq 'ACTIVE') 'FROZEN -> REACTIVATED failed.'
    Assert-True ($null -ne $sub.remaining_days -and [int]$sub.remaining_days -gt 0) 'Remaining period projection failed.'

    $beforeRenew = [DateTimeOffset]::Parse([string]$sub.expires_at)
    [void](Invoke-Action $baseUrl $auth 'SUBSCRIPTION.RENEW' $orgId 'subscription' $subId @{ renewal_days = 365 })
    $sub = Get-Subscription $baseUrl $auth $subId
    $afterRenew = [DateTimeOffset]::Parse([string]$sub.expires_at)
    Assert-True ($afterRenew -gt $beforeRenew) 'Renewal did not extend expiry.'
    $renewals = Invoke-Json $baseUrl $auth.Session 'GET' '/v1/control-center/renewals'
    Assert-True (@($renewals.items | Where-Object { [string]$_.subscription_id -eq $subId }).Count -ge 1) 'Renewal record missing.'

    # Device creation belongs to the activation protocol, not C1. Seed one isolated
    # fixture into the local server state only so C1 can prove admin lifecycle over
    # a server-known device without inventing a customer activation flow.
    Stop-LocalServer $proc
    $proc = $null
    $statePath = Join-Path $stateDir 'server_state.json'
    $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $deviceFixture = [pscustomobject][ordered]@{
        device_id = $deviceId
        organization_id = $orgId
        display_name = 'SEC.015C1 isolated fixture'
        status = 'ACTIVE'
        activated_at = [DateTimeOffset]::UtcNow.ToString('o')
        deactivated_at = $null
        revoked_at = $null
        last_seen = [DateTimeOffset]::UtcNow.ToString('o')
        app_version = 'SELF_TEST'
        source = 'SEC015C1_ISOLATED_TEST_FIXTURE'
    }
    $state.devices = @($state.devices) + @($deviceFixture)
    $state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath -Encoding UTF8

    $port = Get-FreePort
    $baseUrl = "http://127.0.0.1:$port"
    $proc = Start-LocalServer $serverScript $email $port $stateDir $stdout $stderr
    $auth = Login-Admin $baseUrl $email $password $totpSecret

    $device = Get-Device $baseUrl $auth $deviceId
    Assert-True ($null -ne $device) 'Server-known device was not listed.'
    Assert-True (([string]$device.status) -eq 'ACTIVE') 'Fixture did not begin ACTIVE.'

    [void](Invoke-Action $baseUrl $auth 'DEVICE.DEACTIVATE' $orgId 'device' $deviceId)
    $device = Get-Device $baseUrl $auth $deviceId
    Assert-True (([string]$device.status) -eq 'SUSPENDED') 'Device deactivation failed.'

    [void](Invoke-Action $baseUrl $auth 'DEVICE.ACTIVATE' $orgId 'device' $deviceId)
    $device = Get-Device $baseUrl $auth $deviceId
    Assert-True (([string]$device.status) -eq 'ACTIVE') 'Device reactivation failed.'

    $audit = Invoke-Json $baseUrl $auth.Session 'GET' '/v1/control-center/audit-logs'
    foreach ($required in @(
        'SUBSCRIPTION.ACTIVATE',
        'SUBSCRIPTION.EXTEND',
        'SUBSCRIPTION.MARK_PAID',
        'SUBSCRIPTION.MARK_UNPAID',
        'SUBSCRIPTION.SUSPEND',
        'SUBSCRIPTION.REACTIVATE',
        'SUBSCRIPTION.RENEW',
        'DEVICE.DEACTIVATE',
        'DEVICE.ACTIVATE'
    )) {
        Assert-True (@($audit.items | Where-Object { [string]$_.action -eq $required }).Count -ge 1) "Audit entry missing for $required."
    }

    @(
        'YALLA ACCOUNTS - SEC.015C1 ISOLATED INTEGRATION SELF-TEST'
        "CompletedAt: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
        'Trial -> Active: PASS'
        'Active -> Extended: PASS'
        'Mark Paid: PASS'
        'Mark Unpaid: PASS'
        'Freeze: PASS'
        'Reactivation: PASS'
        'Renewal: PASS'
        'Remaining Period: PASS'
        'Device Listing: PASS'
        'Device Deactivation: PASS'
        'Device Activation: PASS'
        'Audit Presence: PASS'
        'Customer SQLite Access: NONE'
        'Result: PASS'
    ) | Set-Content -LiteralPath $resultPath -Encoding UTF8

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host 'SEC.015C1 ISOLATED INTEGRATION SELF-TEST - PASS' -ForegroundColor Green
    Write-Host 'Trial -> Active -> Extended -> Paid/Unpaid -> Frozen -> Reactivated: PASS'
    Write-Host 'Renewal + Remaining Period: PASS'
    Write-Host 'Device Listing + Deactivate/Activate: PASS'
    Write-Host "Result: $resultPath"
    Write-Host '============================================================' -ForegroundColor Green
}
finally {
    Stop-LocalServer $proc
    # Delete isolated credential/state material after the result has been written.
    Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
