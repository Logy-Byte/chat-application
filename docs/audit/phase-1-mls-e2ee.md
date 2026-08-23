# Phase 1 — MLS E2EE

Branch: `phase-1-mls-e2ee`

Acceptance gates:
- OpenMLS client integration compiles.
- Membership commits are failure-atomic: publish pending commit first, merge locally only after server acceptance.
- MLS protocol round-trip tests pass.
- Supabase MLS capability boundaries pass adversarial authorization tests.
- Android analyzer, tests, and release build pass.

This branch is isolated from Phase 2 encrypted attachment work.
