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
