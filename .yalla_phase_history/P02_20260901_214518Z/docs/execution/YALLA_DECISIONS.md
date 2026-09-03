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
