param(
    [string]$AdminEmail = 'owner@yalla.local',
    [int]$Port = 8787,
    [string]$StateDir = "$env:USERPROFILE\Downloads\Yalla_Local_Admin_Dev"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# LOCAL_DEVELOPMENT_ONLY
# This harness exists only to exercise SEC.015 unified-login enrollment/login
# on 127.0.0.1 before the production licensing server is deployed.
# It is intentionally loopback-only and must never be exposed to a LAN/WAN.

function New-RandomBytes([int]$Count) {
    $bytes = New-Object byte[] $Count
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return $bytes
}

function ConvertTo-Base64Url([byte[]]$Bytes) {
    return ([Convert]::ToBase64String($Bytes).TrimEnd('=') -replace '\+', '-' -replace '/', '_')
}

function Get-Sha256Base64([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToBase64String($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)))
    } finally { $sha.Dispose() }
}

function Test-FixedString([string]$A, [string]$B) {
    if ($null -eq $A -or $null -eq $B -or $A.Length -ne $B.Length) { return $false }
    $diff = 0
    for ($i = 0; $i -lt $A.Length; $i++) {
        $diff = $diff -bor ([int][char]$A[$i] -bxor [int][char]$B[$i])
    }
    return $diff -eq 0
}

function New-PasswordRecord([string]$Password) {
    $salt = New-RandomBytes 16
    $iterations = 200000
    $pbkdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($Password, $salt, $iterations)
    try { $hash = $pbkdf.GetBytes(32) } finally { $pbkdf.Dispose() }
    return [ordered]@{
        algorithm = 'PBKDF2-HMAC-SHA1-DEV-ONLY'
        iterations = $iterations
        salt = [Convert]::ToBase64String($salt)
        hash = [Convert]::ToBase64String($hash)
    }
}

function Test-Password([string]$Password, $Record) {
    if ($null -eq $Record) { return $false }
    $salt = [Convert]::FromBase64String([string]$Record.salt)
    $iterations = [int]$Record.iterations
    $pbkdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($Password, $salt, $iterations)
    try { $hash = [Convert]::ToBase64String($pbkdf.GetBytes(32)) } finally { $pbkdf.Dispose() }
    return (Test-FixedString $hash ([string]$Record.hash))
}

function Protect-LocalText([string]$Text) {
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
    $plain = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $protected = [System.Security.Cryptography.ProtectedData]::Protect(
        $plain,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [Convert]::ToBase64String($protected)
}

function Unprotect-LocalText([string]$CipherText) {
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
    $protected = [Convert]::FromBase64String($CipherText)
    $plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $protected,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [System.Text.Encoding]::UTF8.GetString($plain)
}

function ConvertTo-Base32([byte[]]$Bytes) {
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
    $bits = (($Bytes | ForEach-Object { [Convert]::ToString([int]$_, 2).PadLeft(8, '0') }) -join '')
    while (($bits.Length % 5) -ne 0) { $bits += '0' }
    $result = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $bits.Length; $i += 5) {
        $index = [Convert]::ToInt32($bits.Substring($i, 5), 2)
        [void]$result.Append($alphabet[$index])
    }
    return $result.ToString()
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
    $binary = (([int]($digest[$offset] -band 0x7F)) -shl 24) -bor (([int]$digest[$offset + 1]) -shl 16) -bor (([int]$digest[$offset + 2]) -shl 8) -bor ([int]$digest[$offset + 3])
    $code = $binary % 1000000
    return $code.ToString('D6')
}

function Test-Totp([byte[]]$Secret, [string]$Code) {
    $candidate = ($Code -replace '\s', '')
    if ($candidate -notmatch '^\d{6}$') { return $false }
    foreach ($offset in -1, 0, 1) {
        if (Test-FixedString (Get-TotpCode $Secret $offset) $candidate) { return $true }
    }
    return $false
}

function Get-RequestJson($Request) {
    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    try { $raw = $reader.ReadToEnd() } finally { $reader.Dispose() }
    if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]@{} }
    return $raw | ConvertFrom-Json
}

function Send-Json($Context, [int]$StatusCode, $Payload, [string[]]$SetCookies = @()) {
    $json = $Payload | ConvertTo-Json -Depth 12 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = 'application/json; charset=utf-8'
    foreach ($cookie in $SetCookies) { $Context.Response.AppendHeader('Set-Cookie', $cookie) }
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.OutputStream.Close()
}

function Get-SessionToken($Request) {
    $cookie = $Request.Cookies['yalla_admin_session']
    if ($null -eq $cookie) { return '' }
    return [string]$cookie.Value
}

function Require-Session($Context, [switch]$RequireCsrf) {
    $token = Get-SessionToken $Context.Request
    if ([string]::IsNullOrWhiteSpace($token) -or -not $script:Sessions.ContainsKey($token)) {
        Send-Json $Context 401 @{ message = 'Administrative session is not authenticated.' }
        return $null
    }
    $session = $script:Sessions[$token]
    if ([DateTimeOffset]::UtcNow -gt $session.expires_at) {
        $script:Sessions.Remove($token)
        Send-Json $Context 401 @{ message = 'Administrative session expired.' }
        return $null
    }
    if ($RequireCsrf) {
        $csrf = [string]$Context.Request.Headers['X-Yalla-CSRF']
        if (-not (Test-FixedString $csrf ([string]$session.csrf))) {
            Send-Json $Context 403 @{ message = 'CSRF validation failed.' }
            return $null
        }
    }
    return $session
}

function Save-State {
    $script:State | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:StatePath -Encoding UTF8
}

function Ensure-StateCollection([string]$Name) {
    if ($null -eq $script:State.PSObject.Properties[$Name]) {
        $script:State | Add-Member -NotePropertyName $Name -NotePropertyValue @()
    }
}


function Set-StateProperty($Object, [string]$Name, $Value) {
    if ($null -eq $Object) { return }
    if ($null -eq $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    } else {
        $Object.$Name = $Value
    }
}

function Get-StateProperty($Object, [string]$Name, $DefaultValue = $null) {
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $DefaultValue
    }
    return $Object.$Name
}

function Get-RequestedInt($RequestedState, [string]$Name, [int]$DefaultValue = 0) {
    if ($null -eq $RequestedState -or $null -eq $RequestedState.PSObject.Properties[$Name]) {
        return $DefaultValue
    }
    $raw = $RequestedState.$Name
    $parsed = 0
    if ([int]::TryParse([string]$raw, [ref]$parsed)) { return $parsed }
    return $DefaultValue
}

