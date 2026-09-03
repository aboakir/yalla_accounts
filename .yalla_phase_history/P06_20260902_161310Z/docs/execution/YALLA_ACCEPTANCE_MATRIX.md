# Yalla Accounts Mobile V2 — Acceptance Matrix

## Universal gate for every phase

- The project guard confirms `pubspec.yaml` contains `name: yalla_accounts`.
- The resolved project path exactly matches the approved Yalla Accounts project path.
- Payload hashes match `manifest.json` before copying.
- A targeted backup exists before overwriting any target.
- `dart format` verification passes for changed Dart files.
- `flutter analyze` passes.
- Phase-targeted tests pass.
- The required platform build passes.
- Rollback can restore the exact pre-phase files.
- Execution memory and changelog are updated.
- No unrelated file is changed by the installer.

## P01 acceptance criteria

1. Five permanent execution-memory files exist under `docs/execution`.
2. The state JSON records the real Git branch/commit/status plus Flutter and Dart versions.
3. The project contains isolated, compiling design tokens and breakpoint helpers.
4. Shared components compile without modifying existing screens.
5. The breakpoint test validates phone `<600`, tablet `600..1023`, desktop `>=1024`.
6. The minimum interactive dimension is at least 48 logical pixels.
7. The installer refuses any path or project not matching Yalla Accounts.
8. Analyzer, targeted test, and Windows debug build complete successfully.
9. The terminal prints exactly `YALLA P01 RESULT: PASS` at the end.

## P01 does not do

- It does not redesign a user-facing screen.
- It does not change navigation.
- It does not change the database or business logic.
- It does not remove or rename an existing feature.
- It does not push to GitHub.


## P02 acceptance — current status
- [x] Mobile-first login / existing-account entry foundation.
- [x] First-owner four-step workshop setup flow.
- [x] PIN stored via platform secure storage using canonical password hashing.
- [x] Biometric / Windows Hello integration when supported.
- [x] Offline unlock only for a previously valid persisted local session.
- [x] Account recovery paths preserved.
- [x] Commercial access and activation authority preserved.
- [x] Authoritative customer phone SMS OTP start/verify/consume integration with server-side delivery adapter, expiry, resend throttling, attempt limits, digest-only persistence, and one-time phone-bound verification token.


### P02 completion gate
- P02 OTP integration self-test must print `P02 CUSTOMER PHONE OTP INTEGRATION: PASS`.
- P02 targeted Flutter tests and Stage 02/03/SEC.015 regressions must pass.
- R11 adaptive test is evaluated against its pre-patch baseline; P02 may introduce zero new R11 failures.
- Analyzer differential must report zero new ERROR diagnostics.
- Windows release build must pass.
- Final terminal marker: `YALLA P02 RESULT: PASS`.


## P03 acceptance
- [x] Phone bottom navigation has Home / Repairs / Add / Finance / More.
- [x] Add opens an action sheet rather than routing blindly to one feature.
- [x] Home exposes Today summary, quick actions, Needs attention, recent files, and basic alerts.
- [x] Home values are backed by current DB tables; no demo/fake activity is introduced.
- [x] Existing Desktop dashboard is preserved.
- [x] No customer DB migration/reset.
- [x] No Stage04 semantic change.
- [x] P03 closes into C01 checkpoint; P04 remains blocked until C01 PASS.

## C01 FIX3D — iPhone visual/encoding repair
- [x] Rebuild from the exact read-only live-source snapshot after FIX3/FIX3A guard mismatch.
- [x] Sidebar Arabic literals are readable UTF-8 and known mojibake markers are absent.
- [x] P03 Home dates are normalized to `dd-MM-yyyy` before RTL rendering.
- [x] Phone repair-card separator no longer renders as `آ·`.
- [x] Routes/menu structure, P01/P02/P03 scope, accounting logic, and commercial entitlements are unchanged.
- [x] No database migration/reset; P04 remains blocked.
- [ ] Local analyzer/tests/Windows build must PASS.
- [ ] Fresh unsigned C01 IPA must be built.
- [ ] Human iPhone retest must PASS before C01 is marked PASS.

## C01 FIX4 — PHONE Repair Reports responsive chart
- [x] Repair Reports keeps the existing data/filter/accounting logic unchanged.
- [x] PHONE bar chart hides top/right axes explicitly.
- [x] Left Y-axis has explicit reserved width and compact single-line labels.
- [x] Numeric chart rendering is isolated in LTR without changing Arabic page RTL.
- [x] Chart drawing is constrained by a Flutter `ClipRect` wrapper and phone height is increased slightly to avoid visual crowding.
- [x] FIX3D Arabic/date/separator repairs are guarded against regression.
- [x] No database migration/reset; P04 remains blocked.
- [ ] Local analyzer/tests/Windows build must PASS.
- [ ] Fresh unsigned C01 IPA must be built.
- [ ] Human iPhone retest of Repair Reports + Needs Attention must PASS before C01 is marked PASS.


### C01 FIX4A installer guard acceptance
- [x] Prior FIX4 failure occurred before backup/payload application; project files remained untouched.
- [x] Non-payload FIX3D files are not byte-hash guarded because `dart format` may legitimately normalize them.
- [x] Sidebar Arabic, Home date formatting, and repair-card separator remain regression-tested.
- [x] Exact source guard remains mandatory for `repair_reports_screen.dart` and the execution-state documents that FIX4A overwrites.


### C01 FIX4B API compatibility acceptance
- [x] FIX4A analyzer failure is treated as a package failure and its automatic rollback completed successfully.
- [x] Unsupported `BarChartData.clipData` is absent.
- [x] Flutter `ClipRect` is used outside `BarChartData`, compatible with the current chart package API.
- [x] The same PHONE axis-width, compact-label, hidden top/right axis, Arabic/date regression contracts remain enforced.
- [ ] Local analyzer/tests/Windows build must PASS before a new IPA is built.

