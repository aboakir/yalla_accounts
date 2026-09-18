# Phase 17 — Legal & Commercial Readiness — Yallah Accounts

Date: 2026-09-18
Status: PASS / CLOSED — INTERNAL LEGAL & COMPLIANCE ACCEPTANCE
Scope: Palestine first release.

## Implemented in Accounts

- Canonical v1 legal documents are bundled in `assets/legal/`; Terms, Privacy, Account Deletion, Refund, Support and Contact work without a website or external URL.
- Each bundled document is versioned and SHA-256 locked in `LocalLegalDocuments`.
- Signup/onboarding presents two independent unchecked consent boxes for Terms and Privacy.
- Consent is not accepted by opening the screen or clicking signup; the verified session records the active versions on the server.
- Onboarding is rejected by the backend when current legal acceptance is absent.
- Palestine is the only selectable country in the first-release onboarding flow.
- Account deletion is an authenticated server request with a durable request ID; no blind local GL deletion exists.
- A complaint/support request can be submitted from Accounts and returns a durable `complaint_id`.
- Subscription UI explicitly states that there is no hidden self-service paid checkout or implicit auto-renewal.
- The old hard-coded WhatsApp support number was removed.
- Production/Codemagic/GitHub build configuration no longer requires Privacy/Terms/Delete URLs.

## Legal display rule

The application is the primary Phase 17 legal-reading surface. A future website may mirror the same versioned documents, but Accounts does not depend on website hosting, Render, GitHub Pages or any external legal URL.

## Validation evidence

- Accounts targeted Phase 17 / Phase 11 / Phase 18 suite: 19/19 PASS.
- Targeted Flutter analyzer: No issues found.
- Bundled legal assets: SHA-256 checks PASS; no DRAFT/TODO/support placeholder.
- In-app Privacy and Terms navigation widget tests: PASS.
- Legal acceptance transport: PASS.
- Complaint transport: PASS.
- Account deletion transport: PASS.

## Deferred and non-blocking for Phase 17

- trademark registration;
- trade-name registration;
- company formation;
- final commercial registration;
- tax registration/number;
- foreign-country legal packs;
- public website mirror of legal documents.

Governmental prerequisites that may be mandatory before paid public e-commerce remain a separate external pre-launch gate and are not represented as completed.

PHASE_17_ACCOUNTS = PASS / CLOSED
