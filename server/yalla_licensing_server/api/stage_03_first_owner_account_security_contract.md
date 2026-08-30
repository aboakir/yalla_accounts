# Yalla Accounts - Stage 03 First Owner Setup & Account Security

## Scope

Stage 03 closes the local customer-account security boundary after Stage 02.

### Invariants

1. First Owner is created only through the activation-gated one-time bootstrap.
2. Existing users are never silently promoted to owner during login, lookup, recovery, or session restore.
3. A non-empty user set requires exactly one canonical owner linked to:
   - the current organization identity;
   - `owner_bootstrap_state.status = COMPLETED`;
   - the same `owner_user_id`;
   - canonical `role = owner`;
   - active account status.
4. `owner_bootstrap_state = PENDING` requires an empty pre-bootstrap user set.
5. Sensitive owner security changes require a current authenticated owner session plus password reauthentication.
6. Creating a new recovery code replaces the previous code and stores only a salted password hash of the code.
7. Issuing a new password-reset grant invalidates any previous unused reset grant for the same user.
8. Password-reset grants remain short-lived, hashed at rest, one-time, and revoke existing customer sessions after successful reset.
9. Stage 02 commercial identity-chain enforcement remains unchanged.
10. No client database schema migration or reset is introduced by Stage 03 R1.

## Non-goals

- Yalla Control Center administrator MFA/session policy remains governed by SEC.015 server contracts.
- Device/licensing lifecycle remains governed by SEC.010-SEC.015C1.
- Client DB version is not changed by this stage.
