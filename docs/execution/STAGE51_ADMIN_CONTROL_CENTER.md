# Stage 51 — Yalla administration: safe client integration foundation

Status: PASS for the user-authorized fallback of a separate administration client ready to connect; NOT a deployed production control plane or live license-issuance acceptance.

## Implemented

The existing separate web control center now uses Arabic RTL, a light Yalla palette and structured forms for issue, renewal, freeze, cancellation, temporary exception, trial extension, device deactivation and device replacement. It does not read or mutate customer SQLite and does not expose a private signing key.

The web session must represent a Yalla administration role (YALLA_SUPER_OWNER or scoped YALLA_BREAK_GLASS) with MFA. Local workshop owner/admin/accountant/staff/viewer identities cannot open this surface. Server-side authorization remains mandatory on every endpoint; UI checks do not grant permission.

Operations stay unavailable unless /capabilities advertises the particular action plus required audit and idempotency support. Missing backend/configuration produces an explanatory Arabic state. No guessed capabilities, default licenses or fictitious success responses are used. Unsupported raw JSON and emergency action entry buttons are hidden, without deleting their pre-existing code.

Forms select actual server organizations and associated subscriptions/devices. Cross-organization targets, replacement with the same device, unknown plans, invalid expiry/duration and absent reasons are rejected. Requests are reviewed before posting. A request has one UUID idempotency key and a disabled submit while pending; timeout retry or closing/reopening its panel retains that same request. Success requires a matching idempotency key and durable audit_event_id with APPLIED/ALREADY_APPLIED. Closing the browser after an uncertain result requires checking server audit/history before starting another business action; the browser does not persist administrative credentials or drafts.

Last activation/sync/backup values come from server telemetry. Missing telemetry is explicitly unknown, not a fabricated date or successful backup. Transport requires HTTPS, with HTTP permitted only for explicitly configured localhost development. Credentials use the existing server cookie flow and CSRF, bounded requests and redirect refusal.

## Backend connection contract / remaining deployment work

The repository's runtime harness is explicitly a test server. It is not promoted to production by this change. Deploy a managed, authenticated administration backend separately and implement:

- GET /v1/control-center/auth/session: server-verified administration roles, MFA authentication_level and CSRF token.
- GET /capabilities: caller-filtered allowed_actions, audit_required=true, idempotency_required=true, plan_codes. Do not advertise unsupported actions. Existing test harnesses without this endpoint intentionally cannot execute these new controls.
- GET /organizations (subscriber/workshop identity plus last_activation_at/last_sync_at/last_backup_at), /subscriptions and /devices with organization_id and stable UUID IDs.
- POST /actions: the action_code, organization_id, target_entity_type/id, reason, requested_state, expiry and idempotency_key. Verify current actor/scoped role/MFA, target organization, entitlement policy and expiry on the server. An Idempotency-Key header matches the body. Atomically store prior/new values, actor, UTC time and reason with the state change; duplicate identical requests return the original result and altered-key reuse fails. Require reauthentication/approval when server policy calls for it.
- Successful mutation acknowledgement: status APPLIED or ALREADY_APPLIED, matching idempotency_key and audit_event_id. Queued/unverified responses are not treated as success.
- Sign licenses exclusively using server-held private keys. Client-side status editing is not a substitute for a device-bound signed license. Replacement must verify device registration/proof, seat limits and revocation before issuing a replacement grant.
- Report sync/backup telemetry only when those subsystems actually confirm the event.

## Validation

16 Node tests passed: local-role/MFA denial, capability fail-closed, all action payload boundaries, expiry/plan/duration constraints, cross-workshop targets, replacement identity, audit acknowledgements, absent telemetry, double-click, uncertain retry, session revocation and logout while pending.

Commands:
`node --test server/yalla_licensing_server/control_center/test/*.test.cjs`
`node --check server/yalla_licensing_server/control_center/web/app.js`
`node --check server/yalla_licensing_server/control_center/web/managed_operations.js`

No real subscription was issued/changed, no production backend was deployed and no private signing key was copied. Browser/device visual acceptance and live server endpoint testing remain outstanding.

## Files

- control_center/web/index.html, styles.css, app.js
- control_center/web/operations.js and managed_operations.js
- control_center/test/operations.test.cjs, managed_operations.test.cjs and bootstrap.test.cjs
- control_center_manifest.json and this report

The local browser-preview tool failed twice with 'trusted Node process exited unexpectedly'. No browser screenshot or visual PASS is claimed; the full bootstrap and form behavior were exercised with the Node DOM harness instead. The local preview server was stopped afterward.

