import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Durable retry envelope for an MLS application message.
///
/// Deliberately contains no cleartext body, caption, attachment key, reply
/// preview, or other application metadata. All of that is already sealed inside
/// [ciphertext] by the MLS client before this object can be persisted.
class EncryptedOutboxEnvelope {
  const EncryptedOutboxEnvelope({
    required this.clientMessageId,
    required this.conversationId,
    required this.senderDeviceId,
    required this.groupId,
    required this.epoch,
    required this.ciphertext,
    required this.createdAt,
  });

  final String clientMessageId;
  final String conversationId;
  final String senderDeviceId;
  final String groupId;
  final int epoch;
  final String ciphertext;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'client_message_id': clientMessageId,
        'conversation_id': conversationId,
        'sender_device_id': senderDeviceId,
        'group_id': groupId,
        'epoch': epoch,
        'ciphertext': ciphertext,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory EncryptedOutboxEnvelope.fromJson(Map<String, dynamic> json) {
    final clientMessageId = _requiredString(json, 'client_message_id');
    final conversationId = _requiredString(json, 'conversation_id');
    final senderDeviceId = _requiredString(json, 'sender_device_id');
    final groupId = _requiredString(json, 'group_id');
    final ciphertext = _requiredString(json, 'ciphertext');
    final epochValue = json['epoch'];
    final epoch = epochValue is int
        ? epochValue
        : int.tryParse(epochValue?.toString() ?? '');
    final createdAt = DateTime.tryParse(json['created_at']?.toString() ?? '');

    if (epoch == null || epoch < 0) {
      throw const FormatException('Encrypted outbox epoch is invalid.');
    }
    if (ciphertext.length < 16) {
      throw const FormatException('Encrypted outbox ciphertext is invalid.');
    }
    if (createdAt == null) {
      throw const FormatException('Encrypted outbox timestamp is invalid.');
    }

    return EncryptedOutboxEnvelope(
      clientMessageId: clientMessageId,
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      groupId: groupId,
      epoch: epoch,
      ciphertext: ciphertext,
      createdAt: createdAt.toUtc(),
    );
  }

  bool hasSameTransportIdentity(EncryptedOutboxEnvelope other) =>
      clientMessageId == other.clientMessageId &&
      conversationId == other.conversationId &&
      senderDeviceId == other.senderDeviceId &&
      groupId == other.groupId &&
      epoch == other.epoch &&
      ciphertext == other.ciphertext;

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key]?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw FormatException('Encrypted outbox field $key is missing.');
    }
    return value;
  }
}

/// Secure-storage backed queue for transport-level retries.
///
/// The queue is serialized per process to prevent two quick sends/reconnect
/// callbacks from overwriting each other's secure-storage snapshot.
class EncryptedMessageOutbox {
  EncryptedMessageOutbox({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const int maxPendingMessages = 256;
  static const String _keyPrefix = 'chaty.mls_outbox.v1';

  final FlutterSecureStorage _storage;
  Future<void> _tail = Future<void>.value();

  Future<List<EncryptedOutboxEnvelope>> pending(String userId) {
    return _exclusive(() => _readUnlocked(userId));
  }

  Future<void> enqueue(String userId, EncryptedOutboxEnvelope envelope) {
    return _exclusive(() async {
      final items = await _readUnlocked(userId);
      final existingIndex = items.indexWhere(
        (item) => item.clientMessageId == envelope.clientMessageId,
      );
      if (existingIndex >= 0) {
        final existing = items[existingIndex];
        if (!existing.hasSameTransportIdentity(envelope)) {
          throw StateError(
            'Refusing to mutate an existing encrypted outbox envelope.',
          );
        }
        return;
      }
      if (items.length >= maxPendingMessages) {
        throw StateError(
          'Encrypted outbox limit reached. Reconnect before sending more.',
        );
      }
      items.add(envelope);
      items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _writeUnlocked(userId, items);
    });
  }

  Future<void> remove(String userId, String clientMessageId) {
    return _exclusive(() async {
      final items = await _readUnlocked(userId);
      final previousLength = items.length;
      items.removeWhere((item) => item.clientMessageId == clientMessageId);
      if (items.length != previousLength) {
        await _writeUnlocked(userId, items);
      }
    });
  }

  Future<void> clear(String userId) {
    return _exclusive(() => _storage.delete(key: _key(userId)));
  }

  Future<List<EncryptedOutboxEnvelope>> _readUnlocked(String userId) async {
    final raw = await _storage.read(key: _key(userId));
    if (raw == null || raw.trim().isEmpty) {
      return <EncryptedOutboxEnvelope>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Encrypted outbox root is invalid.');
    }
    final items = <EncryptedOutboxEnvelope>[];
    for (final value in decoded) {
      if (value is! Map) {
        throw const FormatException('Encrypted outbox item is invalid.');
      }
      items.add(
        EncryptedOutboxEnvelope.fromJson(
          Map<String, dynamic>.from(value),
        ),
      );
    }
    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  Future<void> _writeUnlocked(
    String userId,
    List<EncryptedOutboxEnvelope> items,
  ) async {
    if (items.isEmpty) {
      await _storage.delete(key: _key(userId));
      return;
    }
    await _storage.write(
      key: _key(userId),
      value: jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.catchError((Object _) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static String _key(String userId) => '$_keyPrefix.$userId';
}
