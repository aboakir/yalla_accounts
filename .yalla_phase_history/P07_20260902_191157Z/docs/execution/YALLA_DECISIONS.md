# Yalla Accounts Mobile V2 — Locked Decisions

These decisions stay in force unless Luay explicitly changes them.

## Product

1. Launch Yalla Garage first. Keep the incomplete Insurance Agent workspace hidden.
2. The repair file is the operational and profitability center of the product.
3. Mobile navigation stays focused on Today, Repairs, Collection, and More.
4. Non-accountants see business actions; accounting mechanics stay behind the scenes.
5. No production placeholder, raw UUID, mojibake, giant gray failure area, or Reset DB.

## Financial integrity

1. File total, paid amount, remaining amount, customer statement, and reports must reconcile.
2. Overpayment is customer credit; it is never displayed as a negative remaining amount.
3. Posted financial actions are reversed with audit, not hard-deleted or silently edited.
4. Database or posting-rule changes require migration, backup, and reconciliation tests.

## Technical and delivery

1. Official project name is `yalla_accounts`.
2. Official Windows path is `E:\flutter_projects\yalla_accounts`.
3. The installer must refuse every project whose name or path differs from the official values.
4. Breakpoints: phone `<600`, tablet `600..1023`, desktop `>=1024`.
5. Every phase uses ZIP + apply + rollback + manifest + guards + tests.
6. No phase or checkpoint is PASS without real command output.
7. Every three phases require a real iPhone IPA checkpoint before continuing.
8. No automatic Git push, destructive cleanup, or database reset.

## First-release exclusions

Advanced insurance-agent workflows, payroll, advanced inventory, multi-branch, OCR/AI,
and direct insurer integrations are postponed and must not appear as incomplete screens.


## P02 security decisions
- PIN hashes are stored only in platform secure storage; plaintext PIN is never persisted.
- Biometric authentication uses OS local authentication and never replaces the commercial license gate.
- Device unlock requires a previously authenticated persisted session and therefore supports offline re-entry without creating a new offline identity.
- Customer phone verification MUST be server-authoritative. A local/generated OTP is explicitly forbidden.

- Customer OTP plaintext must never be returned by an API or persisted in client/server state.
- Production SMS delivery credentials/configuration are server-side only. The canonical adapter is `YALLA_SMS_WEBHOOK_URL` over HTTPS with optional `YALLA_SMS_WEBHOOK_TOKEN`.
- The SEC.015A loopback console OTP diagnostic is development-only and cannot be used as a production delivery mechanism.


## P03 decision — phone Home hierarchy
- Phone Home is decision-first: Today summary → Needs attention → Quick actions → Recent files.
- Do not manufacture delivery/collection semantics when the database does not provide an authoritative event.
- `payments`, `cheques`, `repairs`, and workshop/commercial settings remain the source of truth for P03.
- Desktop remains on the existing dashboard; P03 does not make Desktop imitate Phone.
- P03 completion transitions to checkpoint C01, not directly to P04.

## P04.1 decision — mobile database encryption boundary
1. Canonical iOS/Android Yalla Accounts DB is encrypted with SQLCipher.
2. Key is a random 256-bit installation secret stored only in platform secure storage; never hard-coded/logged/stored in SQLite/preferences.
3. Legacy plaintext mobile DB is exported to a new encrypted DB, validated, then atomically swapped with rollback protection.
4. Key mismatch/unreadable DB fails closed; production never resets or silently replaces customer data.
5. DB schema version remains unchanged; encryption is a storage-format/security transition.
6. Windows/Desktop keeps existing SQLite + sqflite_common_ffi in P04.1.
7. Same-install encrypted backups and legacy plaintext backups remain validation-compatible; portable encrypted backup/key envelopes are P16 scope.
8. Physical mobile encryption migration is verified at C02 before P07.