## P04 acceptance — IN PROGRESS

### P04.1 encrypted local database
- [x] C01 human iPhone checkpoint PASS before P04.
- [x] iOS/Android canonical DB open uses SQLCipher with non-hardcoded password.
- [x] 256-bit random key stored through `FlutterSecureStorage`.
- [x] Legacy plaintext conversion uses `sqlcipher_export()` into a separate file.
- [x] Plaintext remains recoverable until encrypted-copy validation succeeds.
- [x] Validation covers cipher runtime, integrity, foreign keys, table set, and row counts.
- [x] Interrupted swap fails closed and never invokes Reset DB.
- [x] Desktop SQLite/FFI lifecycle and DB path remain unchanged.
- [x] DB schema version unchanged.
- [x] Backup validation supports current-key encrypted and legacy plaintext DBs.
- [ ] Local P04.1 analyzer/tests/Windows release build PASS.
- [ ] Real iOS SQLCipher open/migration verified at C02.

### Remaining P04 items
- [ ] Offline save contract.
- [ ] Outbox for pending operations.
- [ ] Sync-state indicator.
- [ ] Idempotency / duplicate-operation prevention.
- [ ] Connection-failure handling.
- [ ] P04 remains IN PROGRESS until all items pass.

### P04.2 offline save + Outbox foundation
- [x] Local save does not require a connectivity/network check.
- [x] `outbox_messages` is upgraded without deleting legacy rows.
- [x] Outbox payload uses real JSON.
- [x] Outbox records operation, entity type/id, unique idempotency key, state, attempts, next retry, and last error.
- [x] Duplicate enqueue with the same idempotency key is ignored.
- [x] Retry metadata is durable and bounded exponential backoff is defined.
- [x] Interrupted `sending` rows can be returned to a retryable state.
- [x] Repair creation writes its Outbox intent inside the same SQLite transaction as the repair.
- [x] No network transport is introduced in this substep.
- [ ] P04.2 focused database/idempotency tests, analyzer differential, accounting differential, and Windows release build must PASS.

### P04.2C completion acceptance
- [x] Live-source diagnostic confirms the P04.2 Outbox implementation is present.
- [x] Repair save and Outbox enqueue remain inside the same SQLite transaction.
- [x] Retry exponent uses integer arithmetic.
- [x] Existing v69 databases run `ensureP04OutboxSchema()` from `_postInit`.
- [x] Interrupted `sending` state is recovered on startup.
- [x] No network transport is started.
- [x] DB version remains 69 and no destructive Outbox rebuild is introduced.
- [ ] P04.2C focused tests + phase04 tests + lifecycle/iOS regressions + accounting/R11/analyzer differentials + Windows release must PASS locally.

### P04.3 sync state + drain/failure handling
- [x] Shared phone navigation contains a compact sync-state indicator.
- [x] Indicator derives pending/failed/sending counts from the durable Outbox.
- [x] No transport configured => indicator says locally saved, never falsely synced.
- [x] Drain execution is serialized.
- [x] Idempotency key is carried to the transport boundary and validated on acknowledgement.
- [x] A row is marked sent only after an accepted matching acknowledgement.
- [x] Socket/OS/timeout failure keeps the local mutation and writes retryable Outbox failure state.
- [x] App-resume can trigger a coordinated retry.
- [x] No workshop-sync endpoint/URL is invented when none exists in current source.
- [x] DB version remains 69; no reset/destructive migration is introduced.
- [ ] P04.3 focused tests + full phase04 tests + lifecycle/iOS DB regressions + accounting/R11/analyzer differentials + Windows release build must PASS locally.

### P04 phase result
- [x] Encrypted mobile DB architecture implemented; physical iOS runtime verification remains at C02.
- [x] Offline local save foundation.
- [x] Durable Outbox.
- [x] Sync-state indicator.
- [x] Duplicate-operation prevention through idempotency.
- [x] Connection-failure/retry handling.
- [x] P04 becomes PASS after the local gates above pass.

### P04.3A regression alignment
- [x] P04.1 encryption/security assertions remain intact.
- [x] The legacy chronology assertion no longer blocks a legitimate P04 PASS transition.
- [ ] Full P04 suite, lifecycle/iOS DB regressions, accounting/R11/analyzer differentials and Windows release build must PASS.

## P05 acceptance — Clients + Vehicles
- [x] Client list remains searchable/filterable.
- [x] Client add/edit is available and edit preserves notes.
- [x] Client profile exposes linked vehicles and recent repair history.
- [x] Client duplicate checks use normalized identity while preserving existing data.
- [x] Destructive client delete is blocked when history exists.
- [x] Canonical vehicle table is created idempotently without DB version bump.
- [x] Existing repair vehicle data is backfilled without rewriting repairs.
- [x] Vehicle list/search is backed by canonical vehicle records.
- [x] Vehicle add/edit is available.
- [x] Vehicle history is derived from existing repair history.
- [x] Normalized vehicle number has a unique DB index.
- [x] Repair creation upserts canonical client + vehicle inside the repair transaction.
- [x] C01 phone sidebar guard remains width >= 600.
- [ ] P05 focused tests + P04 regression + DB lifecycle/iOS DB + accounting/R11/analyzer differentials + Windows release build must PASS locally.

### P05B analyzer correction
- [x] The only P05-introduced analyzer error identified by P05A is corrected.
- [x] Flutter `TextDirection.rtl` remains the intended UI direction.
- [x] `intl.DateFormat` remains the date formatter.
- [ ] Full P05 gates must PASS locally.
