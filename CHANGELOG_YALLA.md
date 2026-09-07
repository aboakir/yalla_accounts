
## P0.001 — Duplicate Posting
- Prevented repeated (source, source_id) postings from appending GL lines.
- Same financial event is now idempotent.
- Same key with different financial lines fails closed.
- Added regression tests for retry and reopen.
- Historical duplicates corrected with reversal entries, not DELETE/UPDATE.
- Historical excess reversed: 11,000.00 ILS across 4 invoices.
- DB migration: No.
- Applied: 2026-08-18 17:53:15

## P0.002 — Repair Reversal / Adjustment
- Repair edits no longer create automatic REPAIR_REV / REPAIR_ADJ accounting.
- Posted invoices and posted GL remain immutable when the repair file is edited.
- Repair client reassignment fails closed pending a dedicated audited workflow.
- Monetary repair edits are marked isLedgerSynced=false.
- 71 historical REPAIR_REV / REPAIR_ADJ headers (212 GL lines) were neutralized
  with explicit P0_REPAIR_FIX reversal entries; no historical GL was deleted or edited.
- Historical legacy repair-adjustment net accounting effect after repair: 0.00 ILS.
- DB migration: No.
- Applied: 2026-08-18 18:17:46

## P0.003 — Posting Status Single Source of Truth
- Authoritative posting truth is now gl_entries(source, source_id).
- invoice.post_to_gl and invoice.gl_entry_id are compatibility/cache fields only.
- voucher.is_posted and voucher.gl_entry_id are compatibility/cache fields only.
- Invoice view resolves GL from actual gl_entries instead of trusting stored link first.
- Payment/receipt voucher lists display actual GL linkage.
- Unposted customer receipts are identified by absence of PAYMENT GL, not a nullable cache.
- Existing invoice/voucher/receipt cache fields synchronized from actual GL.
- Verified state: invoices 112/113 posted; vouchers 55/55; receipts 37/37.
- The single truly unposted 2,200 ILS invoice remains untouched for P0.004.
- DB migration: No.
- Applied: 2026-08-18 18:34:58

## P0.004 — Missing Invoice GL
- InvoiceDatabaseService.createOrGetByRepair now creates/links the invoice and
  INVOICE GL in the same transaction.
- GL posting failures are no longer swallowed in this flow.
- Existing invoice in this flow is auto-healed when INVOICE GL is missing.
- Historical missing invoice db2a8a09-a868-40f4-bfe4-36f3732953b2 posted:
  Dr 1200.C3 2,200.00 ILS
  Cr 4000    2,200.00 ILS
- Invoice GL coverage after repair: 113/113.
- Duplicate INVOICE headers: 0.
- DB migration: No.
- Applied: 2026-08-18 18:50:14

## P0.005 — Supplier / AP Unification
- Canonical supplier AP is now one account per supplier: 2200.S####.
- Voucher supplier payments no longer create/use legacy 2000.S* accounts.
- Secondary outgoing PaymentService no longer depends on removed suppliers.account_id.
- PurchasePaymentService now posts supplier payment correctly:
  Dr Supplier AP / Cr Cash-Bank-Cheques, and stores isIncome=0.
- Core postPurchasePaymentGL now resolves supplier AP by suppliers.id.
- 24 historical supplier-payment GL lines totaling 34,382.98 ILS were
  reclassified with immutable P0_AP_RECLASS entries.
- Historical 2000.S* supplier-account net after repair: 0.00 ILS.
- Canonical 2200.S#### net supplier AP after repair: 41,434.00 ILS.
- Supplier 13 retains a 1,999.00 ILS debit balance (overpayment/advance);
  it was not silently altered.
- Zero-balance 2200.SS* legacy accounts were preserved for audit.
- DB migration: No.
- Applied: 2026-08-18 19:25:48

## P0.006 — Repair / Invoice Relationship
- Repair is operational; Invoice is commercial/accounting.
- Saving/editing Repair no longer auto-creates or rewrites an Invoice.
- Explicit Invoice creation + INVOICE GL are atomic.
- Posted invoices are immutable through Repair flows.
- One invoice per repair enforced with uq_invoices_repair_id.
- invoices.repair_id is authoritative; repairs.invoice_id is compatibility cache.
- Accounted Repairs cannot be deleted; formal void/reversal is required.
- 113/113 invoiced Repairs now have canonical links.
- 33 historical Repair.fileValue vs Invoice.total differences were preserved,
  not rewritten; they are marked isLedgerSynced=false.
