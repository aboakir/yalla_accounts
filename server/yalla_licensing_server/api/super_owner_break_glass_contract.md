# SEC.014 - YALLA_SUPER_OWNER + Break Glass API Contract

## Authorization boundary

All privileged routes live under `/v1/control-center` and execute only on the licensing server. The customer desktop application never contains a super-owner password, universal token, private signing key, or privileged mutation route.

The server derives `actor_id` from the authenticated admin session. A client-supplied actor id is never authoritative. SEC.015 hardens login, MFA/recovery, session rotation/revocation, and audit integrity; SEC.014 defines the authorization model used by those sessions.

## Current actor

- `GET /v1/control-center/me/authorization` returns active server roles and permissions only.
- It may return `YALLA_SUPER_OWNER` or delegated roles, but never password hashes, recovery secrets, session secrets, or signing secrets.

## Canonical mutation endpoint

`POST /v1/control-center/actions`

Required headers:
- `Authorization: Bearer <ephemeral admin session>`
- `Idempotency-Key: <unique request key>`

Required body fields:
- `action_code`
- `organization_id` when the target is organization-scoped
- `target_entity_type` / `target_entity_id` when applicable
- `reason` (minimum 8 meaningful characters)
- `requested_state` (typed/allowlisted by action handler; never dynamic SQL)
- `break_glass_grant_id` for emergency actions
- `expires_at` for temporary overrides when applicable

The route MUST call `yalla_authorize_admin_action(...)` before mutation. The action handler must reject unknown fields/action codes, capture authoritative `before_state`, apply one typed mutation, capture `after_state`, and persist the request/audit record. No generic SQL expression or table name may come from the browser payload.

## Super Owner action catalog

SEC.014 seeds 38 canonical actions covering the owner's requested capabilities: organization create/update/activate/suspend/resume, country pack, subscription cancel/restore/renew/dates/plan/trial/grace, user/device limits, features, activation history/security reads, license issuance/revocation, admin-user management, and force operations.

Emergency/force actions require BOTH the specific permission and an ACTIVE scoped break-glass grant. Possessing `YALLA_BREAK_GLASS` alone does not grant force-action permissions.

## Break Glass

`POST /v1/control-center/break-glass`
- organization-scoped only
- reason minimum 15 characters
- requested lifetime 5-60 minutes
- server records actor, organization, start, expiry, reason, source IP/device when available
- SEC.015 will require hardened re-authentication/MFA context for production issuance

`POST /v1/control-center/break-glass/{grant_id}/revoke`
- requires reason
- immediately invalidates further emergency authorization

`GET /v1/control-center/break-glass`
- audit/operations view; never returns session/recovery secrets

## License issue / refresh

`LICENSE.ISSUE` and `LICENSE.REFRESH_FORCE` authorize a `yalla_license_issuance_requests` record. They DO NOT sign inside PostgreSQL or the browser. The signing service resolves the approved KMS/HSM/secret-store key reference and returns only a signed license envelope/public key metadata.

## Super Owner bootstrap

`yalla_bootstrap_super_owner(...)` is a one-time server database bootstrap for an already ACTIVE Yalla admin identity. It creates no password and is not a customer-client feature. Production admin identity/login bootstrap is completed with SEC.015.

## Customer passwords

Yalla administrators never receive `SHOW PASSWORD`. SEC.015 may authorize force reset, unlock, disable, and session revocation without exposing plaintext or hashes.
