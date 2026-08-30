# SEC.015 Security / Recovery / Sessions / Audit invariants

1. Control Center authentication exists only on the licensing server; the customer desktop client receives no Yalla admin credential or session secret.
2. Admin passwords are stored only as Argon2id PHC hashes. Plaintext passwords and the password pepper never belong in PostgreSQL, browser storage, source code, or ZIP patches.
3. `YALLA_SUPER_OWNER` and `YALLA_BREAK_GLASS` require MFA. TOTP secret bytes live in the approved server secret store; WebAuthn stores public credential material only.
4. Browser authentication uses Secure + HttpOnly + SameSite=Strict cookies. Access/refresh bearer tokens are not written to localStorage or sessionStorage.
5. State-changing Control Center requests require an anti-CSRF token in addition to the authenticated cookie.
6. Access lifetime defaults to 15 minutes, idle lifetime to 30 minutes, and absolute session lifetime to 12 hours. Refresh tokens rotate; reuse marks the family compromised and revokes it.
7. Break Glass requires MFA step-up reauthentication no older than 5 minutes and tied to the same admin session.
8. Recovery/enrollment challenges are one-time, bounded by attempts and expiry, and persisted only as digests where a secret token is involved.
9. Recovery codes are single-use digests. They are shown only at generation time and never recoverable from PostgreSQL.
10. Login failure responses do not reveal whether an email exists. Account/IP throttling and bounded lockout are mandatory.
11. Admin sessions can be individually revoked or globally revoked without exposing any token.
12. `audit_logs` is immutable for UPDATE and DELETE after SEC.015. Control Center audit events are hash-chain sealed using RFC8785-JCS + SHA-256.
13. The audit hash chain is tamper-evident, not a substitute for protected database backups or external anchoring.
14. Customer passwords remain invisible to Yalla administrators. No SHOW PASSWORD, master password, or customer-client backdoor exists.
15. Client DB remains v69 and historical accounting data is untouched.
16. Clock rollback/device anti-tamper hardening remains SEC.016.
