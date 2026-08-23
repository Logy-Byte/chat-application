import 'package:chat/data/services/uploaded_attachment_guard.dart';
import 'package:chat/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const attachment = MessageAttachment(
    id: 'attachment-a',
    type: 'document',
    name: 'report.pdf',
    size: '1 KB',
    url: 'user/conversation/ciphertext.bin',
  );

  test('successful message send keeps uploaded ciphertext', () async {
    final deleted = <String>[];
    final result = await UploadedAttachmentGuard.keepOnSuccess<int>(
      attachment: attachment,
      operation: () async => 42,
      deleteObject: (path) async => deleted.add(path),
    );

    expect(result, 42);
    expect(deleted, isEmpty);
  });

  test('failed message send removes uploaded ciphertext and rethrows', () async {
    final deleted = <String>[];

    await expectLater(
      UploadedAttachmentGuard.keepOnSuccess<void>(
        attachment: attachment,
        operation: () async => throw StateError('MLS send rejected'),
        deleteObject: (path) async => deleted.add(path),
      ),
      throwsStateError,
    );

    expect(deleted, <String>['user/conversation/ciphertext.bin']);
  });

  test('cleanup failure never hides the original send failure', () async {
    await expectLater(
      UploadedAttachmentGuard.keepOnSuccess<void>(
        attachment: attachment,
        operation: () async => throw ArgumentError('send failure'),
        deleteObject: (_) async => throw Exception('cleanup failure'),
      ),
      throwsArgumentError,
    );
  });

  test('batch cleanup removes every unsent uploaded object', () async {
    final deleted = <String>[];
    final items = <MessageAttachment>[
      attachment,
      const MessageAttachment(
        id: 'attachment-b',
        type: 'image',
        name: 'photo.jpg',
        size: '2 KB',
        url: 'user/conversation/ciphertext-2.bin',
      ),
    ];

    await UploadedAttachmentGuard.cleanupAll(
      items,
      deleteObject: (path) async => deleted.add(path),
    );

    expect(
      deleted,
      <String>[
        'user/conversation/ciphertext.bin',
        'user/conversation/ciphertext-2.bin',
      ],
    );
  });
}
