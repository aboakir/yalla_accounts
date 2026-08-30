# Stage 02 - Login / Subscription / Roles / Activation Completion

Commercial protected access is authorized only by the following canonical chain:

User -> Organization -> Role -> Subscription -> License -> Device -> Installation

Rules:
- A local user must be active and bound to the singleton organization identity.
- The user's role must exist in the canonical RBAC tables and have permissions.
- First Owner bootstrap must be completed.
- The current installation must hold an authentic signed license.
- The signed license organization must match the user's organization.
- The signed license must contain a subscription id and device/installation binding.
- Legacy per-user trial/payment dates and local subscription rows are presentation/legacy data only and cannot authorize access.
- Suspended/expired/revoked signed lifecycle states remain authenticated but read-only, preserving SEC.011 DB enforcement.
- Activation remains a public recovery/setup route; protected business routes cannot bypass this gate.

No client DB schema migration is introduced by Stage 02 R1.