function Get-RemainingPeriod($Subscription) {
    $now = [DateTimeOffset]::UtcNow
    if ($null -eq $Subscription -or [string]::IsNullOrWhiteSpace([string]$Subscription.expires_at)) {
        return [ordered]@{
            remaining_days = $null
            remaining_hours = $null
            remaining_seconds = $null
            expires_at = $null
        }
    }
    try {
        $expiry = [DateTimeOffset]::Parse([string]$Subscription.expires_at)
        $seconds = [Math]::Max(0, [Math]::Floor(($expiry - $now).TotalSeconds))
        return [ordered]@{
            remaining_days = [Math]::Floor($seconds / 86400)
            remaining_hours = [Math]::Floor($seconds / 3600)
            remaining_seconds = $seconds
            expires_at = $expiry.ToString('o')
        }
    } catch {
        return [ordered]@{
            remaining_days = $null
            remaining_hours = $null
            remaining_seconds = $null
            expires_at = [string]$Subscription.expires_at
        }
    }
}

function Find-Subscription([string]$OrganizationId, [string]$SubscriptionId = '') {
    Ensure-StateCollection 'subscriptions'
    if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
        return @($script:State.subscriptions) | Where-Object { [string]$_.subscription_id -eq $SubscriptionId } | Select-Object -First 1
    }
    return @($script:State.subscriptions) | Where-Object { [string]$_.organization_id -eq $OrganizationId } | Select-Object -Last 1
}

function Find-Device([string]$OrganizationId, [string]$DeviceId = '') {
    Ensure-StateCollection 'devices'
    if (-not [string]::IsNullOrWhiteSpace($DeviceId)) {
        return @($script:State.devices) | Where-Object {
            $candidateId = [string](Get-StateProperty $_ 'device_id' (Get-StateProperty $_ 'id' ''))
            $candidateId -eq $DeviceId
        } | Select-Object -First 1
    }
    return @($script:State.devices) | Where-Object { [string](Get-StateProperty $_ 'organization_id' '') -eq $OrganizationId } | Select-Object -First 1
}

function Add-RenewalRecord($Subscription, [DateTimeOffset]$PreviousExpiry, [DateTimeOffset]$NewExpiry) {
    Ensure-StateCollection 'renewals'
    $row = [ordered]@{
        renewal_id = New-LocalId 'REN'
        organization_id = [string]$Subscription.organization_id
        subscription_id = [string]$Subscription.subscription_id
        previous_expires_at = $PreviousExpiry.ToString('o')
        new_expires_at = $NewExpiry.ToString('o')
        renewed_at = [DateTimeOffset]::UtcNow.ToString('o')
        status = 'COMPLETED'
        environment = 'LOCAL_DEVELOPMENT_ONLY'
    }
    $script:State.renewals = @($script:State.renewals) + @($row)
    return $row
}

function New-LocalId([string]$Prefix) {
    return "$Prefix-$([guid]::NewGuid().ToString('N').Substring(0,12).ToUpperInvariant())"
}

function Add-Audit([string]$Action, [string]$EntityType, [string]$EntityId, [string]$Detail) {
    Ensure-StateCollection 'audit_logs'
    $row = [ordered]@{
        audit_id = New-LocalId 'AUD'
        at = [DateTimeOffset]::UtcNow.ToString('o')
        actor = $AdminEmail
        action = $Action
        entity_type = $EntityType
        entity_id = $EntityId
        detail = $Detail
        environment = 'LOCAL_DEVELOPMENT_ONLY'
    }
    $script:State.audit_logs = @($script:State.audit_logs) + @($row)
}

function Add-SecurityEvent([string]$Code, [string]$Detail) {
    Ensure-StateCollection 'security_events'
    $row = [ordered]@{
        event_id = New-LocalId 'SEC'
        at = [DateTimeOffset]::UtcNow.ToString('o')
        code = $Code
        detail = $Detail
        admin_email = $AdminEmail
        environment = 'LOCAL_DEVELOPMENT_ONLY'
    }
    $script:State.security_events = @($script:State.security_events) + @($row)
}

function New-ActivationCode {
    $raw = ConvertTo-Base64Url (New-RandomBytes 18)
    return ('YLA-' + $raw.ToUpperInvariant())
}

function New-CustomerProvision(
    [string]$OrganizationName,
    [string]$OwnerEmail,
    [string]$CountryCode,
    [string]$PlanCode,
    [int]$MaxUsers,
    [int]$MaxDevices,
    [int]$TrialDays,
    [string]$SourceRequestId = ''
) {
    foreach ($name in @('organizations','subscriptions','licenses','entitlements','activations','renewals','overrides','devices')) {
        Ensure-StateCollection $name
    }
    $now = [DateTimeOffset]::UtcNow
    $orgId = New-LocalId 'ORG'
    $subscriptionId = New-LocalId 'SUB'
    $licenseId = New-LocalId 'LIC'
    $activationId = New-LocalId 'ACT'
    $activationCode = New-ActivationCode
    $status = if ($TrialDays -gt 0) { 'TRIAL' } else { 'ACTIVE' }
    $expiry = if ($TrialDays -gt 0) { $now.AddDays($TrialDays).ToString('o') } else { $now.AddYears(1).ToString('o') }
    $billingStatus = if ($TrialDays -gt 0) { 'TRIAL' } else { 'UNPAID' }

    $organization = [ordered]@{
        organization_id = $orgId
        name = $OrganizationName
        owner_email = $OwnerEmail
        country_code = $CountryCode
        status = 'ACTIVE'
        created_at = $now.ToString('o')
        source_request_id = if ([string]::IsNullOrWhiteSpace($SourceRequestId)) { $null } else { $SourceRequestId }
    }
    $subscription = [ordered]@{
        subscription_id = $subscriptionId
        organization_id = $orgId
        plan_code = $PlanCode
        status = $status
        started_at = $now.ToString('o')
        expires_at = $expiry
        max_users = [Math]::Max(1,$MaxUsers)
        max_devices = [Math]::Max(1,$MaxDevices)
        billing_status = $billingStatus
        paid_at = $null
        unpaid_at = if ($billingStatus -eq 'UNPAID') { $now.ToString('o') } else { $null }
        status_changed_at = $now.ToString('o')
        last_period_extension_days = 0
    }
    $license = [ordered]@{
        license_id = $licenseId
        organization_id = $orgId
        subscription_id = $subscriptionId
        status = 'PENDING_ACTIVATION'
        issued_at = $now.ToString('o')
    }
    $entitlement = [ordered]@{
        entitlement_id = New-LocalId 'ENT'
        organization_id = $orgId
        max_users = [Math]::Max(1,$MaxUsers)
        max_devices = [Math]::Max(1,$MaxDevices)
        source = 'LOCAL_CONTROL_CENTER'
    }
    $activation = [ordered]@{
        activation_id = $activationId
        organization_id = $orgId
        license_id = $licenseId
        status = 'ISSUED'
        issued_at = $now.ToString('o')
        redeemed_at = $null
        code_hash = Get-Sha256Base64 $activationCode
    }

    $script:State.organizations = @($script:State.organizations) + @($organization)
    $script:State.subscriptions = @($script:State.subscriptions) + @($subscription)
    $script:State.licenses = @($script:State.licenses) + @($license)
    $script:State.entitlements = @($script:State.entitlements) + @($entitlement)
    $script:State.activations = @($script:State.activations) + @($activation)
    Add-Audit 'CUSTOMER.PROVISION' 'organization' $orgId "Provisioned $OrganizationName / $OwnerEmail"
    Save-State

    return [ordered]@{
        status = 'PROVISIONED'
        organization_id = $orgId
        subscription_id = $subscriptionId
        license_id = $licenseId
        activation_id = $activationId
        activation_code = $activationCode
        owner_email = $OwnerEmail
        environment = 'LOCAL_DEVELOPMENT_ONLY'
    }
}