- One genuine 39,600.00 ILS Repair without Invoice was preserved.
- No historical financial amount or GL amount changed.
- Applied: 2026-08-18 20:23:16

## P0.007 — Voucher Posting / Voucher Integrity
- P0.003 posting-status source-of-truth policy preserved.
- Payment voucher retries no longer repeat payment-log/settlement side effects.
- Supplier purchase-invoice settlement now uses TEXT/UUID invoice IDs.
- Explicit purchase invoice reference never spills to unrelated invoices.
- PaymentService no longer creates zero-value invoices from receipt flows.
- General client/on-account receipt without Repair is supported.
- Posted PAYMENT receipts fail closed on update/delete.
- Voucher screens block rapid double-submit while saving.
- One invalid invoice_settlements helper row was removed:
  5f7cfa02-19bc-4223-a55c-cb656f36acbe / 400.00 ILS / invoice_id=0.
- Added unique settlement side-effect index.
- Historical GL/voucher/receipt amounts unchanged.
- Known 2,000 ILS incomplete cheque voucher preserved for P0.008.
- New incomplete cheque posting fails closed until P0.008.
- Applied: 2026-08-18 20:45:56

## P0.008 — Cheque Integrity / Lifecycle
- Database version upgraded from 55 to 56.
- Cheque is now a first-class financial instrument with canonical schema.
- Added cheque_events audit trail and 1030 outgoing-cheque liability account.
- Incoming cheque receipt: Dr 1020 / Cr client AR.
- Incoming collection: Dr 1010 / Cr 1020.
- Own outgoing cheque issue: Dr AP/expense / Cr 1030.
- Own outgoing cheque bank clearance: Dr 1030 / Cr 1010.
- Return/cancel events use explicit corrective GL; due date alone never means returned.
- Endorsement uses canonical lifecycle accounting and no longer creates fake Payment rows.
- Legacy auto cheque-to-payment and dummy cheque-GL paths are blocked.
- Linked/accounted cheques cannot be destructively edited/deleted.
- Voucher/receipt + cheque + GL creation is atomic for future cheque transactions.
- Historical P-0009 / 2,000.00 ILS recovered as an incomplete linked outgoing cheque.
- Original cheque number/bank/drawer/due date were not stored and were not invented.
- Original GL #71 and P0.005 entry #429 remain immutable.
- Added P0_CHEQUE_FIX: Dr 1020 2,000 / Cr 1030 2,000.
- Supplier AP effect unchanged.
- Applied: 2026-08-18 22:36:26

## P0.009 — Repair Lines Integrity
- Database version upgraded from 56 to 57.
- repairs.parts + repairs.works established as canonical operational detail.
- repair_lines established as a normalized derived/query table.
- Historical repair_lines rebuilt from canonical Repair JSON:
  990 stale rows -> 984 canonical rows.
- Missing/non-positive legacy qty normalized to 1.
- Every repair line now stores explicit qty, price and total=qty*price.
- Repair JSON normalized to explicit qty/price/total fields.
- repair_lines database constraints enforce qty>0, price>=0 and valid total.
- RepairSaveService and RepairDatabaseService now write JSON + repair_lines
  from the same normalized data in one transaction.
- Future customer upgrades oldV<57 receive the same RepairLines migration.
- Repair fileValue total remains 372,110.00 ILS.
- Invoice and GL historical financial values unchanged.
- Applied: 2026-08-18 23:06:08

## P0.010 — Permanent Data Health & Accounting Repair Tool
- Final P0 stage.
- Database baseline upgraded v57 -> v58.
- invoice_settlements.invoice_id normalized from INTEGER to TEXT/UUID.
- Added persistent data_health_repair_log.
- Added Settings -> صحة البيانات والمحاسبة.
- Permanent checker statuses: PASS / WARNING / ERROR / REPAIRABLE.
- Checks cover SQLite integrity/FK, GL balance/duplicates/references,
  document posting coverage, posting caches, Repair/Invoice relationship,
  Repair detail cache, Supplier/AP policy, settlements and cheque integrity.
- Safe repair always creates a backup before deterministic repairs.
- Safe repair never updates/deletes historical GL or rewrites posted Invoice
  amounts / Repair.fileValue.
- Current blocking errors after P0.010: 0.
- Current deterministic repairable issues after bootstrap: 0.
- Current review warnings intentionally preserved: 3:
  33 Repair/Invoice historical differences (47,150 ILS absolute);
  one supplier advance/overpayment (1,999 ILS);
  one recovered legacy incomplete cheque.
