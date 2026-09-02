param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedRoot = 'E:\flutter_projects\yalla_accounts'
$resolvedRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')

if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($resolvedRoot, $expectedRoot)) {
    throw "P01 guard refused path: $resolvedRoot"
}

$pubspecPath = Join-Path $resolvedRoot 'pubspec.yaml'
if (-not (Test-Path -LiteralPath $pubspecPath -PathType Leaf)) {
    throw 'pubspec.yaml was not found.'
}

$pubspec = Get-Content -LiteralPath $pubspecPath -Raw
if ($pubspec -notmatch '(?m)^\s*name:\s*yalla_accounts\s*$') {
    throw 'The project name in pubspec.yaml is not yalla_accounts.'
}

$requiredFiles = @(
    'docs\execution\YALLA_MASTER_PLAN.md',
    'docs\execution\YALLA_PROJECT_STATE.json',
    'docs\execution\YALLA_CHANGELOG.md',
    'docs\execution\YALLA_DECISIONS.md',
    'docs\execution\YALLA_ACCEPTANCE_MATRIX.md',
    'docs\execution\YALLA_DESIGN_FOUNDATION.md',
    'lib\core\design\yalla_design_tokens.dart',
    'lib\core\design\yalla_breakpoints.dart',
    'lib\core\design\yalla_components.dart',
    'test\phase01\yalla_phase01_design_foundation_test.dart'
)

foreach ($relativePath in $requiredFiles) {
    $target = Join-Path $resolvedRoot $relativePath
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        throw "Required P01 file is missing: $relativePath"
    }
}

$statePath = Join-Path $resolvedRoot 'docs\execution\YALLA_PROJECT_STATE.json'
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

if ($state.plan_id -ne 'YAP-MOBILE-V2') {
    throw 'Unexpected plan_id in YALLA_PROJECT_STATE.json.'
}

if ($state.project_name -ne 'yalla_accounts') {
    throw 'Unexpected project_name in YALLA_PROJECT_STATE.json.'
}

Write-Host 'P01 structure verification: PASS' -ForegroundColor Green
