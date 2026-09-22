param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$TestArgs
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testDbRoot = Join-Path $env:TEMP ("yallah_financial_qa_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $testDbRoot | Out-Null

$previousDbDir = $env:YALLA_ACCOUNTS_DB_DIR
$previousV55 = $env:YALLA_V55_FIXTURE_DB
$env:YALLA_ACCOUNTS_DB_DIR = $testDbRoot
$env:YALLA_V55_FIXTURE_DB = ''

try {
  Set-Location $root
  Write-Host "SAFE_DB_ROOT=$testDbRoot"
  if ($TestArgs -and $TestArgs.Count -gt 0) {
    & flutter test --concurrency=1 --no-pub @TestArgs
  } else {
    & flutter test --concurrency=1 --no-pub
  }
  exit $LASTEXITCODE
} finally {
  $env:YALLA_ACCOUNTS_DB_DIR = $previousDbDir
  $env:YALLA_V55_FIXTURE_DB = $previousV55
  if (Test-Path $testDbRoot) { Remove-Item $testDbRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
