# Phase 3 — Calls, TURN, and Call Lifecycle

Base: `production-hardening-2026-08-22` @ `7d887c3d074304cfc591b77c9e26b396585d4fa3`

## Scope
- Make `call_sessions` / `call_ice_candidates` the only authoritative ringing/signaling state.
- Remove remaining legacy user-addressed call broadcast dependencies from release flow.
- Keep UI `connected` state transport-derived from WebRTC only.
- Persist/reload call history from server call sessions.
- Verify microphone/camera/speaker lifecycle, teardown, reconnect/failure states, foreground/background handling.
- Keep TURN credentials server-issued; fail closed when TURN is not configured.
- Add adversarial call-session/ICE authorization tests.

## Primary file ownership
`lib/data/services/call_*`, `lib/features/calls/**`, call-only sections of `lib/main.dart`, call-specific tests and migrations/functions.

Do not change MLS/message encryption files, attachment crypto, global design-system components, launcher-icon code, or repository-facade architecture in this branch.

## Acceptance gates
1. No legacy call broadcast is required for incoming-call state.
2. Unauthorized user cannot read/mutate another call or ICE row.
3. Connected timer starts only from WebRTC connected state.
4. Call teardown releases streams/tracks/peer/subscriptions deterministically.
5. Analyzer, Flutter tests, and release APK build pass.
6. Direct and TURN-relay physical-device tests remain required before final production merge.
