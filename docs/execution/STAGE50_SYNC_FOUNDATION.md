# Stage 50 — local sync foundation

Implemented as additive v73 metadata. No financial cloud transport, remote apply, automatic merge, document recreation, or new posting path is enabled.

## Storage and transaction contract

- `SyncFoundationTables.ensure` creates six technical sidecars and installs capture triggers after operational schemas. `validate` checks identities and capture coverage. Financial document rows and legacy primary keys are preserved.
- `sync_entity_registry` gives every tracked document/line a permanent random UUID alongside its legacy local ID, organization, current revision, lifecycle state, and local snapshots. UUIDs survive repeated schema ensures, database reopen, document deletion/restoration, and legacy SQLite replacement writes.
- `sync_change_log` captures created, updated, voided, restored, and synced events atomically with SQLite writes. Every event has entity type/local ID/UUID, revision, operation, UTC time, organization/device/user fields, and before/after snapshots. UPDATE, DELETE, and INSERT OR REPLACE cannot rewrite history.
- Existing records receive an explicitly historical baseline. Missing historical/preactivation identity stays null with `attribution_state=historical` or `unavailable`; no actor or installation is invented and local saves keep working.
- `SyncFoundationService.transaction` / `withCurrentActor` read the verified process-local `CurrentUserContext`, bind it only inside the transaction, and restore the previous context in finally. Root integration wraps `DatabaseMigration.inTx`; canonical payment/receipt, voucher, and supplier-payment transactions also use the wrapper. Existing recorded `created_by` / newly changed `updated_by` fields can provide truthful attribution for other callers.
- Child line/workflow changes also advance the parent sidecar revision, so simultaneous edits to different lines cannot hide behind an unchanged header.
- Existing outbox envelopes link to the exact local change revision at enqueue. An acknowledged outbox transition appends one synced event for that revision; it does not falsely acknowledge a later local revision. No new financial envelopes are enqueued.

## Coverage

Repairs/workflow/lines, sales invoices, purchase invoices/lines, payments, purchase payments, receipt headers/allocations, customer-credit allocations, vouchers, cheques, employee advances, payroll runs/payments, insurance policies and their payment instruments, invoice settlements, monthly expenses, GL entries and GL lines.

## Conflict boundary

`quarantineCandidate` persists a proposed version and conflict evidence in one transaction. It detects concurrent revisions, delete versus update, explicit restoration requirements, financial-value differences, incomplete financial snapshots, organization/type mismatch, unknown identity, and protected posted-document changes. Stable remote change IDs permit identical retries and reject altered payload reuse. Every proposal requires review, including a proposal with no detected conflict. This foundation has no apply or resolution method and never calls the posting engine.

Existing posted-source and GL guards remain authoritative. Reversal remains with existing financial services; sync metadata cannot bypass it.

## Validation

- 10 dedicated real-SQLite tests passed (`test/sync`): additive metadata upgrade/reopen, atomic rollback, real authenticated user/device attribution, no-identity local saves, UUID/tombstone stability, immutable history including replacement, exact-revision outbox acknowledgements, conflict/idempotency/no-merge paths, parent revisions, and posted-source/duplicate-posting guards.
- Real application paths exercised: repair intake, canonical receipt/payment/GL posting, supplier voucher, duplicate request replay, failure cleanup, and signed-out actor cleanup. Device identity is created through the real device identity service with isolated in-memory secrets.
- 31 tests passed including the relevant Phase04 outbox/coordinator, Phase11 receipt, and unified supplier-payment regressions.
- Static analysis of new schema, service, and tests: no issues.
- Test processes used `YALLA_ACCOUNTS_DB_DIR` pointing to isolated temporary storage. Real-service fixtures additionally bind `DatabaseMigration.useDatabaseForTesting`; no real financial/user database was used.

## Scope limits

