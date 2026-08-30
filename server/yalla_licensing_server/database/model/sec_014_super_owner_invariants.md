# SEC.014 Super Owner / Break Glass invariants

1. `YALLA_SUPER_OWNER` exists only in the licensing server control plane; it is not a customer SQLite role.
2. No universal/master password is embedded in the customer client, Control Center, migration, or patch.
3. A privileged action is authorized server-side by an ACTIVE Yalla admin identity, ACTIVE role assignment, ACTIVE permission, and the canonical action catalog.
4. Actions marked `requires_break_glass=true` require a short-lived grant belonging to the same actor and target organization.
5. A break-glass grant requires a meaningful reason, is organization-scoped, and lasts 5-60 minutes only.
6. Every break-glass open/revoke is written to `audit_logs`; privileged mutation handlers must record before/after/reason/expiry/IP/device when available.
7. Audit events cannot be deleted. SEC.015 adds broader session/recovery/tamper-evident audit hardening.
8. The first super-owner role can be assigned only once to an existing ACTIVE admin identity. No credentials are created by the bootstrap function.
9. The last ACTIVE super owner cannot be revoked/deleted by normal role mutation.
10. License signing remains a server KMS/HSM/secret-store operation. Control Center can authorize an issuance request but never receives private signing-key bytes.
11. Customer passwords are never readable by Yalla administrators. Password reset/unlock/session revocation are SEC.015 operations, never SHOW PASSWORD.
12. Client DB remains v69 and historical accounting data is untouched.
