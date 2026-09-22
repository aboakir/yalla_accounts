param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$TestArgs
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testDbRoot = Join-Path $env:TEMP ('yallah_financial_qa_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $testDbRoot | Out-Null
# Only this child process environment is changed; never machine/user settings.
$previousEnvironment = @{}
Get-ChildItem Env: | Where-Object { $_.Name -match '^YALLAH?_' } | ForEach-Object {
  $previousEnvironment[$_.Name] = $_.Value
  Remove-Item ('Env:' + $_.Name)
}
$env:YALLA_ACCOUNTS_DB_DIR = $testDbRoot
$env:YALLAH_FINANCIAL_QA = '1'
$exitCode = 1
$lock = $null
try {
  Set-Location $root
  $lockDir = Join-Path $root '.dart_tool'
  New-Item -ItemType Directory -Force -Path $lockDir | Out-Null
  $lock = [IO.File]::Open((Join-Path $lockDir 'financial-qa.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
  Write-Host "SAFE_DB_ROOT=$testDbRoot"
  if ($TestArgs -and $TestArgs.Count -gt 0) {
    & flutter test --concurrency=1 --no-pub @TestArgs
  } else {
    & flutter test --concurrency=1 --no-pub
  }
  $exitCode = $LASTEXITCODE
} finally {
  if ($null -ne $lock) { $lock.Dispose() }
  Get-ChildItem Env: | Where-Object { $_.Name -match '^YALLAH?_' } | ForEach-Object {
    Remove-Item ('Env:' + $_.Name)
  }
  foreach ($name in $previousEnvironment.Keys) {
    Set-Item ('Env:' + $name) $previousEnvironment[$name]
  }
  if (Test-Path $testDbRoot) {
    Remove-Item $testDbRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
exit $exitCode
