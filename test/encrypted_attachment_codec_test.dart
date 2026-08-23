import 'dart:io';

import 'package:chat/data/services/encrypted_attachment_codec.dart';
import 'package:chat/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EncryptedAttachmentCodec', () {
    late Directory directory;
    late EncryptedAttachmentCodec codec;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('chaty_attachment_test_');
      codec = EncryptedAttachmentCodec();
    });

    tearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('round trips streaming ciphertext without exposing plaintext', () async {
      final source = File('${directory.path}/source.bin');
      final ciphertext = File('${directory.path}/cipher.bin');
      final clear = File('${directory.path}/clear.bin');
      final bytes = List<int>.generate(
        1024 * 1024 + 333,
        (index) => (index * 31 + 17) & 0xff,
      );
      await source.writeAsBytes(bytes, flush: true);

      const conversationId = 'conversation-a';
      const attachmentId = 'attachment-a';
      final encrypted = await codec.encryptFile(
        source: source,
        destination: ciphertext,
        conversationId: conversationId,
        attachmentId: attachmentId,
        originalMimeType: 'application/pdf',
        originalFileName: 'contract.pdf',
      );

      expect(await ciphertext.length(), bytes.length);
      expect(await ciphertext.readAsBytes(), isNot(equals(bytes)));

      final attachment = MessageAttachment(
        id: attachmentId,
        type: 'document',
        name: 'contract.pdf',
        size: '${bytes.length} B',
        url: 'user/conversation/object.bin',
        encryptionVersion: EncryptedAttachmentCodec.version,
        encryptionAlgorithm: EncryptedAttachmentCodec.algorithm,
        encryptionKeyBase64: encrypted.keyBase64,
        encryptionNonceBase64: encrypted.nonceBase64,
        encryptionMacBase64: encrypted.macBase64,
        originalMimeType: encrypted.originalMimeType,
        originalSizeBytes: encrypted.originalSizeBytes,
      );

      await codec.decryptFile(
        source: ciphertext,
        destination: clear,
        conversationId: conversationId,
        attachment: attachment,
      );
      expect(await clear.readAsBytes(), bytes);
    });

    test('rejects ciphertext tampering and removes clear output', () async {
      final source = File('${directory.path}/source.bin');
      final ciphertext = File('${directory.path}/cipher.bin');
      final clear = File('${directory.path}/clear.bin');
      await source.writeAsBytes(
        List<int>.generate(8192, (index) => index & 0xff),
        flush: true,
      );

      final encrypted = await codec.encryptFile(
        source: source,
        destination: ciphertext,
        conversationId: 'conversation-a',
        attachmentId: 'attachment-a',
        originalMimeType: 'image/jpeg',
        originalFileName: 'photo.jpg',
      );
      final mutated = await ciphertext.readAsBytes();
      mutated[mutated.length ~/ 2] ^= 0x80;
      await ciphertext.writeAsBytes(mutated, flush: true);

      final attachment = _attachment(encrypted);
      await expectLater(
        codec.decryptFile(
          source: ciphertext,
          destination: clear,
          conversationId: 'conversation-a',
          attachment: attachment,
        ),
        throwsA(isA<AttachmentCryptoException>()),
      );
      expect(await clear.exists(), isFalse);
    });

    test('binds ciphertext to conversation and attachment AAD', () async {
      final source = File('${directory.path}/source.bin');
      final ciphertext = File('${directory.path}/cipher.bin');
      final clear = File('${directory.path}/clear.bin');
      await source.writeAsBytes(List<int>.filled(4096, 0x5a), flush: true);

      final encrypted = await codec.encryptFile(
        source: source,
        destination: ciphertext,
        conversationId: 'conversation-a',
        attachmentId: 'attachment-a',
        originalMimeType: 'audio/ogg',
        originalFileName: 'voice.ogg',
      );
      final attachment = _attachment(encrypted);

      await expectLater(
        codec.decryptFile(
          source: ciphertext,
          destination: clear,
          conversationId: 'conversation-b',
          attachment: attachment,
        ),
        throwsA(isA<AttachmentCryptoException>()),
      );
      expect(await clear.exists(), isFalse);
    });
  });
}

MessageAttachment _attachment(AttachmentEncryptionResult encrypted) {
  return MessageAttachment(
    id: 'attachment-a',
    type: 'document',
    name: encrypted.originalFileName,
    size: '${encrypted.originalSizeBytes} B',
    url: 'user/conversation/object.bin',
    encryptionVersion: EncryptedAttachmentCodec.version,
    encryptionAlgorithm: EncryptedAttachmentCodec.algorithm,
    encryptionKeyBase64: encrypted.keyBase64,
    encryptionNonceBase64: encrypted.nonceBase64,
    encryptionMacBase64: encrypted.macBase64,
    originalMimeType: encrypted.originalMimeType,
    originalSizeBytes: encrypted.originalSizeBytes,
  );
}
