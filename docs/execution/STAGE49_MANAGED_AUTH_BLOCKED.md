# Stage 49 — Managed cloud identity: BLOCKED / not accepted

2026-09-09. The current request explicitly includes implementing Stages 47–51 concurrently. The earlier Stage43 was a read-only audit.

## Findings and recommendation

No configured Firebase/Supabase identity provider was found. Supabase is the proposed managed provider. Email/password, password reset, Google OAuth and Apple on iOS must remain identity-only; workshop finance remains local.

Official references:
- https://supabase.com/docs/guides/auth/social-login/auth-google
- https://supabase.com/docs/guides/auth/social-login/auth-apple
- https://supabase.com/docs/guides/getting-started/api-keys
- https://supabase.com/docs/reference/dart/auth-signinwithoauth

## Required implementation boundary

1. Configure Project URL and a public publishable key only. A service-role/secret key never belongs in the app.
2. Initialize lazily so missing network/configuration cannot block local password/PIN login.
3. Persist both session and PKCE verifier in secure storage. Verify persistence/read-back explicitly before relying on a cloud session; do not rely on the SDK asynchronous persistence callback alone.
4. Verify a fresh user with the provider user endpoint; cached currentUser alone is not proof.
5. Bind issuer + subject to the existing identity_account only after local password/PIN verification. Do not match by email/username or accept remote role claims.
6. Every local session must still pass canonical user/workshop/device/license checks. Existing expired/frozen subscriptions remain read-only.
7. Handle recovery deep links during initialization as well as after initialization. Use PKCE and restrict approved redirect URIs. Disable verbose auth/URI/session SDK logging.
8. Hide the cloud entry until provider configuration, platform callbacks and provider-console settings pass live validation.

## Blocker

Automatic approval review rejected the agent's authentication file writes twice. It treated the older Stage43 read-only instruction as controlling and explicitly rejected the current Stage47–51 authorization relayed from the parent. No workaround was used. No cloud_auth source, binding table, route, provider configuration, live user or cloud session was created.

The two dependencies briefly added for that implementation (supabase_flutter and a direct logging dependency) were removed again using flutter pub remove. No unused Supabase dependency is intentionally left behind. Existing offline authentication is retained.

The user's Supabase URL/public key and Google/Apple/reset redirect setup also remain unavailable. Therefore this stage is NOT PASS and no live cloud authentication has been claimed.
