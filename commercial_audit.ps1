$ErrorActionPreference = "Continue"
$OutFile = "YALLA_COMMERCIAL_AUDIT.txt"

if (Test-Path $OutFile) { Remove-Item $OutFile -Force }

function S($t) {
    Add-Content $OutFile ""
    Add-Content $OutFile "============================================================"
    Add-Content $OutFile $t
    Add-Content $OutFile "============================================================"
}

function R($label,$cmd) {
    S $label
    Add-Content $OutFile "COMMAND: $cmd"
    try {
        cmd /c "$cmd" 2>&1 | Tee-Object -FilePath $OutFile -Append
    } catch {
        Add-Content $OutFile "EXCEPTION: $($_.Exception.Message)"
    }
}

S "YALLA ACCOUNTS COMMERCIAL READINESS AUDIT"
Add-Content $OutFile "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Add-Content $OutFile "Working Directory: $(Get-Location)"
Add-Content $OutFile "Computer: $env:COMPUTERNAME"
Add-Content $OutFile "User: $env:USERNAME"

R "01 FLUTTER DOCTOR" "flutter doctor -v"
R "02 FLUTTER VERSION" "flutter --version"
R "03 DART VERSION" "dart --version"

R "04 GIT STATUS" "git status --short"
R "05 GIT BRANCH" "git branch --show-current"
R "06 RECENT COMMITS" "git log -10 --oneline"

R "07 FLUTTER CLEAN" "flutter clean"
R "08 REMOVE BUILD" "if exist build rmdir /s /q build"
R "09 PUB GET" "flutter pub get"
R "10 PUB OUTDATED" "flutter pub outdated"

R "11 FLUTTER ANALYZE" "flutter analyze"
R "12 FULL TEST SUITE" "flutter test"
R "13 TEST WITH COVERAGE" "flutter test --coverage"

R "14 WINDOWS RELEASE BUILD" "flutter build windows --release -v"

S "15 WINDOWS BUILD ARTIFACT CHECK"
$exe = Get-ChildItem ".\build\windows" -Filter *.exe -Recurse -ErrorAction SilentlyContinue
if ($exe) {
    $exe | Select-Object FullName,Length,LastWriteTime |
    Format-Table -AutoSize | Out-String | Add-Content $OutFile
} else {
    Add-Content $OutFile "NO WINDOWS EXE FOUND"
}

S "16 DATABASE FILE DISCOVERY"
$db = Get-ChildItem . -Recurse -Include *.db,*.sqlite,*.sqlite3 -ErrorAction SilentlyContinue
if ($db) {
    $db | Select-Object FullName,Length,LastWriteTime |
    Format-Table -AutoSize | Out-String | Add-Content $OutFile
} else {
    Add-Content $OutFile "NO DB FILES FOUND INSIDE PROJECT"
}

S "17 YALLA_DB_PATH CHECK"
if ($env:YALLA_DB_PATH) {
    Add-Content $OutFile "YALLA_DB_PATH=$env:YALLA_DB_PATH"
    if (Test-Path $env:YALLA_DB_PATH) {
        Add-Content $OutFile "YALLA_DB_PATH EXISTS"
    } else {
        Add-Content $OutFile "YALLA_DB_PATH DOES NOT EXIST"
    }
} else {
    Add-Content $OutFile "YALLA_DB_PATH IS NOT SET"
}

S "18 BACKUP RESTORE FILES"
Get-ChildItem . -Recurse -File -ErrorAction SilentlyContinue |
Where-Object { $_.Name -match "backup|restore|migration|database|sqlite" } |
Select-Object FullName |
Format-Table -AutoSize | Out-String | Add-Content $OutFile

S "19 ACCOUNTING CORE FILES"
Get-ChildItem . -Recurse -File -ErrorAction SilentlyContinue |
Where-Object { $_.Name -match "journal|ledger|gl_|invoice|purchase|supplier|customer|payment|account" } |
Select-Object FullName |
Format-Table -AutoSize | Out-String | Add-Content $OutFile

S "20 OWNER ROLE PERMISSION RESTORE SEARCH"
$pats = @(
"owner","manager","accountant","employee","technician",
"permission","role","canRestore","restore"
)

foreach ($p in $pats) {
    Add-Content $OutFile ""
    Add-Content $OutFile "----- $p -----"
    Get-ChildItem .\lib -Recurse -Include *.dart -ErrorAction SilentlyContinue |
    Select-String -Pattern $p -CaseSensitive:$false |
    Select-Object Path,LineNumber,Line |
    Format-Table -AutoSize | Out-String | Add-Content $OutFile
}

