import 'package:chat/data/services/encrypted_message_outbox.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EncryptedOutboxEnvelope', () {
    test('round-trips transport identity without cleartext fields', () {
      final original = EncryptedOutboxEnvelope(
        clientMessageId: '11111111-1111-1111-1111-111111111111',
        conversationId: '22222222-2222-2222-2222-222222222222',
        senderDeviceId: 'device-12345678',
        groupId: 'opaque-group-id',
        epoch: 9,
        ciphertext: 'abcdefghijklmnopqrstuvwxyz0123456789',
        createdAt: DateTime.utc(2026, 8, 23, 5, 30),
      );

      final json = original.toJson();
      expect(
        json.keys,
        containsAll(<String>[
          'client_message_id',
          'conversation_id',
          'sender_device_id',
          'group_id',
          'epoch',
          'ciphertext',
          'created_at',
        ]),
      );
      expect(json.containsKey('text'), isFalse);
      expect(json.containsKey('body'), isFalse);
      expect(json.containsKey('metadata'), isFalse);
      expect(json.containsKey('attachment'), isFalse);
      expect(json.containsKey('encryption_key'), isFalse);

      final restored = EncryptedOutboxEnvelope.fromJson(json);
      expect(restored.hasSameTransportIdentity(original), isTrue);
      expect(restored.createdAt, original.createdAt);
    });

    test('rejects malformed or plaintext-shaped envelopes', () {
      expect(
        () => EncryptedOutboxEnvelope.fromJson(<String, dynamic>{
          'client_message_id': 'id',
          'conversation_id': 'conversation',
          'sender_device_id': 'device',
          'group_id': 'group',
          'epoch': 1,
          'ciphertext': 'too-short',
          'created_at': DateTime.now().toIso8601String(),
          'text': 'must never be persisted',
        }),
        throwsFormatException,
      );
    });

    test('same client id cannot silently change its encrypted transport', () {
      final first = EncryptedOutboxEnvelope(
        clientMessageId: 'same-id',
        conversationId: 'conversation',
        senderDeviceId: 'device-12345678',
        groupId: 'group',
        epoch: 3,
        ciphertext: 'abcdefghijklmnop-original',
        createdAt: DateTime.utc(2026, 8, 23),
      );
      final changed = EncryptedOutboxEnvelope(
        clientMessageId: 'same-id',
        conversationId: 'conversation',
        senderDeviceId: 'device-12345678',
        groupId: 'group',
        epoch: 4,
        ciphertext: 'abcdefghijklmnop-changed',
        createdAt: DateTime.utc(2026, 8, 23),
      );

      expect(first.hasSameTransportIdentity(changed), isFalse);
    });
  });
}
