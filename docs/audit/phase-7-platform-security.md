# Phase 7 — Platform Security, Account Lifecycle, Device Features

Base: `production-hardening-2026-08-22` @ `7d887c3d074304cfc591b77c9e26b396585d4fa3`

## Scope
- Finish launcher-icon production behavior for supported built-in aliases and clearly separate unsupported arbitrary runtime icon mutation from real Android capabilities.
- Verify app-lock, biometric/device-credential, notification privacy, push-token lifecycle, and lock-screen/background privacy behavior.
- Finish linked-device registration/revocation semantics and security-center visibility.
- Implement/verify logout, account deletion, session/device revocation, and sensitive local-data cleanup.
- Remove release-visible demo/preview platform actions.
- Audit Android manifest/exported components/permissions and iOS-compatible permission declarations for least privilege.
- Verify Supabase Auth password protections/configuration that are available to the project.

## Primary file ownership
Platform/security services, settings/security screens, launcher-icon controller/platform channels, notification/push/device lifecycle files, Android/iOS configuration, and Phase-7 tests.

Do not modify call media transport, MLS/attachment crypto, realtime cache architecture, or shared UI design-system internals except security-specific components.

## Acceptance gates
1. No launcher-icon path claims unsupported arbitrary runtime behavior.
2. App lock and notification privacy prevent sensitive content leakage when configured.
3. Logout/account deletion/revocation clear the correct local tokens/keys/caches.
4. Linked-device revoke blocks future device access according to server policy.
5. Platform permissions/exported components pass least-privilege review.
6. Analyzer, Flutter tests, and release APK build pass.
