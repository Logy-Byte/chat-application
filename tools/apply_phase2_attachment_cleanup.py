from pathlib import Path

# Chat attachment sheet / media send paths.
path = Path('lib/features/messages/chat_attachment_actions.dart')
text = path.read_text(encoding='utf-8')
if "import '../../data/services/uploaded_attachment_guard.dart';" not in text:
    text = text.replace(
        "import '../../data/services/gb_feature_backend_service.dart';\n",
        "import '../../data/services/gb_feature_backend_service.dart';\n"
        "import '../../data/services/uploaded_attachment_guard.dart';\n",
        1,
    )

old = """        for (final attachment in items) {
          await dataStore.sendMessage(
            conversationId: conversationId,
            text: '',
            type: _messageType(type),
            attachment: attachment,
          );
        }
"""
new = """        for (var index = 0; index < items.length; index++) {
          final attachment = items[index];
          try {
            await UploadedAttachmentGuard.keepOnSuccess<void>(
              attachment: attachment,
              operation: () => dataStore.sendMessage(
                conversationId: conversationId,
                text: '',
                type: _messageType(type),
                attachment: attachment,
              ),
              deleteObject: _media.deleteOwnAttachment,
            );
          } catch (_) {
            if (index + 1 < items.length) {
              await UploadedAttachmentGuard.cleanupAll(
                items.skip(index + 1),
                deleteObject: _media.deleteOwnAttachment,
              );
            }
            rethrow;
          }
        }
"""
if 'items.skip(index + 1)' not in text:
    if old not in text:
        raise SystemExit('Phase 2 multiple attachment send marker missing')
    text = text.replace(old, new, 1)

old = """        await dataStore.sendMessage(
          conversationId: conversationId,
          text: '',
          type: _messageType(type),
          attachment: attachment,
          extraMetadata: viewOnce
              ? const <String, dynamic>{'view_once': true}
              : null,
        );
"""
new = """        await UploadedAttachmentGuard.keepOnSuccess<void>(
          attachment: attachment,
          operation: () => dataStore.sendMessage(
            conversationId: conversationId,
            text: '',
            type: _messageType(type),
            attachment: attachment,
            extraMetadata: viewOnce
                ? const <String, dynamic>{'view_once': true}
                : null,
          ),
          deleteObject: _media.deleteOwnAttachment,
        );
"""
if 'extraMetadata: viewOnce' in text and 'UploadedAttachmentGuard.keepOnSuccess<void>(\n          attachment: attachment,\n          operation: () => dataStore.sendMessage(\n            conversationId: conversationId,\n            text: \'\',' not in text:
    if old not in text:
        raise SystemExit('Phase 2 single attachment send marker missing')
    text = text.replace(old, new, 1)

old = """      await dataStore.sendMessage(
        conversationId: conversationId,
        text: '',
        type: MessageType.audio,
        attachment: attachment,
      );
      _toast(context, 'Voice note sent.');
"""
new = """      await UploadedAttachmentGuard.keepOnSuccess<void>(
        attachment: attachment,
        operation: () => dataStore.sendMessage(
          conversationId: conversationId,
          text: '',
          type: MessageType.audio,
          attachment: attachment,
        ),
        deleteObject: _media.deleteOwnAttachment,
      );
      _toast(context, 'Voice note sent.');
"""
if "_toast(context, 'Voice note sent.');" in text:
    voice_region = text[text.rfind('Future<void> recordVoiceNote'):]
    if 'UploadedAttachmentGuard.keepOnSuccess<void>(' not in voice_region:
        if old not in text:
            raise SystemExit('Phase 2 attachment-sheet voice send marker missing')
        text = text.replace(old, new, 1)

for marker in [
    "import '../../data/services/uploaded_attachment_guard.dart';",
    'items.skip(index + 1)',
    'UploadedAttachmentGuard.cleanupAll(',
]:
    if marker not in text:
        raise SystemExit(f'Phase 2 attachment action cleanup marker missing: {marker}')
path.write_text(text, encoding='utf-8')

# Long-press composer voice-note service.
path = Path('lib/data/services/voice_note_service.dart')
text = path.read_text(encoding='utf-8')
if "import 'uploaded_attachment_guard.dart';" not in text:
    text = text.replace(
        "import 'chat_media_service.dart';\n",
        "import 'chat_media_service.dart';\nimport 'uploaded_attachment_guard.dart';\n",
        1,
    )

old = """      await dataStore.sendMessage(
        conversationId: conversationId,
        text: '',
        type: MessageType.audio,
        attachment: attachment,
      );
      return true;
"""
new = """      await UploadedAttachmentGuard.keepOnSuccess<void>(
        attachment: attachment,
        operation: () => dataStore.sendMessage(
          conversationId: conversationId,
          text: '',
          type: MessageType.audio,
          attachment: attachment,
        ),
        deleteObject: _media.deleteOwnAttachment,
      );
      return true;
"""
if 'UploadedAttachmentGuard.keepOnSuccess<void>(' not in text:
    if old not in text:
        raise SystemExit('Phase 2 voice-note service send marker missing')
    text = text.replace(old, new, 1)

for marker in [
    "import 'uploaded_attachment_guard.dart';",
    'deleteObject: _media.deleteOwnAttachment,',
]:
    if marker not in text:
        raise SystemExit(f'Phase 2 voice cleanup marker missing: {marker}')
path.write_text(text, encoding='utf-8')
