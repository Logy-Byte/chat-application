# Phase 4 — Realtime Messaging, Pagination, Offline Recovery

Base: `production-hardening-2026-08-22` @ `7d887c3d074304cfc591b77c9e26b396585d4fa3`

## Scope
- Replace broad aggregate rehydration with event-specific message/reaction/receipt/task reducers.
- Add bounded message pagination/cursors and reconnect backfill.
- Preserve optimistic client IDs and reconcile server acknowledgements deterministically.
- Introduce typed transport/hydration failures instead of silent empty-state fallbacks.
- Add retry/backoff and offline/reconnect behavior without duplicating messages.
- Add large-history and reconnect regression tests.

## Primary file ownership
`lib/data/services/backend_service.dart`, realtime/event-bus/repository cache helpers created specifically for this phase, and Phase-4 tests.

Do not modify call transport, MLS implementation, attachment crypto, launcher icons, or broad UI redesign files.

## Acceptance gates
1. One incoming message does not refetch every loaded timeline.
2. Reaction/receipt/task changes update only affected entities.
3. Pagination is bounded and stable under concurrent incoming messages.
4. Reconnect backfills only missing deltas and produces no duplicates.
5. Network/database failure becomes an explicit typed error/retry state.
6. Analyzer, Flutter tests, and release APK build pass.

## Current verification notes
- Event-specific reconciliation sets are present instead of unconditional full authenticated-state hydration.
- Message history is bounded by a 50-message page and the branch patcher owns pagination/backfill wiring.
- The encrypted offline outbox preserves idempotent client message identifiers and has a dedicated contract test.
- The verified branch runner applies the remaining pagination/outbox integration, formats it, runs analyzer/full tests/release build, and commits only if those gates pass.
- Silent profile/hydration fallbacks are still treated as a release-hardening concern and must not be misreported as completed typed-error coverage.