## P04.2 decision — local-first write and transactional Outbox
1. A user-facing save must commit locally before any network dependency. Connectivity is never a prerequisite for a valid local save.
2. Syncable mutations are recorded in the same SQLite transaction as the local business mutation; local data and Outbox intent cannot diverge because of a crash between two commits.
3. `idempotency_key` is unique when present. Re-enqueueing the same logical mutation is a no-op rather than a duplicate server intent.
4. The existing legacy `outbox_messages` table is upgraded in place; old rows are preserved and no table reset/rebuild is allowed.
5. P04.2 establishes storage and retry semantics only. It does not contact a server and does not mark queued work sent without an acknowledgement.
6. Retry state is durable and uses bounded exponential backoff. A process interrupted while `sending` is returned to a retryable failed state on recovery.
7. The first wired golden path is repair creation. P05/P06 will extend the same transaction-boundary contract to the client/vehicle/repair flows they own.

## P04.2C decision — current-v69 Outbox compatibility
1. The live project already contains the P04.2 Outbox implementation; P04.2C completes and validates that implementation instead of reapplying it.
2. Because deployed databases are already v69, Outbox compatibility cannot depend on an `oldV < 68` branch. It must be idempotently ensured from `_postInit`.
3. The compatibility ensure may add only missing Outbox columns/indexes and project legacy `sent` state; it must not drop/rebuild the table or delete queued rows.
4. Any row left in `sending` across process restart is stale and becomes retryable before a future drain begins.
5. P04.2C still performs no network I/O. Transport, acknowledgement handling, sync indicator and coordinated drain remain later P04 work.

## P04.3 decision — truthful sync indicator and transport boundary
1. The UI may display `متزامن` only when a configured transport has acknowledged the queue and no unsent rows remain.
2. When no production workshop-sync transport exists, the UI says `محفوظ محليًا` and, when applicable, shows the number waiting for sync. It must not manufacture a cloud-success state.
3. The coordinator serializes drain execution. Multiple app-resume/manual triggers cannot concurrently send the same queue.
4. `sent=1` is written only after an accepted acknowledgement whose idempotency key exactly matches the queued mutation.
5. Network timeout/socket/OS failures preserve the local business transaction, record retry metadata and stop the current drain to avoid hammering an unavailable connection.
6. A real backend adapter must implement `OutboxSyncTransport`; P04 does not invent an endpoint absent from the source of truth.
7. The visible indicator is attached to the existing shared mobile bottom navigation, preserving the approved P03 route/shell architecture.

## P04.3A decision — phase tests must not prohibit legitimate completion
A subphase regression test may lock functional/security invariants introduced by
that subphase, but it must not require the parent phase to remain `IN_PROGRESS`
forever. P04.1 therefore accepts both P04 `IN_PROGRESS` and `PASS`.

## P05 decision — canonical client/vehicle identity
1. Client records remain the existing `clients` table with integer IDs and existing AR-account linkage.
2. Vehicle identity becomes a canonical `vehicles` table keyed by a unique normalized vehicle number; historical repairs remain the source of vehicle repair history.
3. P05 backfills vehicles from existing repairs without rewriting/deleting repair rows and without changing DB version.
4. Client deletion is prohibited while repair/vehicle history exists. Historical business records take precedence over destructive convenience.
5. Vehicle number editing is locked once a repair history exists; users may edit type/model/owner/notes without detaching old history.
6. Repair creation upserts canonical client and vehicle master data inside the repair transaction.
7. Client/vehicle mutations follow the P04 local-first Outbox contract. No server endpoint is invented.

## P05B decision — resolve symbol collision, not behavior
The P05 analyzer delta was a namespace collision only. The fix aliases `intl`
instead of changing RTL behavior or the vehicle history UI contract.

## P06 decision — archive is operational state, not payment state
1. `repairs.isArchived` is the sole archive truth. `paymentStatus == مسدد` must not silently move a repair into the archive.
2. Archive/restore is explicit, reversible, and financially inert: no file value, payment, invoice, GL, ledger or client data may change.
3. Archive/restore follows P04 local-first behavior and queues an Outbox UPSERT in the same SQLite transaction.
4. The canonical P06 list route is `/repairs/list`, backed by the already-approved `RepairsScreen`; `/repairs` remains the summary/overview route.
5. The global mobile route frame must not wrap `RepairsScreen` a second time on `/repairs/list`, because that screen already owns its phone drawer/bottom navigation.
6. Search/filter behavior must be deterministic and shared across phone/tablet/desktop through `RepairListFilter`.
7. P07 may not start before C02 real-iPhone PASS.
