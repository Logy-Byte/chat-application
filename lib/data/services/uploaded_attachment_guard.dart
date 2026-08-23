import '../../domain/models/chat_message.dart';

/// Couples an uploaded encrypted object to the message operation that makes it
/// reachable by recipients.
///
/// The guard removes only Storage objects whose message operation throws. A
/// transient network send that has been accepted into the encrypted offline
/// outbox completes normally and therefore keeps its ciphertext object.
class UploadedAttachmentGuard {
  const UploadedAttachmentGuard._();

  static Future<T> keepOnSuccess<T>({
    required MessageAttachment attachment,
    required Future<T> Function() operation,
    required Future<void> Function(String objectPath) deleteObject,
  }) async {
    try {
      return await operation();
    } catch (_) {
      await cleanup(
        attachment,
        deleteObject: deleteObject,
      );
      rethrow;
    }
  }

  static Future<void> cleanup(
    MessageAttachment attachment, {
    required Future<void> Function(String objectPath) deleteObject,
  }) async {
    final objectPath = attachment.url?.trim() ?? '';
    if (objectPath.isEmpty) return;
    try {
      await deleteObject(objectPath);
    } catch (_) {
      // Preserve the original send failure. Storage cleanup is best-effort and
      // may be retried later by an orphan-object maintenance task.
    }
  }

  static Future<void> cleanupAll(
    Iterable<MessageAttachment> attachments, {
    required Future<void> Function(String objectPath) deleteObject,
  }) async {
    for (final attachment in attachments) {
      await cleanup(attachment, deleteObject: deleteObject);
    }
  }
}
