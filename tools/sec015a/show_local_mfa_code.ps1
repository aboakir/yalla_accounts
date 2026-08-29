param(
    [string]$StateDir = "$env:USERPROFILE\Downloads\Yalla_Local_Admin_Dev"
)

$ErrorActionPreference = 'Stop'
$statePath = Join-Path $StateDir 'server_state.json'
if (-not (Test-Path -LiteralPath $statePath)) { throw "Local dev state not found: $statePath" }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
if (-not [bool]$state.enrolled -or [string]::IsNullOrWhiteSpace([string]$state.totp_secret_dpapi)) {
    throw 'Local Super Owner is not enrolled yet.'
}

Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
$protected = [Convert]::FromBase64String([string]$state.totp_secret_dpapi)
$plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
    $protected,
    $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
)
$secretB64 = [System.Text.Encoding]::UTF8.GetString($plain)
$secret = [Convert]::FromBase64String($secretB64)
$unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
[Int64]$counter = [Math]::Floor($unix / 30)
$counterBytes = [BitConverter]::GetBytes($counter)
if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($counterBytes) }
$hmac = New-Object System.Security.Cryptography.HMACSHA1
$hmac.Key = $secret
try { $digest = $hmac.ComputeHash($counterBytes) } finally { $hmac.Dispose() }
$offset = [int]($digest[$digest.Length - 1] -band 0x0F)
$binary = (([int]($digest[$offset] -band 0x7F)) -shl 24) -bor (([int]$digest[$offset + 1]) -shl 16) -bor (([int]$digest[$offset + 2]) -shl 8) -bor ([int]$digest[$offset + 3])
$code = ($binary % 1000000).ToString('D6')
$remaining = 30 - ([int]($unix % 30))
Write-Host "LOCAL DEVELOPMENT MFA CODE: $code" -ForegroundColor Cyan
Write-Host "Valid for about $remaining second(s)." -ForegroundColor Yellow
