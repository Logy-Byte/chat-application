# Phase 6 — UI/UX Consistency, Responsive Layout, Accessibility

Base: `production-hardening-2026-08-22` @ `7d887c3d074304cfc591b77c9e26b396585d4fa3`

## Scope
- Standardize all back chevrons on the shared Chaty back-button component and one size/touch target.
- Standardize empty, no-results, loading, error, permission-denied, mutation-loading, and delete-confirmation states.
- Audit responsive layouts for phone/tablet/small-window use; remove overlap, clipping, inaccessible controls, and bottom-nav obstruction.
- Normalize modal/sheet transitions, touch targets, typography hierarchy, spacing, actions, edit/delete ordering, and semantic labels.
- Keep motion smooth and bounded; respect reduced-motion and accessibility settings.
- Remove visual fake-success/fake-data states from release UI.

## Primary file ownership
`lib/ui/core/**`, shared widgets/design-system primitives, UI-only portions of feature screens, and Phase-6 widget/golden/semantics tests.

No database/RPC changes, no call/WebRTC logic, no MLS/attachment crypto, no repository architecture changes.

## Acceptance gates
1. Shared back navigation and state components are used consistently.
2. No critical screen clips/overlaps at supported narrow and tablet breakpoints.
3. All actionable controls meet accessible tap/semantic requirements.
4. Empty/no-result/error states are distinct and truthful.
5. No backend or transport behavior changes are introduced by UI refactors.
6. Analyzer, Flutter/widget tests, and release APK build pass.

## Current verification notes
- Shared state primitives and targeted Phase-6 widget tests are present on this isolated branch.
- This phase intentionally owns UI primitives only; any backend/transport diff is a regression and blocks merge.
- The branch verification workflow is being re-run against this exact head before the phase can move from implemented to accepted.
- Physical responsive inspection on representative phone/tablet sizes remains part of final integration even when widget tests are green.