New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$script:StatePath = Join-Path $StateDir 'server_state.json'
$EnrollmentPath = Join-Path $StateDir 'Yalla_LOCAL_SUPER_OWNER_ENROLLMENT.txt'
$ReadyPath = Join-Path $StateDir 'server_ready.txt'
Remove-Item -LiteralPath $ReadyPath -Force -ErrorAction SilentlyContinue

$AdminEmail = $AdminEmail.Trim().ToLowerInvariant()
if ($AdminEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
    throw 'AdminEmail must be a valid email address.'
}

if (Test-Path -LiteralPath $script:StatePath) {
    $script:State = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
    $AdminEmail = ([string]$script:State.email).ToLowerInvariant()
} else {
    $enrollmentSecret = ConvertTo-Base64Url (New-RandomBytes 24)
    $script:State = [pscustomobject][ordered]@{
        version = 1
        environment = 'LOCAL_DEVELOPMENT_ONLY'
        email = $AdminEmail
        enrolled = $false
        enrollment_secret_hash = Get-Sha256Base64 $enrollmentSecret
        password = $null
        totp_secret_dpapi = $null
        created_at = [DateTimeOffset]::UtcNow.ToString('o')
        enrolled_at = $null
    }
    Save-State
    @(
        'Yalla Accounts - LOCAL DEVELOPMENT Super Owner Enrollment'
        '==========================================================='
        'THIS IS NOT A PRODUCTION LICENSING SERVER.'
        ''
        "Server URL: http://127.0.0.1:$Port/"
        "Admin email: $AdminEmail"
        "Enrollment Secret: $enrollmentSecret"
        ''
        'Use these values in the app: First Yalla Admin Enrollment'
        'The Enrollment Secret is one-time. Choose your own password in the app.'
    ) | Set-Content -LiteralPath $EnrollmentPath -Encoding UTF8
}


foreach ($name in @(
    'organizations','onboarding_requests','subscriptions','licenses','devices',
    'plans','features','entitlements','activations','renewals','overrides',
    'security_events','audit_logs'
)) {
    Ensure-StateCollection $name
}

# SEC.015C1 local development state evolution. This is server-side state only;
# it never touches the customer SQLite database.
$stateEvolved = $false
foreach ($sub in @($script:State.subscriptions)) {
    if ($null -eq $sub.PSObject.Properties['billing_status']) {
        $defaultBilling = if ([string]$sub.status -eq 'TRIAL') { 'TRIAL' } else { 'UNPAID' }
        Set-StateProperty $sub 'billing_status' $defaultBilling
        $stateEvolved = $true
    }
    if ($null -eq $sub.PSObject.Properties['paid_at']) {
        Set-StateProperty $sub 'paid_at' $null
        $stateEvolved = $true
    }
    if ($null -eq $sub.PSObject.Properties['unpaid_at']) {
        Set-StateProperty $sub 'unpaid_at' $null
        $stateEvolved = $true
    }
    if ($null -eq $sub.PSObject.Properties['status_changed_at']) {
        Set-StateProperty $sub 'status_changed_at' ([DateTimeOffset]::UtcNow.ToString('o'))
        $stateEvolved = $true
    }
    if ($null -eq $sub.PSObject.Properties['last_period_extension_days']) {
        Set-StateProperty $sub 'last_period_extension_days' 0
        $stateEvolved = $true
    }
}
foreach ($device in @($script:State.devices)) {
    foreach ($field in @('activated_at','deactivated_at','revoked_at','last_seen','app_version','display_name')) {
        if ($null -eq $device.PSObject.Properties[$field]) {
            Set-StateProperty $device $field $null
            $stateEvolved = $true
        }
    }
    if ($null -eq $device.PSObject.Properties['device_id']) {
        $fallbackDeviceId = [string](Get-StateProperty $device 'id' '')
        if (-not [string]::IsNullOrWhiteSpace($fallbackDeviceId)) {
            Set-StateProperty $device 'device_id' $fallbackDeviceId
            $stateEvolved = $true
        }
    }
    if ($null -eq $device.PSObject.Properties['status_changed_at']) {
        Set-StateProperty $device 'status_changed_at' ([DateTimeOffset]::UtcNow.ToString('o'))
        $stateEvolved = $true
    }
}
if ($stateEvolved) { Save-State }

if (@($script:State.plans).Count -eq 0) {
    $script:State.plans = @(
        [ordered]@{ plan_code='LOCAL_STARTER'; name='Starter'; status='ACTIVE'; environment='LOCAL_DEVELOPMENT_ONLY' },
        [ordered]@{ plan_code='LOCAL_PRO'; name='Pro'; status='ACTIVE'; environment='LOCAL_DEVELOPMENT_ONLY' },
        [ordered]@{ plan_code='LOCAL_BUSINESS'; name='Business'; status='ACTIVE'; environment='LOCAL_DEVELOPMENT_ONLY' }
    )
}
if (@($script:State.features).Count -eq 0) {
    $script:State.features = @(
        [ordered]@{ feature_code='ACCOUNTING'; name='Accounting'; status='ACTIVE' },
        [ordered]@{ feature_code='REPAIRS'; name='Repairs'; status='ACTIVE' },
        [ordered]@{ feature_code='INVENTORY'; name='Inventory & Purchases'; status='ACTIVE' },
        [ordered]@{ feature_code='EMPLOYEES'; name='Employees'; status='ACTIVE' },
        [ordered]@{ feature_code='INSURANCE'; name='Insurance'; status='ACTIVE' }
    )
}
Save-State

$script:EnrollmentChallenges = @{}
$script:LoginChallenges = @{}
$script:Sessions = @{}
$script:ReauthContexts = @{}
$script:BreakGlass = @{}

$listener = New-Object System.Net.HttpListener
$prefix = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($prefix)
$listener.Start()

