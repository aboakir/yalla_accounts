# Phase 17 — Legal & Commercial Operations

Status: IMPLEMENTATION_READY / LEGAL_COUNSEL_EXTERNAL

- Yalla Accounts exposes Privacy, Terms and account-deletion entry points for release builds.
- A signed-in customer can submit a deletion request from the subscription screen.
- Submission requires a freshly network-verified Supabase bearer token and HTTPS Control origin.
- The client never performs local destructive account/GL deletion from this request.
- The server-issued request id is shown to the customer for support correlation.
- Trial, cancellation, renewal, payment and read-only behavior remain server-authoritative.
- Phase 17 tests cover authenticated request, fail-closed missing identity and insecure-origin denial.
- Accounting source of truth remains the local Accounts GL; no legal workflow rewrites it.

External gate: production legal text must be approved for each launch jurisdiction before final commercial GO.