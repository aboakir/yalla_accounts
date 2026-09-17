[CmdletBinding()]
param(
  [string]$SourceDirectory = (Join-Path $PSScriptRoot '../build/windows/x64/runner/Release'),
  [string]$OutputRoot = (Join-Path $PSScriptRoot '../dist'),
  [switch]$RequireSigned
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
$files = @(Get-ChildItem -LiteralPath $source -Recurse -Force)
foreach ($entry in $files) {
  if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked package entries are forbidden.' }
  $relative = $entry.FullName.Substring($source.Length).TrimStart('\','/').Replace('\','/')
  if ($relative -match '(^|/)(\.env[^/]*|node_modules|test|tests|\.git|\.dart_tool)(/|$)' -or
      $relative -match '\.(pem|key|pfx|p12|db|sqlite|log|bak|tmp|ps1|dart|pdb)$') {
    throw "Forbidden package entry: $relative"
  }
}
foreach ($required in @('yalla_accounts.exe','flutter_windows.dll','data/app.so','data/icudtl.dat')) {
  if (-not (Test-Path -LiteralPath (Join-Path $source $required) -PathType Leaf)) { throw "Missing build file: $required" }
}
$exe = Join-Path $source 'yalla_accounts.exe'
$signature = Get-AuthenticodeSignature -LiteralPath $exe
if ($RequireSigned -and $signature.Status -ne 'Valid') { throw 'A valid Windows publisher signature is required.' }
$versionLine = (Get-Content (Join-Path $PSScriptRoot '../pubspec.yaml') | Where-Object { $_ -match '^version:' } | Select-Object -First 1)
$version = ($versionLine -replace '^version:\s*','').Trim()
if ([string]::IsNullOrWhiteSpace($version)) { throw 'Application version is missing.' }
$label = 'yalla-accounts-internal-candidate-' + $version.Replace('+','-') + '-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$output = [IO.Path]::GetFullPath($OutputRoot)
$null = New-Item -ItemType Directory -Path $output -Force
$stage = Join-Path $output $label
if (Test-Path $stage) { throw 'Candidate path already exists.' }
$null = New-Item -ItemType Directory -Path $stage
foreach ($entry in (Get-ChildItem -LiteralPath $source -Force)) { Copy-Item -LiteralPath $entry.FullName -Destination $stage -Recurse }
$manifestFiles = @(
  foreach ($file in ($files | Where-Object { -not $_.PSIsContainer } | Sort-Object FullName)) {
    $relative = $file.FullName.Substring($source.Length).TrimStart('\','/')
    $hash = (Get-FileHash -LiteralPath (Join-Path $stage $relative) -Algorithm SHA256).Hash
    [ordered]@{ path=$relative.Replace('\','/'); bytes=$file.Length; sha256=$hash }
  }
)
$manifest = [ordered]@{
  product='Yalla Accounts'; version=$version; channel='INTERNAL_CANDIDATE'
  generated_at=[DateTime]::UtcNow.ToString('o'); windows_signature=$signature.Status.ToString()
  production_accepted=$false; files=$manifestFiles
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $stage 'manifest.json') -Encoding utf8
@'
Yalla Accounts — internal release candidate only.
This package is not a signed commercial release.
Keep all adjacent files and the data directory together.
Customer databases/backups are never bundled in this archive.
Upgrade validation must preserve the canonical external application-data database.
Signing status and file hashes are recorded in manifest.json.
'@ | Set-Content -LiteralPath (Join-Path $stage 'README-PACKAGE.txt') -Encoding utf8
$archive = Join-Path $output ($label + '.zip')
Compress-Archive -LiteralPath $stage -DestinationPath $archive -CompressionLevel Optimal
$archiveHash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
"$archiveHash  $([IO.Path]::GetFileName($archive))" | Set-Content -LiteralPath ($archive+'.sha256') -Encoding ascii
[pscustomobject]@{archive=$archive;sha256=$archiveHash;files=$manifestFiles.Count;signature=$signature.Status.ToString();productionAccepted=$false} | ConvertTo-Json