Raw database writers outside the attributed wrappers and without truthful actor columns are still captured, but are explicitly marked unavailable rather than attributed to a guessed user. Historical/unavailable events must not be treated as fully attributable remote mutations by any future transport. Transport security, server protocol, conflict-resolution UI, remote apply, and mobile-device runtime acceptance remain outside this local foundation. SQLite snapshot triggers use the JSON functions supplied by the supported database runtime; Windows SQLite was exercised here, mobile SQLCipher was not run on hardware.
## Final integrated check and strict acceptance

After the final boundary fixes, 17/17 focused tests passed. Real authenticated paths include repair intake/edit/workflow, receipts, sales invoices, purchases, supplier vouchers, employee advances and payroll. Each captured local change in those scenarios was checked for organization, device and user attribution. The nested write helper preserved the original transaction and return value. Final full flutter analyze: zero errors, 98 warnings and 282 infos (380 existing issues, unchanged baseline); log tmp/stage50_final_analyze.log. All files were frozen after these checks.

Full Stage50 requirement: **PARTIAL / NOT PASS**. Clients, suppliers and vehicles still use local integer identities without UUID sidecar/change coverage; employee TEXT identifiers are not universally covered. Existing CUSTOMER:<id>/SUPPLIER:<id>/EMPLOYEE:<id> party mappings do not provide cross-device foreign-reference identity. Financial sync remains disabled, so these incomplete mappings cannot silently import a financial document.

Remaining actor boundaries: ChequeService.addCheque/updateCheque/deleteCheque; ChequeAccountingService.transitionStatus/endorseToSupplier; PoliciesListScreen._deletePolicy. These hidden paths can produce explicitly unavailable attribution. No invented user is recorded.

Compatibility writers without active callers found: InvoiceGlService.insertInvoice; PurchaseDatabaseService.insertInvoice; InvoiceDatabaseService.upsert; RepairLedgerService.createLedgerEntriesForRepair; RepairTables.updateRepairPaidAmount/createInvoiceForRepair; ReportTables.setRepairThumbnailPath/createInvoiceForRepair; HrTables.createPayrollRun; DBService.insertPurchaseInvoice/insertPurchasePayment delegates. Historical import/migration writers remain intentionally unchanged. Mobile SQLCipher JSON runtime still requires device verification.

Final modified source boundaries (relative to lib/):
- core/services/db/tables/accounting_tables.dart, repair_tables.dart, report_tables.dart
- features/employees/services/advance_database_service.dart, payroll_database_service.dart
- features/finance/invoices/services/invoice_service.dart
- features/finance/payments/services/payment_service.dart
- features/finance/purchases/services/purchase_invoice_service.dart, supplier_payment_service.dart
- features/finance/services/finance_events_service.dart, financial_void_service.dart
- features/repairs/screens/repair_details_screen.dart (write boundary only)
- features/repairs/services/edit_repair_service.dart, repair_auto_accounting_service.dart, repair_financial_truth_service.dart, repair_workflow_service.dart, repairs_service.dart
- features/vouchers/services/voucher_payment_service.dart
- test/phase11/yalla_p11_receipt_completion_test.dart and test/phase14/yalla_p14_repair_costing_completion_test.dart (transaction-boundary contracts)

These patches attach metadata at transaction boundaries; they do not introduce a new balance formula, automatic merge, or financial posting source.


## v74 continuation
Added stable master UUID tracking for clients, suppliers, vehicles, employees, parties and accounts (30 types total), additive upgrade74, and a same-workshop UUID reference resolver. Ambiguous legacy plate matches and missing/foreign references fail closed. Existing employee/supplier/cheque/policy/account writer boundaries now record authenticated mutation context. Raw historical imports remain distinguishable. Final isolated sync/cloud run: 30/30 passed; log tmp/stage49_50_verified.log. Full analyzer: zero errors, 98 warnings, 283 infos, before final tested account wrappers. Remaining compatibility writers and a real Desktop transport are not accepted; remote financial apply remains disabled.
