# Yallah Accounts — Unified source, 20 September 2026

Version: 1.0.1+20. Database schema: 78.

This is the independent source for Windows, iPhone and Android owner builds.
It is not a linked worktree and does not use another project's Git object directory.

## Included work
- Human QA baseline: accbc34.
- Financial Track B: 87b4397.
- UX / navigation / attendance Track A: 41dd1c2.
- Cheques lifecycle and accounting: 45aa635, plus the saved v78 migration-test updates.
- Sidebar merge retains cheque books and route-visibility rules.
- Attendance merge retains period filters and report access without duplicate month controls.

## Build from this directory
- Windows owner: powershell -File tools/release/build_unified_owner.ps1 -Target windows
- Android owner test APK: powershell -File tools/release/build_unified_owner.ps1 -Target android
- iPhone owner, on macOS/Xcode: bash tools/release/build_unified_ios_owner.sh
- Codemagic workflow: ios_unified_owner (select this source branch explicitly).

## Safety and release boundaries
The owner build flag is explicit; customer authentication defaults and Android production-signing guards are unchanged.
Owner builds must not be distributed as commercial/customer releases. The iPhone package produced by the script is unsigned.
No customer database, customer photos, production defines, signing keys or device activation data are bundled in this source.
Old project directories and live databases were not modified during consolidation. Existing storage-location behavior is retained.
Generated artifacts and old duplicate folders are excluded; archived material and validation evidence are stored beside SOURCE.
Read the accompanying EVIDENCE/FINAL_VALIDATION.json for actual validation and platform-build results; do not infer success from this document.

## Integration corrections applied in this consolidated source
- Restore mobile cheque KPI sizing, adaptive report cards and collapsed phone filters.
- Mask technical errors and use the existing brand colors.
- Export the displayed report snapshot to a platform-safe, uniquely named PDF.
- Check report-view and print permissions before export; keep owner access explicit.
- Enable long reports to span PDF pages and keep totals separate for each currency.
- Preserve historical instrument currency defaults independently of display settings.
- Add behavioral regression tests for filters, currency totals, empty/long PDF export and receipt instrument currencies.

## Contract-test alignment
Existing tests were not disabled. Schema expectations follow the saved v78 migration, and the release-version check follows 1.0.1+20.
Legacy cheque assertions now follow the canonical allocation variable, maturity classifier, expanded lifecycle statuses and the current sidebar label.
Accounting allocation guards, device/auth defaults, production-signing guards and Yalla Control contracts were not weakened.
Full-suite logs retain the initial failures as well as the subsequent results; a build alone is not acceptance evidence.
