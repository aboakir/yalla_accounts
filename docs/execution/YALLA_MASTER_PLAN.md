# Yalla Accounts Mobile V2 — Master Plan

Plan ID: `YAP-MOBILE-V2`  
Official project: `yalla_accounts`  
Official Windows path: `E:\flutter_projects\yalla_accounts`  
Pre-plan reference: `R11.12 PASS`.

## Status symbols

- `PASS`: completed and verified locally.
- `IN_PROGRESS`: currently being implemented or fixed.
- `BLOCKED`: cannot continue until the blocker is resolved.
- `PENDING`: not started.

## Mandatory execution cycle

Every phase is delivered as an independent ZIP with project guards, targeted backup,
apply, verification, rollback, manifest, tests, and updated execution memory. A later
phase cannot start before the previous phase is `PASS`.

Every three phases create one iPhone checkpoint:

`3 phases -> local verification -> unsigned IPA -> Sideloadly -> real iPhone test -> checkpoint PASS`

## Phases

### Cycle C01 — Foundation and entry

1. `P01` Baseline, execution memory, safety guards, and isolated design foundation.
2. `P02` Sign-in, account recovery, and first workshop setup.
3. `P03` Mobile shell, role-aware navigation, and the Today dashboard.

Checkpoint: `C01 IPA`.

### Cycle C02 — Core data and repair list

4. `P04` Encrypted local storage, outbox, and foundational offline sync.
5. `P05` Customers and vehicles.
6. `P06` Repair list, search, filters, statuses, and archive.

Checkpoint: `C02 IPA`.

### Cycle C03 — Workshop operation

7. `P07` New repair intake wizard, photos, fuel, mileage, damage, and signature.
8. `P08` Repair details architecture, timeline, attachments, and independent statuses.
9. `P09` Damage assessment, estimate versions, approval, work order, and progress.

Checkpoint: `C03 IPA`.

### Cycle C04 — Financial truth and collection

10. `P10` One financial source of truth and migration/reconciliation of legacy totals.
11. `P11` Payments, allocation, receipts, reversal, and customer credit.
12. `P12` Receivables, checks, due dates, collection alerts, and customer statement.

Checkpoint: `C04 IPA` plus mandatory financial reconciliation.

### Cycle C05 — Close, profitability, and documents

13. `P13` Quality control, delivery, closure, signature, and warranty.
14. `P14` Purchases, materials, parts, external services, and repair profitability.
15. `P15` Repair PDF, estimate, invoice, receipt, reports, print/share, and global search.

Checkpoint: `C05 IPA` plus PDF/data comparison.

### Cycle C06 — Security, hardening, and launch

16. `P16` Roles, audit trail, backup, restore, and desktop-data migration.
17. `P17` Performance, image compression, RTL, accessibility, error states, and regression tests.
18. `P18` Pilot workshops, package limits, store readiness, and release candidate.

Checkpoint: `C06 Release Candidate IPA` and final `GO / NO-GO` gate.

## Out of scope for the first release

- Full Insurance Agent workspace.
- Advanced HR and payroll.
- Advanced multi-warehouse inventory.
- Multi-branch management.
- OCR and AI automation.
- Advanced accounting dashboards.
- Direct policy issuance or insurer integrations.

These modules must remain hidden; no placeholder screen is allowed in production.

## Continuity rule

The current truth is stored in this file plus:

- `YALLA_PROJECT_STATE.json`
- `YALLA_CHANGELOG.md`
- `YALLA_DECISIONS.md`
- `YALLA_ACCEPTANCE_MATRIX.md`

At the end of every phase, all five files must be updated and included in the next ZIP.
In a new conversation, the latest files — not chat memory — define what is completed.
