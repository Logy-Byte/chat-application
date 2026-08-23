# MLS adversarial authorization verification

Date: 2026-08-23  
Project: Chaty production Supabase project  
Protocol: `mls-rfc9420-v1`

This verification was executed against the live project using a transaction-only fixture built from existing authenticated users and an existing multi-member conversation. The transaction was rolled back after the assertions, so no CI MLS devices, group state, or message fixture was persisted.

## Capability grant boundary

All eight MLS SECURITY DEFINER capability RPCs were inspected through PostgreSQL function metadata:

- `ack_mls_welcome_v1`
- `claim_mls_conversation_key_packages_v1`
- `edit_mls_message_v1`
- `get_mls_conversation_state_v1`
- `publish_mls_group_v1`
- `publish_mls_membership_update_v1`
- `register_mls_device_v1`
- `send_mls_message_v1`

For every RPC:

- `anon` has no EXECUTE privilege.
- `authenticated` has EXECUTE privilege.
- the function itself is SECURITY DEFINER and therefore must enforce its own identity/authorization checks.

## Transactional adversarial assertions

Result: **6 / 6 passed**.

1. A conversation member using their own active MLS device can read the MLS conversation-state capability.
2. The same member cannot substitute another member's MLS device ID when reading conversation state.
3. An authenticated user who is not a conversation member cannot read that conversation's MLS state.
4. A valid active MLS group device can call `send_mls_message_v1` with an accepted epoch and opaque ciphertext.
5. Repeating the same `(sender_id, client_message_id)` returns the same server message ID, proving the retry boundary is idempotent rather than creating a duplicate message.
6. A member cannot forge another member's MLS sender-device ID when sending an MLS application message.

The fixture transaction finished with an explicit rollback.

## What this proves

This verifies the live server capability boundary for the MLS state/read and encrypted-send paths used by the Flutter client, including member authorization, device ownership, and retry idempotency.

It does **not** replace:

- the OpenMLS two-independent-client protocol round-trip test;
- failure-atomic client membership-commit verification;
- physical multi-device testing;
- future adversarial tests for every possible malformed MLS payload.

Phase 1 remains gated on the exact branch-head analyzer, full Flutter test suite, and release APK build in addition to this live authorization evidence.
