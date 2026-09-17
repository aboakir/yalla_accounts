# Phase 17 — Legal & Commercial Operations

Status: IMPLEMENTATION_READY / LEGAL_REVIEW_EXTERNAL

Evidence:
- Subscription screen exposes privacy, terms, deletion information and authenticated deletion request entry.
- Deletion request requires a freshly verified Supabase bearer session and HTTPS Control Server endpoint.
- Client receives a durable server request id; no local financial or workshop data is deleted by this action.
- Existing signed-license read-only behavior remains unchanged for expired/suspended/revoked authority.
- Final jurisdiction-specific legal wording, refund obligations, store declarations and counsel approval remain external gates.