- Historical financial totals unchanged.
- Applied: 2026-08-18 23:26:55

## P1.001 — Fresh Install / Upgrade Integrity
- Commercial DB location policy added:
  existing D:/YallaAccounts installation remains discoverable;
  fresh Windows installs use LOCALAPPDATA/Yalla Accounts/data.
- DBService is the single canonical SQLite lifecycle.
- Legacy DatabaseProvider no longer opens a second DB.
- Legacy payments.db removed from the active lifecycle; history is read-only
  against canonical payments and direct off-ledger writes fail closed.
- Legacy duplicate RepairDatabaseService path now exports the canonical service.
- Backup no longer uses destructive reset; WAL is checkpointed before copying.
- Restore validates candidate DB, creates a safety backup, and rolls back on failure.
- Production Reset DB action removed from workshop settings.
- Bootstrap fails closed if the financial DB cannot be opened/validated.
- Normal startup no longer runs mutating _postInit work outside migrations.
- Upgrade v51 no longer wipes legacy purchase detail columns.
- Fresh-install v58 and v57->v58 regression tests added.
- Live DB version remains v58; no financial data or schema changed.
- Applied: 2026-08-19 00:01:02

## P1.002 — Authentication / Activation / Owner Setup Hardening
- DB v58 -> v59 authentication schema.
- Fresh installations no longer seed universal users/shared passwords.
- First owner creation is explicit.
- New passwords use salted PBKDF2-HMAC-SHA256 (120,000 iterations).
- Existing legacy credentials remain usable for one migration login, are
  re-hashed on successful authentication, and require mandatory password change.
- Failed-login local lockout: 5 attempts / 15 minutes.
- Token-backed, revocable 30-day sessions replace boolean SharedPreferences login.
- Legacy login preference flags are ignored/removed.
- Startup/login/register/logout routes now use real auth screens.
- Business routes are protected by AuthenticatedRouteGate.
- Settings/subscription/admin/dev routes are owner-only.
- Password recovery now requires a one-time 10-minute reset grant.
- Direct password reset paths fail closed.
- Legacy default-admin alternate DB path disabled.
- Legacy bulk user/password/license generator disabled.
- Legacy activation-code batch seeding disabled.
- Embedded client-side activation signing secret removed.
- Licensing remains separated from access to existing financial data.
- Historical accounting/GL values unchanged.
- Applied: 2026-08-19 08:39:17

## P1.003 — Country / Currency / VAT / Numbering
- DB v59 -> v60.
- Country/base-currency/VAT configuration added.
- Historical ILS financial amounts preserved without conversion.
- VAT on historical documents not recalculated.
- document_sequences introduced.
- Voucher numbering now sequence-backed.
- Existing P-0001..P-0055 preserved; next payment voucher P-0056.
- Country presets added for Palestine, Jordan, Egypt and Gulf markets.
- Applied: 2026-08-19 09:42:37

## P1.004 — Currency / Tax Presentation Cleanup
- DB remains v60.
- Added canonical MoneyFormatter tied to P1.003 commercial settings.
- Commercial presentation settings load during bootstrap.
- 2/3-decimal currency display is configurable.
- Direct workshop-currency shekel presentation removed from UI/PDF/reports.
- Key purchase/repair/voucher monetary inputs follow currency precision.
- Base-currency changes are blocked after financial history exists.
- Historical amounts / VAT / GL / numbering unchanged.
- Subscription billing currency remains a separate commercial-pricing concern.
- Applied: 2026-08-19 10:30:54

## P1.005 — Posting Engine Audit & Consolidation
- DB remains v60; no migration.
- Added one production PostingEngine gateway.
- DBService posting/reversal APIs delegate to PostingEngine.
- Removed direct production AccountingTables posting/reversal bypasses.
- Legacy journal_entries and ledger_entries writes are fail-closed.
- Repair receipt + optional cheque + GL use one canonical PaymentService path.
- Arabic/English cheque aliases normalized.
- Linked cheque currency uses commercial base currency.
- Destructive posted-voucher GL deletion removed.
- Historical GL/data unchanged.
- Applied: 2026-08-19 11:04:33

