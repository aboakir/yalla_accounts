param(
  [string]$ProjectRoot = "E:\flutter_projects\yalla_accounts"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path (Join-Path $ProjectRoot 'android\app\build.gradle.kts'))) {
  throw "ProjectRoot غير صحيح: $ProjectRoot"
}

$keytool = Get-Command keytool -ErrorAction SilentlyContinue
if ($null -eq $keytool -and $env:JAVA_HOME) {
  $candidate = Join-Path $env:JAVA_HOME 'bin\keytool.exe'
  if (Test-Path $candidate) { $keytool = Get-Item $candidate }
}
if ($null -eq $keytool) {
  throw 'keytool غير موجود. ثبّت/فعّل JDK المستخدم مع Flutter/Android Studio.'
}

$secureRoot = Join-Path $env:USERPROFILE '.yalla_accounts\signing'
New-Item -ItemType Directory -Force -Path $secureRoot | Out-Null
$keystore = Join-Path $secureRoot 'yalla-accounts-release.jks'
$secretFile = Join-Path $secureRoot 'YALLA_ANDROID_SIGNING_SECRETS.txt'
$keyProps = Join-Path $ProjectRoot 'android\key.properties'

if ((Test-Path $keystore) -and (Test-Path $secretFile)) {
  if (-not (Test-Path $keyProps)) {
    $secretLines = Get-Content -LiteralPath $secretFile
    function Read-SecretValue([string]$label) {
      $line = $secretLines | Where-Object { $_.StartsWith($label) } | Select-Object -First 1
      if ([string]::IsNullOrWhiteSpace($line)) { throw "Signing secret is missing: $label" }
      return $line.Substring($label.Length).Trim()
    }
    $alias = Read-SecretValue 'Alias:'
    $password = Read-SecretValue 'Store password:'
    $keyPassword = Read-SecretValue 'Key password:'
    $escapedStore = $keystore -replace '\\','/'
    @"
storePassword=$password
keyPassword=$keyPassword
keyAlias=$alias
storeFile=$escapedStore
"@ | Set-Content -Path $keyProps -Encoding ASCII
    Write-Host 'Recovered android/key.properties from the existing private signing secret.' -ForegroundColor Yellow
  }
  Write-Host 'Android production signing already prepared. Existing key was not replaced.' -ForegroundColor Green
  Write-Host "Keystore: $keystore"
  Write-Host "Secrets remain private under: $secureRoot"
  exit 0
}

$alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%+-_'
$rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
$bytes = New-Object byte[] 36
$rng.GetBytes($bytes)
$password = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
$rng.Dispose()
$alias = 'yalla_release'

& $keytool.Source -genkeypair `
  -v `
  -keystore $keystore `
  -storetype JKS `
  -keyalg RSA `
  -keysize 4096 `
  -validity 10000 `
  -alias $alias `
  -storepass $password `
  -keypass $password `
  -dname 'CN=Yalla Accounts, OU=Mobile, O=Yalla, C=PS'
if ($LASTEXITCODE -ne 0) { throw 'keytool failed to create release keystore.' }

$escapedStore = $keystore -replace '\\','/'
@"
storePassword=$password
keyPassword=$password
keyAlias=$alias
storeFile=$escapedStore
"@ | Set-Content -Path $keyProps -Encoding ASCII

@"
YALLA ACCOUNTS ANDROID RELEASE SIGNING
======================================
KEEP THIS FILE PRIVATE. DO NOT UPLOAD TO GIT OR CHAT.

Keystore: $keystore
Alias: $alias
Store password: $password
Key password: $password

Created: $((Get-Date).ToString('o'))
"@ | Set-Content -Path $secretFile -Encoding UTF8

# Restrict ACL to current user where possible.
try {
  & icacls $secureRoot /inheritance:r /grant:r "$env:USERNAME:(OI)(CI)F" | Out-Null
} catch {}

Write-Host 'ANDROID RELEASE SIGNING: READY' -ForegroundColor Green
Write-Host "Keystore: $keystore"
Write-Host "Private secrets file: $secretFile" -ForegroundColor Yellow
Write-Host 'Do not upload the keystore or secrets file.'
