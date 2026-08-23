# Phase 5 — Messaging Feature Correctness

Base: `production-hardening-2026-08-22` @ `7d887c3d074304cfc591b77c9e26b396585d4fa3`

## Scope
- Fix voice recorder completion so a successful recording exposes Send and sends the real audio attachment.
- Verify `/task` command flow: parse command, open assignment UI, support self/direct/group-member assignment, persist real task data.
- Finish Updates/Status flow: views list, bottom-to-top views sheet behavior, owner delete, correct empty/no-result states.
- Implement home horizontal swipe between tabs without breaking nested vertical scrolling.
- Enforce bottom navigation rule: maximum four direct items; overflow appears as `More` with horizontal-three-dots and includes desktop/show-desktop destinations when configured.
- Verify settings toggles actually affect the feature they describe; remove/disable options with no runtime consumer.

## Primary file ownership
Feature screens/services for chat composer, tasks, statuses/updates, home navigation, settings runtime wiring, and Phase-5 tests.

Do not redesign shared design-system primitives, modify WebRTC/MLS/attachment crypto, or refactor the global repository facade in this branch.

## Acceptance gates
1. Voice recording has deterministic cancel/delete/send behavior with no fake success toast.
2. `/task` persists and renders real assignments.
3. Status owner can inspect viewers and delete; unrelated users cannot access status/view data.
4. Tab swipe and bottom-nav overflow behavior are responsive and gesture-safe.
5. Every retained setting has a verified runtime consumer.
6. Analyzer, Flutter tests, and release APK build pass.

## Current verification notes
- Dedicated feature-contract and root-navigation-policy tests are present.
- The runtime settings audit has identified and wired the previously write-only appearance controls.
- The verified branch runner applies remaining navigation/profile/settings wiring, then runs the settings-consumer audit, targeted feature tests, analyzer, full Flutter suite, and Android release build before it is allowed to commit patched source.
- No retained setting should be counted as complete merely because its toggle renders; the runtime consumer audit remains authoritative for this phase.