@(
    'READY'
    "URL=$prefix"
    "EMAIL=$AdminEmail"
    "ENROLLED=$($script:State.enrolled)"
    'MODE=LOCAL_DEVELOPMENT_ONLY'
) | Set-Content -LiteralPath $ReadyPath -Encoding ASCII

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host '[YALLA LOCAL ADMIN DEV SERVER] READY' -ForegroundColor Green
Write-Host "URL: $prefix"
Write-Host "Admin: $AdminEmail"
Write-Host "State: $StateDir"
if (-not [bool]$script:State.enrolled) { Write-Host "Enrollment: $EnrollmentPath" -ForegroundColor Yellow }
Write-Host 'Loopback only. LOCAL DEVELOPMENT ONLY.' -ForegroundColor Yellow
Write-Host '============================================================' -ForegroundColor Green

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            $request = $context.Request
            $path = $request.Url.AbsolutePath.TrimEnd('/')
            if ([string]::IsNullOrEmpty($path)) { $path = '/' }
            $method = $request.HttpMethod.ToUpperInvariant()

            if ($method -eq 'GET' -and $path -eq '/health') {
                Send-Json $context 200 @{ status = 'ok'; environment = 'LOCAL_DEVELOPMENT_ONLY'; enrolled = [bool]$script:State.enrolled }
                continue
            }


            if ($method -eq 'POST' -and $path -eq '/v1/customer-onboarding/request') {
                $body = Get-RequestJson $request
                $orgName = ([string]$body.organization_name).Trim()
                $ownerName = ([string]$body.owner_name).Trim()
                $ownerEmail = ([string]$body.owner_email).Trim().ToLowerInvariant()
                if ($orgName.Length -lt 2 -or $ownerName.Length -lt 2 -or $ownerEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
                    Send-Json $context 400 @{ message = 'Organization name, owner name and a valid email are required.' }
                    continue
                }
                Ensure-StateCollection 'onboarding_requests'
                $requestId = New-LocalId 'REQ'
                $row = [ordered]@{
                    request_id = $requestId
                    organization_name = $orgName
                    owner_name = $ownerName
                    owner_email = $ownerEmail
                    phone = [string]$body.phone
                    country_code = ([string]$body.country_code).ToUpperInvariant()
                    status = 'PENDING'
                    submitted_at = [DateTimeOffset]::UtcNow.ToString('o')
                    reviewed_at = $null
                    reviewed_by = $null
                    organization_id = $null
                }
                $script:State.onboarding_requests = @($script:State.onboarding_requests) + @($row)
                Add-Audit 'ONBOARDING.REQUEST' 'onboarding_request' $requestId "Self-service request: $orgName"
                Save-State
                Send-Json $context 201 @{ status='PENDING'; request_id=$requestId; message='Request submitted for Yalla review.' }
                continue
            }

            if ($method -eq 'POST' -and $path -eq '/v1/control-center/auth/enrollment/start') {
                if ([bool]$script:State.enrolled) {
                    Send-Json $context 409 @{ message = 'The local Super Owner identity is already enrolled.' }
                    continue
                }
                $body = Get-RequestJson $request
                $email = ([string]$body.email).Trim().ToLowerInvariant()
                $secret = [string]$body.enrollment_secret
                if ($email -ne $AdminEmail -or -not (Test-FixedString (Get-Sha256Base64 $secret) ([string]$script:State.enrollment_secret_hash))) {
                    Send-Json $context 403 @{ message = 'Enrollment identity or one-time secret is invalid.' }
                    continue
                }
                $challengeId = ConvertTo-Base64Url (New-RandomBytes 24)
                $totpSecret = New-RandomBytes 20
                $script:EnrollmentChallenges[$challengeId] = [pscustomobject]@{
                    email = $AdminEmail
                    totp_secret = $totpSecret
                    expires_at = [DateTimeOffset]::UtcNow.AddMinutes(10)
                }
                $base32 = ConvertTo-Base32 $totpSecret
                $label = [Uri]::EscapeDataString("Yalla Accounts:$AdminEmail")
                $issuer = [Uri]::EscapeDataString('Yalla Accounts')
                $uri = "otpauth://totp/$label?secret=$base32&issuer=$issuer&digits=6&period=30"
                Write-Host "[ENROLLMENT] TOTP secret for Authenticator: $base32" -ForegroundColor Cyan
                Write-Host "[ENROLLMENT] Current TOTP code: $(Get-TotpCode $totpSecret)" -ForegroundColor Cyan
                Send-Json $context 200 @{ challenge_id = $challengeId; totp_provisioning_uri = $uri }
                continue
            }

            if ($method -eq 'POST' -and $path -eq '/v1/control-center/auth/enrollment/complete') {
                $body = Get-RequestJson $request
                $challengeId = [string]$body.challenge_id
                if (-not $script:EnrollmentChallenges.ContainsKey($challengeId)) {
                    Send-Json $context 400 @{ message = 'Enrollment challenge is invalid or expired.' }
                    continue
                }
                $challenge = $script:EnrollmentChallenges[$challengeId]
                if ([DateTimeOffset]::UtcNow -gt $challenge.expires_at) {
                    $script:EnrollmentChallenges.Remove($challengeId)
                    Send-Json $context 400 @{ message = 'Enrollment challenge expired.' }
                    continue
                }
                $password = [string]$body.new_password
                if ($password.Length -lt 10) {
                    Send-Json $context 400 @{ message = 'Password must contain at least 10 characters.' }
                    continue
                }
                $proof = $body.mfa_proof
                $code = if ($null -ne $proof) { [string]$proof.code } else { '' }
                if (-not (Test-Totp $challenge.totp_secret $code)) {
                    Send-Json $context 403 @{ message = 'MFA code is invalid.' }
                    continue
                }
                $script:State.password = New-PasswordRecord $password
                $script:State.totp_secret_dpapi = Protect-LocalText ([Convert]::ToBase64String($challenge.totp_secret))
                $script:State.enrolled = $true
                $script:State.enrollment_secret_hash = $null
                $script:State.enrolled_at = [DateTimeOffset]::UtcNow.ToString('o')
                Save-State
                $script:EnrollmentChallenges.Remove($challengeId)
                @(
                    'Yalla Accounts - LOCAL DEVELOPMENT Super Owner'
                    '==============================================='
                    "Server URL: $prefix"
                    "Admin email: $AdminEmail"
                    'Status: ENROLLED'
                    'Password: the password you selected in the app (not stored here).'
                    'MFA: standard TOTP configured during enrollment.'
                    ''
                    'LOCAL DEVELOPMENT ONLY - production enrollment requires the deployed licensing server.'
                ) | Set-Content -LiteralPath $EnrollmentPath -Encoding UTF8
                Send-Json $context 200 @{ status = 'ENROLLED' }
                continue
            }

            if ($method -eq 'POST' -and $path -eq '/v1/control-center/auth/login') {
                $body = Get-RequestJson $request
                $email = ([string]$body.email).Trim().ToLowerInvariant()
                $password = [string]$body.password
                if (-not [bool]$script:State.enrolled -or $email -ne $AdminEmail -or -not (Test-Password $password $script:State.password)) {
                    Send-Json $context 401 @{ message = 'Invalid administrative credentials.' }
                    continue
                }
                $challengeId = ConvertTo-Base64Url (New-RandomBytes 24)
                $script:LoginChallenges[$challengeId] = [pscustomobject]@{
                    email = $AdminEmail
                    expires_at = [DateTimeOffset]::UtcNow.AddMinutes(5)
                }
                $loginSecretB64 = Unprotect-LocalText ([string]$script:State.totp_secret_dpapi)
                $loginSecret = [Convert]::FromBase64String($loginSecretB64)
                $loginUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                $loginRemaining = 30 - ([int]($loginUnix % 30))
                Write-Host "[LOGIN] Current TOTP code: $(Get-TotpCode $loginSecret)" -ForegroundColor Cyan
                Write-Host "[LOGIN] Valid for about: $loginRemaining second(s) (previous/current window accepted)" -ForegroundColor Yellow
                Send-Json $context 200 @{ status = 'MFA_REQUIRED'; challenge_id = $challengeId }
                continue
            }

            if ($method -eq 'POST' -and $path -eq '/v1/control-center/auth/mfa/verify') {
                $body = Get-RequestJson $request
                $challengeId = [string]$body.challenge_id
                if (-not $script:LoginChallenges.ContainsKey($challengeId)) {
                    Send-Json $context 401 @{ message = 'MFA challenge is invalid or expired.' }
                    continue
                }
                $challenge = $script:LoginChallenges[$challengeId]
                if ([DateTimeOffset]::UtcNow -gt $challenge.expires_at) {
                    $script:LoginChallenges.Remove($challengeId)
                    Send-Json $context 401 @{ message = 'MFA challenge expired.' }
                    continue
                }
                $secretB64 = Unprotect-LocalText ([string]$script:State.totp_secret_dpapi)
                $secret = [Convert]::FromBase64String($secretB64)
                $proof = $body.proof
                $code = if ($null -ne $proof) { [string]$proof.code } else { '' }
                if (-not (Test-Totp $secret $code)) {
                    $retryUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                    $retryRemaining = 30 - ([int]($retryUnix % 30))
                    Write-Host "[LOGIN] MFA rejected. Current TOTP code: $(Get-TotpCode $secret)" -ForegroundColor Red
                    Write-Host "[LOGIN] Valid for about: $retryRemaining second(s)" -ForegroundColor Yellow
                    Send-Json $context 401 @{ message = 'MFA code is invalid.' }
                    continue
                }
                $script:LoginChallenges.Remove($challengeId)
                $sessionToken = ConvertTo-Base64Url (New-RandomBytes 32)
                $csrf = ConvertTo-Base64Url (New-RandomBytes 24)
                $script:Sessions[$sessionToken] = [pscustomobject]@{
                    email = $AdminEmail
                    csrf = $csrf
                    created_at = [DateTimeOffset]::UtcNow
                    expires_at = [DateTimeOffset]::UtcNow.AddHours(12)
                }
                $cookie = "yalla_admin_session=$sessionToken; HttpOnly; SameSite=Strict; Path=/; Max-Age=43200"
                Add-SecurityEvent 'ADMIN.LOGIN.SUCCESS' 'Local Super Owner authenticated with password + TOTP.'
                Save-State
                Send-Json $context 200 @{ status = 'AUTHENTICATED'; csrf_token = $csrf } @($cookie)
                continue
            }

            if ($method -eq 'GET' -and $path -eq '/v1/control-center/auth/session') {
                $session = Require-Session $context
                if ($null -eq $session) { continue }
                Send-Json $context 200 @{
                    email = $AdminEmail
                    roles = @('YALLA_SUPER_OWNER')
                    permissions = @('YALLA_CONTROL_CENTER','YALLA_SUPER_OWNER','YALLA_BREAK_GLASS')
                    authentication_level = 'MFA'
                    csrf_token = $session.csrf
                }
                continue
            }

            if ($method -eq 'POST' -and $path -eq '/v1/control-center/auth/logout') {
                $session = Require-Session $context -RequireCsrf
                if ($null -eq $session) { continue }
                $token = Get-SessionToken $request
                $script:Sessions.Remove($token)
                $cookie = 'yalla_admin_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0'
                Send-Json $context 200 @{ status = 'LOGGED_OUT' } @($cookie)
                continue
            }

            if ($method -eq 'POST' -and $path -eq '/v1/control-center/auth/re-auth') {
                $session = Require-Session $context -RequireCsrf
                if ($null -eq $session) { continue }
                $body = Get-RequestJson $request
                if (-not (Test-Password ([string]$body.password) $script:State.password)) {
                    Send-Json $context 403 @{ message = 'Password reauthentication failed.' }
                    continue
                }
                $secret = [Convert]::FromBase64String((Unprotect-LocalText ([string]$script:State.totp_secret_dpapi)))
                $proof = $body.mfa_proof
                $code = if ($null -ne $proof) { [string]$proof.code } else { '' }
                if (-not (Test-Totp $secret $code)) {
                    Send-Json $context 403 @{ message = 'MFA reauthentication failed.' }
                    continue
                }
                $contextId = ConvertTo-Base64Url (New-RandomBytes 24)
                $script:ReauthContexts[$contextId] = [DateTimeOffset]::UtcNow.AddMinutes(5)
                Send-Json $context 200 @{ status = 'REAUTHENTICATED'; reauth_context_id = $contextId }
                continue
            }

            if ($method -eq 'POST' -and $path -eq '/v1/control-center/break-glass') {
                $session = Require-Session $context -RequireCsrf
                if ($null -eq $session) { continue }
                $body = Get-RequestJson $request
                $contextId = [string]$body.reauth_context_id
                if (-not $script:ReauthContexts.ContainsKey($contextId) -or [DateTimeOffset]::UtcNow -gt $script:ReauthContexts[$contextId]) {
                    Send-Json $context 403 @{ message = 'Fresh step-up reauthentication is required.' }
                    continue
                }
                $duration = [Math]::Max(5, [Math]::Min(60, [int]$body.duration_minutes))
                $grantId = ConvertTo-Base64Url (New-RandomBytes 18)
                $script:BreakGlass[$grantId] = [pscustomobject]@{
                    grant_id = $grantId
                    organization_id = [string]$body.organization_id
                    reason = [string]$body.reason
                    status = 'ACTIVE'
                    expires_at = [DateTimeOffset]::UtcNow.AddMinutes($duration).ToString('o')
                }
                Send-Json $context 200 $script:BreakGlass[$grantId]
                continue
            }


            if ($method -eq 'POST' -and $path -eq '/v1/control-center/customer-onboarding/create') {
                $session = Require-Session $context -RequireCsrf
                if ($null -eq $session) { continue }
                $body = Get-RequestJson $request
                $orgName = ([string]$body.organization_name).Trim()
                $ownerEmail = ([string]$body.owner_email).Trim().ToLowerInvariant()
                if ($orgName.Length -lt 2 -or $ownerEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
                    Send-Json $context 400 @{ message = 'Organization name and valid owner email are required.' }
                    continue
                }
                $result = New-CustomerProvision `
                    -OrganizationName $orgName `
                    -OwnerEmail $ownerEmail `
                    -CountryCode ([string]$body.country_code).ToUpperInvariant() `
                    -PlanCode ([string]$body.plan_code) `
                    -MaxUsers ([int]$body.max_users) `
                    -MaxDevices ([int]$body.max_devices) `
                    -TrialDays ([int]$body.trial_days)
                Send-Json $context 201 $result
                continue
            }

            if ($method -eq 'POST' -and $path -eq '/v1/control-center/customer-onboarding/approve') {
                $session = Require-Session $context -RequireCsrf
                if ($null -eq $session) { continue }
                $body = Get-RequestJson $request
                $requestId = [string]$body.request_id
                $rows = @($script:State.onboarding_requests)
                $requestRow = $rows | Where-Object { [string]$_.request_id -eq $requestId } | Select-Object -First 1
                if ($null -eq $requestRow) {
                    Send-Json $context 404 @{ message = 'Onboarding request not found.' }
                    continue
                }
                if ([string]$requestRow.status -ne 'PENDING') {
                    Send-Json $context 409 @{ message = 'Onboarding request is not pending.' }
                    continue
                }
                $result = New-CustomerProvision `
                    -OrganizationName ([string]$requestRow.organization_name) `
                    -OwnerEmail ([string]$requestRow.owner_email) `
                    -CountryCode ([string]$requestRow.country_code) `
                    -PlanCode 'LOCAL_PRO' `
                    -MaxUsers 5 `
                    -MaxDevices 2 `
                    -TrialDays 14 `
                    -SourceRequestId $requestId
                $requestRow.status = 'APPROVED'
                $requestRow.reviewed_at = [DateTimeOffset]::UtcNow.ToString('o')
                $requestRow.reviewed_by = $AdminEmail
                $requestRow.organization_id = [string]$result.organization_id
                Add-Audit 'ONBOARDING.APPROVE' 'onboarding_request' $requestId "Approved and provisioned $($requestRow.organization_name)"
                Save-State
                Send-Json $context 200 $result
                continue
            }

            if ($method -eq 'POST' -and $path -eq '/v1/control-center/customer-onboarding/reject') {
                $session = Require-Session $context -RequireCsrf
                if ($null -eq $session) { continue }
                $body = Get-RequestJson $request
                $requestId = [string]$body.request_id
                $requestRow = @($script:State.onboarding_requests) | Where-Object { [string]$_.request_id -eq $requestId } | Select-Object -First 1
                if ($null -eq $requestRow) {
                    Send-Json $context 404 @{ message = 'Onboarding request not found.' }
                    continue
                }
                if ([string]$requestRow.status -ne 'PENDING') {
                    Send-Json $context 409 @{ message = 'Onboarding request is not pending.' }
                    continue
                }
                $requestRow.status = 'REJECTED'
                $requestRow.reviewed_at = [DateTimeOffset]::UtcNow.ToString('o')
                $requestRow.reviewed_by = $AdminEmail
                $requestRow.rejection_reason = [string]$body.reason
                Add-Audit 'ONBOARDING.REJECT' 'onboarding_request' $requestId ([string]$body.reason)
                Save-State
                Send-Json $context 200 @{ status='REJECTED'; request_id=$requestId }
                continue
            }

            if ($method -eq 'POST' -and $path -eq '/v1/control-center/actions') {
                $session = Require-Session $context -RequireCsrf
                if ($null -eq $session) { continue }
                $body = Get-RequestJson $request
                $actionCode = ([string]$body.action_code).Trim().ToUpperInvariant()
                $organizationId = ([string]$body.organization_id).Trim()
                $targetEntityId = ([string]$body.target_entity_id).Trim()
                $reason = ([string]$body.reason).Trim()
                $requestedState = $body.requested_state

                if ([string]::IsNullOrWhiteSpace($actionCode) -or [string]::IsNullOrWhiteSpace($reason)) {
                    Send-Json $context 400 @{ message = 'action_code and reason are required.' }
                    continue
                }

                $changed = $false
                $entityType = 'organization'
                $entityId = $organizationId
                $beforeState = $null
                $afterState = $null

                if ($actionCode -in @('ORGANIZATION.ACTIVATE','ORGANIZATION.SUSPEND','ORGANIZATION.RESUME')) {
                    $org = @($script:State.organizations) | Where-Object { [string]$_.organization_id -eq $organizationId } | Select-Object -First 1
                    if ($null -eq $org) {
                        Send-Json $context 404 @{ message = 'Organization not found for action.' }
                        continue
                    }
                    $entityType = 'organization'
                    $entityId = [string]$org.organization_id
                    $beforeState = [ordered]@{ status = [string]$org.status }
                    if ($actionCode -eq 'ORGANIZATION.SUSPEND') { $org.status = 'SUSPENDED' }
                    else { $org.status = 'ACTIVE' }
                    Set-StateProperty $org 'status_changed_at' ([DateTimeOffset]::UtcNow.ToString('o'))
                    $afterState = [ordered]@{ status = [string]$org.status }
                    $changed = $true

                } elseif ($actionCode -in @(
                    'SUBSCRIPTION.ACTIVATE','SUBSCRIPTION.SUSPEND','SUBSCRIPTION.REACTIVATE',
                    'SUBSCRIPTION.CANCEL','SUBSCRIPTION.RESTORE','SUBSCRIPTION.RENEW',
                    'SUBSCRIPTION.EXTEND','SUBSCRIPTION.TRIAL_EXTEND',
                    'SUBSCRIPTION.MARK_PAID','SUBSCRIPTION.MARK_UNPAID'
                )) {
                    $sub = Find-Subscription $organizationId $targetEntityId
                    if ($null -eq $sub) {
                        Send-Json $context 404 @{ message = 'Subscription not found for action.' }
                        continue
                    }
                    $entityType = 'subscription'
                    $entityId = [string]$sub.subscription_id
                    $organizationId = [string]$sub.organization_id
                    $beforeState = [ordered]@{
                        status = [string]$sub.status
                        billing_status = [string]$sub.billing_status
                        expires_at = [string]$sub.expires_at
                    }

                    if ($actionCode -eq 'SUBSCRIPTION.ACTIVATE') {
                        if ([string]$sub.status -in @('CANCELLED','EXPIRED')) {
                            Send-Json $context 409 @{ message = 'Cancelled/expired subscription must be restored or renewed, not directly activated.' }
                            continue
                        }
                        $sub.status = 'ACTIVE'
                        if ([string]$sub.billing_status -eq 'TRIAL') { $sub.billing_status = 'UNPAID' }
                    } elseif ($actionCode -eq 'SUBSCRIPTION.SUSPEND') {
                        if ([string]$sub.status -eq 'CANCELLED') {
                            Send-Json $context 409 @{ message = 'Cancelled subscription cannot be suspended.' }
                            continue
                        }
                        $sub.status = 'SUSPENDED'
                    } elseif ($actionCode -eq 'SUBSCRIPTION.REACTIVATE') {
                        if ([string]$sub.status -ne 'SUSPENDED') {
                            Send-Json $context 409 @{ message = 'Only a suspended subscription can be reactivated.' }
                            continue
                        }
                        $sub.status = 'ACTIVE'
                    } elseif ($actionCode -eq 'SUBSCRIPTION.CANCEL') {
                        $sub.status = 'CANCELLED'
                    } elseif ($actionCode -eq 'SUBSCRIPTION.RESTORE') {
                        if ([string]$sub.status -ne 'CANCELLED') {
                            Send-Json $context 409 @{ message = 'Only a cancelled subscription can be restored.' }
                            continue
                        }
                        $sub.status = 'ACTIVE'
                    } elseif ($actionCode -in @('SUBSCRIPTION.EXTEND','SUBSCRIPTION.TRIAL_EXTEND')) {
                        $days = Get-RequestedInt $requestedState 'extension_days' 0
                        if ($days -lt 1 -or $days -gt 3650) {
                            Send-Json $context 400 @{ message = 'extension_days must be between 1 and 3650.' }
                            continue
                        }
                        if ($actionCode -eq 'SUBSCRIPTION.TRIAL_EXTEND' -and [string]$sub.status -ne 'TRIAL') {
                            Send-Json $context 409 @{ message = 'Trial extension requires TRIAL status.' }
                            continue
                        }
                        $base = [DateTimeOffset]::UtcNow
                        if (-not [string]::IsNullOrWhiteSpace([string]$sub.expires_at)) {
                            try {
                                $currentExpiry = [DateTimeOffset]::Parse([string]$sub.expires_at)
                                if ($currentExpiry -gt $base) { $base = $currentExpiry }
                            } catch {}
                        }
                        $sub.expires_at = $base.AddDays($days).ToString('o')
                        Set-StateProperty $sub 'last_period_extension_days' $days
                    } elseif ($actionCode -eq 'SUBSCRIPTION.MARK_PAID') {
                        $sub.billing_status = 'PAID'
                        Set-StateProperty $sub 'paid_at' ([DateTimeOffset]::UtcNow.ToString('o'))
                        Set-StateProperty $sub 'unpaid_at' $null
                    } elseif ($actionCode -eq 'SUBSCRIPTION.MARK_UNPAID') {
                        $sub.billing_status = 'UNPAID'
                        Set-StateProperty $sub 'unpaid_at' ([DateTimeOffset]::UtcNow.ToString('o'))
                    } elseif ($actionCode -eq 'SUBSCRIPTION.RENEW') {
                        $renewalDays = Get-RequestedInt $requestedState 'renewal_days' 365
                        if ($renewalDays -lt 1 -or $renewalDays -gt 3650) {
                            Send-Json $context 400 @{ message = 'renewal_days must be between 1 and 3650.' }
                            continue
                        }
                        $previousExpiry = [DateTimeOffset]::UtcNow
                        if (-not [string]::IsNullOrWhiteSpace([string]$sub.expires_at)) {
                            try { $previousExpiry = [DateTimeOffset]::Parse([string]$sub.expires_at) } catch {}
                        }
                        $renewBase = $previousExpiry
                        if ($renewBase -lt [DateTimeOffset]::UtcNow) { $renewBase = [DateTimeOffset]::UtcNow }
                        $newExpiry = $renewBase.AddDays($renewalDays)
                        $sub.expires_at = $newExpiry.ToString('o')
                        $sub.status = 'ACTIVE'
                        [void](Add-RenewalRecord $sub $previousExpiry $newExpiry)
                    }

                    Set-StateProperty $sub 'status_changed_at' ([DateTimeOffset]::UtcNow.ToString('o'))
                    $remaining = Get-RemainingPeriod $sub
                    $afterState = [ordered]@{
                        status = [string]$sub.status
                        billing_status = [string]$sub.billing_status
                        expires_at = [string]$sub.expires_at
                        remaining_days = $remaining.remaining_days
                        remaining_hours = $remaining.remaining_hours
                    }
                    $changed = $true

                } elseif ($actionCode -in @(
                    'DEVICE.ACTIVATE','DEVICE.DEACTIVATE','DEVICE.SUSPEND','DEVICE.RESUME','DEVICE.REVOKE'
                )) {
                    $device = Find-Device $organizationId $targetEntityId
                    if ($null -eq $device) {
                        Send-Json $context 404 @{ message = 'Device not found for action.' }
                        continue
                    }
                    $entityType = 'device'
                    $entityId = [string](Get-StateProperty $device 'device_id' (Get-StateProperty $device 'id' ''))
                    $organizationId = [string]$device.organization_id
                    $beforeStatus = ([string]$device.status).ToUpperInvariant()
                    $beforeState = [ordered]@{ status = $beforeStatus }

                    if ($beforeStatus -in @('REVOKED','REPLACED')) {
                        Send-Json $context 409 @{ message = "Terminal device state $beforeStatus cannot be reactivated." }
                        continue
                    }

                    if ($actionCode -in @('DEVICE.DEACTIVATE','DEVICE.SUSPEND')) {
                        $device.status = 'SUSPENDED'
                        Set-StateProperty $device 'deactivated_at' ([DateTimeOffset]::UtcNow.ToString('o'))
                    } elseif ($actionCode -in @('DEVICE.ACTIVATE','DEVICE.RESUME')) {
                        $device.status = 'ACTIVE'
                        Set-StateProperty $device 'activated_at' ([DateTimeOffset]::UtcNow.ToString('o'))
                    } elseif ($actionCode -eq 'DEVICE.REVOKE') {
                        $device.status = 'REVOKED'
                        Set-StateProperty $device 'revoked_at' ([DateTimeOffset]::UtcNow.ToString('o'))
                    }
                    Set-StateProperty $device 'status_changed_at' ([DateTimeOffset]::UtcNow.ToString('o'))
                    $afterState = [ordered]@{ status = [string]$device.status }
                    $changed = $true
                } else {
                    Send-Json $context 400 @{ message = "Unsupported operational action: $actionCode" }
                    continue
                }

                $auditDetail = [ordered]@{
                    reason = $reason
                    before = $beforeState
                    after = $afterState
                    target_entity_type = $entityType
                    target_entity_id = $entityId
                } | ConvertTo-Json -Depth 6 -Compress
                Add-Audit $actionCode $entityType $entityId $auditDetail
                Save-State

                Send-Json $context 200 @{
                    status = 'LOCAL_DEV_APPLIED'
                    action_code = $actionCode
                    organization_id = $organizationId
                    target_entity_type = $entityType
                    target_entity_id = $entityId
                    before_state = $beforeState
                    after_state = $afterState
                    environment = 'LOCAL_DEVELOPMENT_ONLY'
                }
                continue
            }

            if ($method -eq 'POST' -and $path -eq '/v1/control-center/auth/recovery/start') {
                Send-Json $context 200 @{ status = 'RECOVERY_REQUEST_ACCEPTED'; environment = 'LOCAL_DEVELOPMENT_ONLY' }
                continue
            }

            if ($method -eq 'POST' -and $path -eq '/v1/control-center/auth/recovery/complete') {
                Send-Json $context 501 @{ message = 'Recovery completion is not implemented by the local development harness. Use production server recovery or reset local dev state.' }
                continue
            }

            if ($method -eq 'GET' -and $path.StartsWith('/v1/control-center')) {
                $session = Require-Session $context
                if ($null -eq $session) { continue }
                $relative = $path.Substring('/v1/control-center'.Length)
                if ($relative -eq '/dashboard' -or $relative -eq '') {
                    $organizations = @($script:State.organizations)
                    $requests = @($script:State.onboarding_requests)
                    $subscriptions = @($script:State.subscriptions)
                    $activations = @($script:State.activations)
                    Send-Json $context 200 @{
                        environment = 'LOCAL_DEVELOPMENT_ONLY'
                        server = 'Yalla Local Admin Development Harness'
                        admin_email = $AdminEmail
                        role = 'YALLA_SUPER_OWNER'
                        client_database_exposure = 'NONE'
                        counts = @{
                            organizations = $organizations.Count
                            pending_onboarding = @($requests | Where-Object { [string]$_.status -eq 'PENDING' }).Count
                            active_subscriptions = @($subscriptions | Where-Object { [string]$_.status -in @('ACTIVE','TRIAL') }).Count
                            suspended_subscriptions = @($subscriptions | Where-Object { [string]$_.status -eq 'SUSPENDED' }).Count
                            unpaid_subscriptions = @($subscriptions | Where-Object { [string]$_.billing_status -eq 'UNPAID' }).Count
                            devices = @($script:State.devices).Count
                            active_devices = @($script:State.devices | Where-Object { [string]$_.status -eq 'ACTIVE' }).Count
                            pending_activations = @($activations | Where-Object { [string]$_.status -eq 'ISSUED' }).Count
                            security_events = @($script:State.security_events).Count
                        }
                        message = 'Operational local Control Center is connected. Customer onboarding data is persisted in Downloads for development only.'
                    }
                } elseif ($relative -eq '/organizations') {
                    Send-Json $context 200 @{ items = @($script:State.organizations) }
                } elseif ($relative -eq '/onboarding-requests') {
                    Send-Json $context 200 @{ items = @($script:State.onboarding_requests | Sort-Object submitted_at -Descending) }
                } elseif ($relative -eq '/subscriptions') {
                    $safeSubscriptions = @()
                    foreach ($sub in @($script:State.subscriptions)) {
                        $remaining = Get-RemainingPeriod $sub
                        $safeSubscriptions += [ordered]@{
                            subscription_id = $sub.subscription_id
                            organization_id = $sub.organization_id
                            plan_code = $sub.plan_code
                            status = $sub.status
                            billing_status = $sub.billing_status
                            started_at = $sub.started_at
                            expires_at = $sub.expires_at
                            remaining_days = $remaining.remaining_days
                            remaining_hours = $remaining.remaining_hours
                            max_users = $sub.max_users
                            max_devices = $sub.max_devices
                            last_period_extension_days = $sub.last_period_extension_days
                            status_changed_at = $sub.status_changed_at
                        }
                    }
                    Send-Json $context 200 @{ items = $safeSubscriptions }
                } elseif ($relative -eq '/licenses') {
                    Send-Json $context 200 @{ items = @($script:State.licenses) }
                } elseif ($relative -eq '/devices') {
                    $safeDevices = @()
                    foreach ($device in @($script:State.devices)) {
                        $deviceId = [string](Get-StateProperty $device 'device_id' (Get-StateProperty $device 'id' ''))
                        $safeDevices += [ordered]@{
                            device_id = $deviceId
                            organization_id = (Get-StateProperty $device 'organization_id')
                            display_name = (Get-StateProperty $device 'display_name')
                            status = (Get-StateProperty $device 'status' 'UNKNOWN')
                            activated_at = (Get-StateProperty $device 'activated_at')
                            deactivated_at = (Get-StateProperty $device 'deactivated_at')
                            revoked_at = (Get-StateProperty $device 'revoked_at')
                            last_seen = (Get-StateProperty $device 'last_seen' (Get-StateProperty $device 'last_seen_at'))
                            app_version = (Get-StateProperty $device 'app_version')
                            status_changed_at = (Get-StateProperty $device 'status_changed_at')
                            can_activate = ([string]$device.status -eq 'SUSPENDED')
                            can_deactivate = ([string]$device.status -eq 'ACTIVE')
                        }
                    }
                    Send-Json $context 200 @{ items = $safeDevices }
                } elseif ($relative -eq '/plans') {
                    Send-Json $context 200 @{ items = @($script:State.plans) }
                } elseif ($relative -eq '/features') {
                    Send-Json $context 200 @{ items = @($script:State.features) }
                } elseif ($relative -eq '/entitlements') {
                    Send-Json $context 200 @{ items = @($script:State.entitlements) }
                } elseif ($relative -eq '/activations') {
                    $safe = @()
                    foreach ($a in @($script:State.activations)) {
                        $safe += [ordered]@{
                            activation_id = $a.activation_id
                            organization_id = $a.organization_id
                            license_id = $a.license_id
                            status = $a.status
                            issued_at = $a.issued_at
                            redeemed_at = $a.redeemed_at
                        }
                    }
                    Send-Json $context 200 @{ items = $safe }
                } elseif ($relative -eq '/renewals') {
                    Send-Json $context 200 @{ items = @($script:State.renewals) }
                } elseif ($relative -eq '/overrides') {
                    Send-Json $context 200 @{ items = @($script:State.overrides) }
                } elseif ($relative -eq '/security-events' -or $relative -eq '/admin-security-events') {
                    Send-Json $context 200 @{ items = @($script:State.security_events | Sort-Object at -Descending) }
                } elseif ($relative -eq '/audit-logs') {
                    Send-Json $context 200 @{ items = @($script:State.audit_logs | Sort-Object at -Descending) }
                } elseif ($relative -eq '/admin-users') {
                    Send-Json $context 200 @{ items = @(@{ email = $AdminEmail; roles = @('YALLA_SUPER_OWNER'); status = 'ACTIVE'; environment = 'LOCAL_DEVELOPMENT_ONLY' }) }
                } elseif ($relative -eq '/auth/sessions') {
                    $rows = @()
                    foreach ($entry in $script:Sessions.GetEnumerator()) {
                        $rows += @{ session_id = $entry.Key.Substring(0, [Math]::Min(12, $entry.Key.Length)); email = $AdminEmail; status = 'ACTIVE'; expires_at = $entry.Value.expires_at.ToString('o') }
                    }
                    Send-Json $context 200 @{ items = $rows }
                } elseif ($relative -eq '/break-glass') {
                    Send-Json $context 200 @{ items = @($script:BreakGlass.Values) }
                } else {
                    Send-Json $context 200 @{ items = @(); environment = 'LOCAL_DEVELOPMENT_ONLY'; section = $relative.TrimStart('/') }
                }
                continue
            }

            Send-Json $context 404 @{ message = 'Local development endpoint not found.'; path = $path }
        } catch {
            try { Send-Json $context 500 @{ message = 'Local development server error.'; detail = $_.Exception.Message } } catch {}
        }
    }
} finally {
    if ($listener.IsListening) { $listener.Stop() }
    $listener.Close()
    Remove-Item -LiteralPath $ReadyPath -Force -ErrorAction SilentlyContinue
}