## P1.006 — GL Core Hardening
- DB v60 -> v61.
- Added source_number, posting_version, reversal_of and created_by.
- Historical posting_version backfilled to v1.
- 55 voucher source numbers safely backfilled.
- 77 deterministic historical reversal links recorded.
- Unknown historical actor/timestamps were not fabricated.
- New authenticated postings capture created_by when the local session is known.
- New reversals use real reversal_of linkage and one-reversal-per-entry protection.
- DB-level UPDATE/DELETE protection added for posted gl_entries/gl_lines.
- Historical debit/credit and GL counts unchanged.
- Applied: 2026-08-19 11:30:48

## P1.007 — Chart of Accounts Hardening
- DB v61 -> v62.
- Added report_class, parent_id, is_postable, is_system, is_active and is_legacy.
- Account codes remain stable; no historical account_id rewrite.
- Existing account type/name/code identities preserved.
- Historical null normal_balance values normalized from existing account type.
- Parent hierarchy established for customer, employee and supplier subaccounts.
- Core AR/AP/employee-payable roots are system-managed non-postable headers.
- Legacy 1200.E employee-advance accounts preserved and made non-postable.
- Legacy 2000.S and 2200.SS supplier aliases retired without deleting history.
- Canonical employee advances now use 1120.E<employeeId>.
- Canonical supplier lookup uses 2200.S#### and no longer depends on removed suppliers.account_id.
- Purchase flow no longer creates 2200.SS#### aliases.
- Invoice GL uses the canonical customer AR subaccount.
- PostingEngine rejects normal posting to inactive/non-postable accounts.
- Formal reversals remain able to reverse historical entries on retired accounts.
- Historical GL account IDs and debit/credit totals unchanged.
- Applied: 2026-08-19 12:54:46


## SEC.006 — Activation API + First Online Activation
- Client DB v64 -> v65.
- Added local signed activation receipt/state bound to organization + installation + device.
- Fresh ownerless installations now route to online activation before First Owner creation.
- Existing installations with users remain accessible; expiry/read-only enforcement is deferred to SEC.011.
- Added one-time server activation grants stored as SHA-256 hashes only.
- Added short-lived server activation challenges and Ed25519 device proof-of-possession contract.
- Signed license envelope is verified client-side before local activation is committed.
- Activation code is never persisted locally and plaintext grant codes are never stored server-side.
- Production signing private key remains KMS/HSM/secret-store only.
- Commercial plan/pricing seeding remains NONE.


## SEC.007 — First Owner Bootstrap
- Client DB v65 -> v66; server model remains v4.
- Added one-time owner_bootstrap_state bound to the local organization.
- First Owner creation requires a currently verified SEC.006 activation.
- Owner, workshop identity, recovery-code hash and bootstrap completion commit atomically.
- Recovery code is displayed once; plaintext recovery code is never persisted.
- Existing installations with one owner are reconciled to COMPLETED without changing owner ID/password hash.
- Database-level unique owner-per-organization guard added.
- Additional-user creation remains deferred to SEC.008/SEC.009.

## SEC.008 — Users / Roles / Permissions
- Added canonical local role and permission catalogs.
- Added nine system roles and 28 permission keys.
- Added service-layer permission enforcement for user administration.
- Enabled additional local users after First Owner bootstrap; seat limits remain deferred to SEC.009.
- Replaced hard user deletion with session-revoking soft disable.
- Preserved existing owner identity, user IDs, password hashes, and accounting history.

## SEC.009 — Licensed User Seats
- Client DB remains v67; server model remains v4.
- MAX_USERS is enforced from the currently verified signed license only.
- Local SQLite values cannot raise the seat limit.
- The workshop owner consumes one active seat.
- Active additional users consume seats; frozen/inactive users do not consume a seat until reactivation.
- Active-user creation and reactivation fail closed when the signed license is missing, invalid, expired, tampered, organization-mismatched, or out of seats.
- Seat checks and user activation/creation are transactionally serialized in SQLite.
- Existing users, user IDs, password hashes, role assignments, and accounting history are not rewritten.


## SEC.011 - Expiry / Read Only / Renewal / Suspension

- Client DB v68 adds `license_runtime_state` and DB-level operational write guards.
- Expired/suspended/revoked signed authorization becomes READ ONLY.
- View/report/print/export/backup and authentication/recovery remain available.
- Explicit online validate/renew protocol added; periodic cadence remains SEC.012.
- Server licensing model advanced to v6.
- Historical accounting data rewrite: NONE.

## SEC.012 - Periodic Online Validation + Grace Period
- Added signed periodic validation deadlines to license envelopes.
- Default server policy: 30-day online validation interval + 7-day offline grace.
- Added local validation-state projection and DB-level grace-expiry write guards.
- Added non-blocking startup/hourly validation scheduler using SEC.011 device-proof VALIDATE flow.
- Client DB v69; licensing server model v7.
- Historical accounting data rewrite: NONE.