S "21 DUPLICATE POSTING SEARCH"
Get-ChildItem . -Recurse -Include *.dart -ErrorAction SilentlyContinue |
Select-String -Pattern "duplicate|posting|posted|postTo|journal|gl_entries|gl_lines" -CaseSensitive:$false |
Select-Object Path,LineNumber,Line |
Format-Table -AutoSize | Out-String | Add-Content $OutFile

S "22 ASYNC BUILD CONTEXT SEARCH"
Get-ChildItem .\lib -Recurse -Include *.dart -ErrorAction SilentlyContinue |
Select-String -Pattern "use_build_context_synchronously|mounted" -CaseSensitive:$false |
Select-Object Path,LineNumber,Line |
Format-Table -AutoSize | Out-String | Add-Content $OutFile

S "23 TODO FIXME HACK TEMP MOCK DUMMY"
Get-ChildItem .\lib -Recurse -Include *.dart -ErrorAction SilentlyContinue |
Select-String -Pattern "TODO|FIXME|HACK|TEMP|temporary|mock|dummy" -CaseSensitive:$false |
Select-Object Path,LineNumber,Line |
Format-Table -AutoSize | Out-String | Add-Content $OutFile

S "24 HARDCODED TEST LOGIN SEARCH"
Get-ChildItem .\lib -Recurse -Include *.dart -ErrorAction SilentlyContinue |
Select-String -Pattern "owner|1234|admin|test login|temporary login|دخول مؤقت" -CaseSensitive:$false |
Select-Object Path,LineNumber,Line |
Format-Table -AutoSize | Out-String | Add-Content $OutFile

S "25 PUBSPEC FONT CHECK"
if (Test-Path ".\pubspec.yaml") {
    Get-Content ".\pubspec.yaml" |
    Select-String -Pattern "fonts:|assets:|Cairo|Noto|Tahoma|TraditionalArabic" -CaseSensitive:$false |
    Out-String | Add-Content $OutFile
}

S "26 ACTUAL FONT FILES"
Get-ChildItem . -Recurse -Include *.ttf,*.otf -ErrorAction SilentlyContinue |
Select-Object FullName,Length |
Format-Table -AutoSize | Out-String | Add-Content $OutFile

S "27 RELEASE SCOPE FEATURE FLAGS"
Get-ChildItem .\lib -Recurse -Include *.dart -ErrorAction SilentlyContinue |
Select-String -Pattern "ReleaseScopeConfig|chequesEnabled|feature flag|Enabled" -CaseSensitive:$false |
Select-Object Path,LineNumber,Line |
Format-Table -AutoSize | Out-String | Add-Content $OutFile

S "28 SECURITY AND DATABASE PACKAGES"
if (Test-Path ".\pubspec.yaml") {
    Get-Content ".\pubspec.yaml" |
    Select-String -Pattern "secure_storage|crypto|encrypt|sqlite|sqflite|drift|provider|riverpod" -CaseSensitive:$false |
    Out-String | Add-Content $OutFile
}

S "29 TEST FILE INVENTORY"
$tests = Get-ChildItem .\test -Recurse -Include *.dart -ErrorAction SilentlyContinue
Add-Content $OutFile "TEST FILE COUNT: $($tests.Count)"
$tests | Select-Object FullName |
Format-Table -AutoSize | Out-String | Add-Content $OutFile

S "30 LARGE PROJECT FILES"
Get-ChildItem . -Recurse -File -ErrorAction SilentlyContinue |
Where-Object { $_.FullName -notmatch "\\build\\|\\.git\\" } |
Sort-Object Length -Descending |
Select-Object -First 50 FullName,Length |
Format-Table -AutoSize | Out-String | Add-Content $OutFile

S "31 FINAL ERROR EXTRACT"
Select-String -Path $OutFile -Pattern "error|failed|exception|fatal|FAIL|skipping|warning" -CaseSensitive:$false |
Select-Object -First 500 |
Out-String | Add-Content $OutFile

S "AUDIT FINISHED"
Add-Content $OutFile "Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

Write-Host ""
Write-Host "DONE"
Write-Host "Upload this file:"
Write-Host "$((Get-Location).Path)\YALLA_COMMERCIAL_AUDIT.txt"
