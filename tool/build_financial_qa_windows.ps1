param([Parameter(ValueFromRemainingArguments = $true)][string[]]$BuildArgs)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$previous = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)', 'Process')
$exitCode = 1
try {
  # Some remote terminal hosts omit this standard Windows variable.
  # Resolve the OS-known folder without changing machine or user settings.
  if ([string]::IsNullOrWhiteSpace($previous)) {
    $folder = [Environment]::GetFolderPath('ProgramFilesX86')
    if (!$folder -or !(Test-Path $folder)) { throw 'ProgramFilesX86 could not be resolved.' }
    [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', $folder, 'Process')
  }
  Set-Location $root
  & flutter build windows --release --no-pub @BuildArgs
  $exitCode = $LASTEXITCODE
} finally {
  [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', $previous, 'Process')
}
exit $exitCode
