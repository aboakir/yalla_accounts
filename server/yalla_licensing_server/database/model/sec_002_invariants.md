# SEC.002 data-model invariants

1. `organization_id` is the permanent tenant key and is the same UUID family established by SEC.001.
2. The desktop SQLite database remains accounting/operational storage; the server model is not copied into it.
3. A license belongs to exactly one organization, subscription and device.
4. A device has a globally unique `installation_id` and public key.
5. Activations are idempotent through `request_idempotency_key`.
6. Renewal, suspension and override history is explicit; commercial state is not inferred from mutable client preferences.
7. Override records carry before/after state, reason, actor and optional expiry.
8. Audit/security tables are append-oriented. Hard immutability enforcement is implemented in SEC.015.
9. Plans exist now only as stable identities. Feature/seat/device entitlement rules are implemented in SEC.003.
10. Cryptographic signing material is not represented in this schema; signing authority is SEC.004.
11. No destructive cascade is allowed on core commercial entities (`ON DELETE RESTRICT`).
12. Client DB version stays at v63 in SEC.002.
