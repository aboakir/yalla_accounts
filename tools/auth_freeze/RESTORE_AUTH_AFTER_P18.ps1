param(
    [string]$ProjectRoot = "E:\flutter_projects\yalla_accounts"
)

$Flag = Join-Path $ProjectRoot "lib\dev\temporary_auth_bypass.dart"

if(!(Test-Path $Flag)){
    throw "temporary_auth_bypass.dart not found"
}

$Text = Get-Content $Flag -Raw -Encoding UTF8
$Text = $Text.Replace(
    "const bool kTemporaryAuthBypass = true;",
    "const bool kTemporaryAuthBypass = false;"
)

Set-Content $Flag -Value $Text -Encoding UTF8

dart format `
    "$ProjectRoot\lib\dev\temporary_auth_bypass.dart" `
    "$ProjectRoot\lib\core\routes\app_routes.dart"

Write-Host ""
Write-Host "AUTH BYPASS DISABLED - NORMAL AUTH RESTORED" -ForegroundColor Green
Write-Host "Now rebuild and redesign authentication before release."
