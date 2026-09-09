# Stage 36 — Responsive Audit

Status: PASS for the responsive scenarios below. Stage 37 has not started.
Date: 2026-09-09

## Acceptance evidence

- 29 primary screens and 51 additional route constructors rendered at 430x932 (iPhone 15 Pro Max logical size), 390x844 (medium Android), and 844x390 (landscape).
- Five document/detail/dialog cases: repair details, purchase details, supplier account, client details dialog, and edit-client dialog at the same sizes. The supplier-account bottom sheet is also opened from the supplier list.
- Disposable database with long Arabic customer/supplier names, vehicles, repairs, purchase items and balanced ledger data. No fake legacy tables were introduced to conceal query failures.
- Real Cairo fonts plus an Arabic fallback for the headless test environment, mobile theme and route frame. Keyboard insets, focus, scrolling and teardown exercised.
- Screenshot review of the rendered phone screens. Security & Data explicitly must finish loading and show its save-settings action before acceptance.
- Combined responsive, adaptive-layout, dashboard, workflow, employee, master-data, voucher and dialog regressions: **55 tests passed** (`.dart_tool/stage36-final-suite.log`). Aggregate matrix tests include multiple screens/sizes; 55 is not the screen count.
- Shared layout contracts include Spacer/wrapped actions at seven widths from 320 to 1440.
- `dart format`: 51 files checked, zero changes on the final formatting pass.
- `flutter analyze --no-pub`: zero errors; warnings/info remain in the repository and the command returns nonzero. See final log for count. This is not a claim of a lint-clean repository.
- Android debug APK built, installed with `adb install -r`, launched and logged into the existing test owner session. Dashboard visually checked with existing workshop data. No financial documents were created during this native check.

No RenderFlex overflow or Flutter layout exception remains in the tested scenarios. No obvious unintended text clipping was found in the reviewed captures. Horizontal stage chips intentionally scroll.

## Fixes implemented

- Scrollable summaries/headers and empty/error states under landscape and keyboard constraints.
- Wrapping toolbars, bounded dropdowns, intrinsic card heights and phone layouts retained at landscape widths.
- Adaptive dialogs; scrollable employee form; compact salary action with tooltip.
- AdaptiveRow filters Spacer from Wrap; repairs overview only shows its fixed sidebar at desktop width.
- Purchase details uses the desktop breakpoint so its header remains scrollable on landscape phones.
- Purchases dashboard listener registered through listenManual to allow rendering.
- Legacy purchase audit/unposted screens and insurance invoices handle load errors with a visible Arabic retry state instead of uncaught errors. Their accounting queries were not remapped.
- Test-only storage root override prevents tests from scanning real workshop backup files. Owner/device test fixtures allow settings content to render without altering authorization.

## Limits and remaining risks

- Three legacy screens still have unavailable data dependencies in a newly migrated database: `purchases` for purchase audit/unposted screens and `insurance_invoices` for insurance invoices. Their error-state layout is verified; successful populated content cannot be certified for those routes. They are NOT certified commercially functional by this stage.
- Existing raw-material and vehicle-arrears query issues were observed. Their feature readiness must be resolved or hidden in the planned release-cleanup stages. No schema or speculative accounting changes were made here.
- This is a responsive acceptance result, not full functional/commercial release acceptance. Tests cover initial rendering, representative data, first visible input and scrolling, not every possible document and text-scale combination.
- iPhone-size widget tests are not a physical iPhone test. Native iOS picker/keyboard and final Android/iPhone end-to-end acceptance remain Stages 59–60. No IPA was built.
- No database reset, schema migration, posting changes or authorization bypass was introduced in Stage 36. Existing unrelated workspace changes were retained.

## Files modified in this stage

- `lib/features/repairs/widgets/repair_filter_bar.dart`
- `lib/features/repairs/screens/repairs_screen.dart`
- `lib/features/insurance_agent/calculator/widgets/dynamic_inputs_form.dart`
- `lib/features/insurance_agent/calculator/widgets/category_selector.dart`
- `lib/features/employees/widgets/steps/step_employee_basic_data.dart`
- `lib/features/finance/screens/cash_account_screen.dart`
- `lib/features/finance/screens/bank_account_screen.dart`
- `lib/features/finance/screens/journal_entries_screen.dart`
- `lib/features/finance/purchases/screens/purchase_create_screen.dart`
- `lib/features/finance/purchases/screens/purchases_list_screen.dart`
- `lib/features/finance/purchases/screens/purchase_details_screen.dart`
- `lib/features/vouchers/screens/payment_voucher_screen.dart`
- `lib/features/parties/screens/parties_screen.dart`
- `lib/features/reports/screens/gl_entry_details_dialog.dart`
- `test/responsive/stage36_primary_screens_test.dart`
- `lib/shared/widgets/adaptive_layout.dart`
- `lib/features/finance/gl/screens/gl_browser_screen.dart`
- `lib/features/finance/screens/accounts_receivable_screen.dart`
- `lib/features/finance/reports/screens/income_statement_screen.dart`
- `lib/features/finance/reports/screens/balance_sheet_screen.dart`
- `lib/features/finance/reports/screens/cash_flow_screen.dart`
- `lib/features/vouchers/screens/payment_vouchers_list_screen.dart`
- `lib/features/vouchers/screens/receipt_vouchers_list_screen.dart`
- `lib/features/finance/screens/account_ledger_screen.dart`
- `lib/features/finance/screens/general_journal_screen.dart`
- `lib/features/reports/screens/trial_balance_screen.dart`
- `lib/features/finance/purchases/screens/supplier_payments_screen.dart`
- `lib/features/reports/screens/reports_dashboard_screen.dart`
- `lib/features/cheques/screens/cheques_list_screen.dart`
- `lib/features/cheques/screens/cheques_report_screen.dart`
- `lib/features/cheques/screens/cheques_dashboard_screen.dart`
- `lib/features/employees/screens/advances_report_screen.dart`
- `lib/features/finance/purchases/screens/purchase_other_screen.dart`
- `lib/features/finance/purchases/screens/purchases_dashboard_screen.dart`
- `lib/features/suppliers/screens/suppliers_payables_list_screen.dart`
- `lib/features/repairs/screens/repairs_and_ar_screen.dart`
- `lib/features/employees/screens/salary_screen.dart`
- `lib/features/finance/purchases/screens/purchases_gl_audit_screen.dart`
- `test/responsive/stage36_additional_routes_test.dart`
- `test/responsive/r11_adaptive_layout_contract_test.dart`

- `lib/core/storage/yalla_storage_service.dart`
- `lib/shared/widgets/error_widget.dart`
- `lib/features/repairs/screens/repairs_overview_screen.dart`
- `lib/features/finance/purchases/screens/unposted_purchases_screen.dart`
- `lib/features/insurance/providers/insurance_invoice_provider.dart`
- `lib/features/insurance/screens/insurance_invoice_list_screen.dart`
- `test/responsive/stage36_documents_test.dart`
- `test/responsive/stage36_support.dart`
- `pubspec.yaml` (direct test dependency on the already installed device-info platform interface)

## Evidence files

- `.dart_tool/stage36-final-suite.log`
- `.dart_tool/stage36-primary-final.log`
- `.dart_tool/stage36-analyze-final.log`
- `.dart_tool/stage36-build.log`
- `.dart_tool/stage36-previews/`
- `.dart_tool/stage36-android.png`