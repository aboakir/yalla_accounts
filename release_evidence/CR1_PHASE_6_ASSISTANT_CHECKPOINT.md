# CR1 Phase 6 — Assistant Checkpoint

Base Accounts commit: `687d5840d633b4ed0d26a30a1cb439ea4165ff93`.
Control base: `e03604b60861f5f1e0d776f172282a7d08a81f4e`.
Production Supabase changes: **NONE**.

## Direct implementation completed

- Accounts now validates the signed `PLAN_CODE`, `ACCESS_ALLOWED`, `MAX_USERS`, `MAX_DEVICES` projection without local plan authority.
- Added helpers to consume signed plan code and signed access authority only.
- Subscription and onboarding UI display the signed plan, never a locally inferred plan.
- Restored correct Arabic subscription-state labels/messages.
- Updated seat/subscription regression fixtures to current authorization and signed-entitlement contracts.
- Added isolated CR1 Phase 6 E2E using the real V2 challenge/proof/complete path and current Accounts verifier.

## Verification

- Signed Gate-6 transition E2E + entitlement contract: 7/7 PASS.
- Subscription access + licensed user seat regression: 22/22 PASS.
- Modified/new Dart analyzer: NO ISSUES.
- Control Server full suite: 129/129 PASS.
- Control focused UI: 72/72 PASS; analyzer clean.
- Production Supabase changes: NONE.

Remaining task for independent review: audit feature/route enforcement coverage and decide whether the existing separate `billing_status=UNPAID` model is sufficient or an explicit stored `PAST_DUE` subscription state is required by CR1. No Phase 7 work has started.
