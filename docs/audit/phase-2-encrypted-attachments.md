# Phase 2 — Encrypted Attachments

Branch: `phase-2-encrypted-attachments`

Acceptance gates:
- File bytes are encrypted locally before Supabase Storage upload.
- Storage object names and MIME type do not expose original filename/type.
- Attachment key/nonce/MAC/original metadata travel only inside the MLS application payload.
- Image, video, audio and document consumers authenticate/decrypt to local temporary files before rendering/opening.
- Tampering and wrong-conversation AAD fail closed.
- Failed MLS message sends remove newly uploaded encrypted objects.
- Private Storage/RLS membership policies remain enforced.
- Flutter analyzer, tests and Android release build pass.

Current verification notes:
- XChaCha20-Poly1305 streaming codec and authenticated AAD binding are implemented.
- Storage uploads use opaque `.bin` object names with `application/octet-stream`; original filename/type stay in the encrypted message envelope.
- The branch CI applies the remaining send-lifecycle/cleanup wiring and only commits verified source after crypto tests, cleanup tests, analyzer, full tests, and release build pass.
- Live `chat-media` policies remain membership-scoped for select and sender/member-scoped for insert/delete.

This branch is isolated from the Phase 1 MLS completion branch.
