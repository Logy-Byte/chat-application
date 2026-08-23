from pathlib import Path

mls = Path('lib/data/services/mls_e2ee_service.dart')
text = mls.read_text(encoding='utf-8')
if "import 'dart:async';" not in text:
    text = text.replace(
        "import 'dart:convert';",
        "import 'dart:async';\nimport 'dart:convert';",
        1,
    )
old = """    await _requireEngine().mergePendingCommit(groupIdBytes: groupIdBytes);
    final newEpoch = (await _requireEngine().groupEpoch(
      groupIdBytes: groupIdBytes,
    )).toInt();

    try {
      await _client.rpc(
        'publish_mls_membership_update_v1',"""
new = """    final newEpoch = group.epoch + 1;

    try {
      await _client.rpc(
        'publish_mls_membership_update_v1',"""
if old in text:
    text = text.replace(old, new, 1)
old = """    } catch (error) {
      // The local engine already advanced. Failing closed is safer than trying
      // to synthesize a rollback of MLS ratchet state.
      throw MlsE2eeException(
        'Server rejected the MLS membership commit after local advancement. Re-open this account on the device to resynchronize. ($error)',
      );
    }

    return _fetchState(conversationId, afterEpoch: newEpoch);"""
new = """    } catch (error) {
      await _requireEngine().clearPendingCommit(groupIdBytes: groupIdBytes);
      throw MlsE2eeException(
        'Server rejected the pending MLS membership commit; local state was not advanced. ($error)',
      );
    }

    await _requireEngine().mergePendingCommit(groupIdBytes: groupIdBytes);
    final mergedEpoch = (await _requireEngine().groupEpoch(
      groupIdBytes: groupIdBytes,
    )).toInt();
    if (mergedEpoch != newEpoch) {
      throw MlsE2eeException(
        'MLS local epoch mismatch after commit: local=$mergedEpoch expected=$newEpoch.',
      );
    }
    return _fetchState(conversationId, afterEpoch: newEpoch);"""
if old in text:
    text = text.replace(old, new, 1)
for marker in [
    "import 'dart:async';",
    'clearPendingCommit(groupIdBytes: groupIdBytes)',
    'final newEpoch = group.epoch + 1;',
]:
    if marker not in text:
        raise SystemExit(f'Phase 2 MLS integration marker missing: {marker}')
mls.write_text(text, encoding='utf-8')

media = Path('lib/data/services/chat_media_service.dart')
text = media.read_text(encoding='utf-8').replace(
    "throw const FileSystemException('Downloaded attachment is empty.');",
    "throw FileSystemException('Downloaded attachment is empty.');",
)
media.write_text(text, encoding='utf-8')

detail = Path('lib/features/chats/chat_detail_screen.dart')
text = detail.read_text(encoding='utf-8')
replacements = [
    (
        """        builder: (_) => MediaViewerScreen(
          title: attachment.name,
          type: attachment.type,
          size: attachment.size,
          storagePath: attachment.url,
          theme: theme,
        ),""",
        """        builder: (_) => MediaViewerScreen(
          theme: theme,
          conversationId: message.conversationId,
          attachment: attachment,
        ),""",
        'view-once media viewer',
    ),
    (
        """                      builder: (_) => MediaViewerScreen(
                        title: message.attachment!.name,
                        type: message.attachment!.type,
                        size: message.attachment!.size,
                        storagePath: message.attachment!.url,
                        theme: theme,
                      ),""",
        """                      builder: (_) => MediaViewerScreen(
                        theme: theme,
                        conversationId: message.conversationId,
                        attachment: message.attachment!,
                      ),""",
        'message media viewer',
    ),
]
for old, new, label in replacements:
    if new in text:
        continue
    if old not in text:
        raise SystemExit(f'Expected Phase 2 caller missing: {label}')
    text = text.replace(old, new, 1)
detail.write_text(text, encoding='utf-8')

contact = Path('lib/features/chats/contact_info_screen.dart')
text = contact.read_text(encoding='utf-8')
old = """        builder: (_) => MediaViewerScreen(
          title: attachment.name,
          type: attachment.type,
          size: attachment.size,
          storagePath: attachment.url,
          theme: widget.theme,
        ),"""
new = """        builder: (_) => MediaViewerScreen(
          theme: widget.theme,
          conversationId: message.conversationId,
          attachment: attachment,
        ),"""
if new not in text:
    if old not in text:
        raise SystemExit('Expected Phase 2 caller missing: contact media viewer')
    text = text.replace(old, new, 1)
contact.write_text(text, encoding='utf-8')