## SEC.013 - Yalla Control Center
- Client DB remains v69; no client schema or historical accounting data changes.
- Licensing server model advances from v7 to v8.
- Added an independent Yalla-only Control Center shell, outside the customer desktop app.
- Added canonical read models for Dashboard, Organizations, Subscriptions, Licenses, Devices, Plans, Features, Entitlements, Activations, Renewals, Overrides, Security Events, Audit Logs and Yalla Admin Users.
- Control Center API surface is GET/read-only in SEC.013.
- YALLA_SUPER_OWNER and YALLA_BREAK_GLASS mutation authorization remain deferred to SEC.014.
- Authentication/session/recovery/audit immutability hardening remains deferred to SEC.015.
- No private signing key, master password, universal admin password, or server secret is added to the repository/client.
- Historical accounting data rewrite: NONE.


## SEC.014 - YALLA_SUPER_OWNER + Break Glass Overrides

- Client SQLite remains v69; no historical accounting data rewrite.
- Licensing server model v8 -> v9.
- Added server-only Yalla admin RBAC with YALLA_SUPER_OWNER and YALLA_BREAK_GLASS.
- Added 39 canonical permissions and 38 privileged action codes covering owner commercial/licensing controls.
- Force/emergency operations require the specific permission plus an active organization-scoped 5-60 minute Break Glass grant.
- Added one-time super-owner ownership binding to an existing ACTIVE Yalla admin identity; no credentials/master password are created.
- Added privileged action request and license issuance request models. Private signing keys remain server KMS/HSM/secret-store only.
- Added audit delete protection and full Break Glass who/when/organization/reason/expiry/IP/device fields.
- Updated Yalla Control Center with authorization identity, privileged action, Break Glass, and action/audit views.
- Customer password visibility remains impossible; reset/unlock/session revocation and admin auth/session hardening continue in SEC.015.

## SEC.015 - Security / Recovery / Sessions / Audit
- Server licensing model v10; client DB remains v69.
- Added real Control Center admin credential enrollment/login boundary with Argon2id hash storage and secret-store pepper boundary.
- MFA mandatory for YALLA_SUPER_OWNER / YALLA_BREAK_GLASS; TOTP secrets remain outside PostgreSQL.
- Replaced pasted browser bearer token with Secure/HttpOnly/SameSite session-cookie contract plus anti-CSRF.
- Added 15m access, 30m idle, 12h absolute session policy; refresh rotation/reuse detection and session revocation.
- Added one-time recovery/enrollment challenges and single-use recovery-code digests.
- Break Glass now requires fresh same-session MFA reauthentication (default 5 minutes).
- Audit UPDATE and DELETE blocked; administrative audit chain seals use RFC8785-JCS + SHA-256.
- Historical accounting data rewrite: NONE.


### SEC.015 V5 - Customer authentication UX completion

- Completed customer-facing authentication UX without changing client DB v69.
- Login now supports password visibility, remembered username, optional keep-signed-in, and clear guidance that passwords are never stored locally.
- Persistent customer session material moved to Windows secure storage through `flutter_secure_storage`; non-persistent sessions remain process-local only.
- Added one-time First Owner entry point when the activated installation has no users.
- Added owner-only user management UI for canonical SEC.008 roles, user activation/freeze, temporary password reset, and forced password change on next login.
- Added Account & Security screen for own-password change, owner recovery-code rotation, forgotten-device cleanup, and session revocation.
- Added owner username/password recovery flow using one-time recovery code or previously configured security answers; ordinary-user password recovery remains owner-controlled.
- Added show/hide controls to login, owner setup, add-user, temporary-reset, and password-change fields.
- No plaintext password persistence and no password-visibility capability for Yalla administrators.

## YALLA OFFICIAL CHECKPOINT — P08-P18 ALL PASS
- Checkpoint: 2026-09-06 12:59:36
- P08 through P18: PASS / CLOSED.
- P18 live database integrity contract: PASS.
- APK release build: PASS.
- AAB release build: PASS.
- Android release blocker: CLOSED.
- No DB reset.
- No migration.
- No Codemagic action.
- Analyzer: 46 non-blocking warnings/info remain for separate cleanup.
- Project currently has no Git repository.
- Do not infer or create P19 without an explicit official phase definition.
