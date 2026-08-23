from pathlib import Path

path = Path('lib/data/services/backend_service.dart')
text = path.read_text(encoding='utf-8')

if "import 'dart:io';" not in text:
    text = text.replace("import 'dart:async';\n", "import 'dart:async';\nimport 'dart:io';\n", 1)
if "import 'encrypted_message_outbox.dart';" not in text:
    text = text.replace(
        "import 'mls_e2ee_service.dart';\n",
        "import 'encrypted_message_outbox.dart';\nimport 'mls_e2ee_service.dart';\n",
        1,
    )

field_marker = "  final Uuid _uuid = const Uuid();\n"
if 'final EncryptedMessageOutbox _encryptedOutbox' not in text:
    if field_marker not in text:
        raise SystemExit('Phase 4 outbox UUID field marker missing')
    text = text.replace(
        field_marker,
        field_marker +
        "  final EncryptedMessageOutbox _encryptedOutbox = EncryptedMessageOutbox();\n",
        1,
    )

state_marker = "  bool _isHydrating = false;\n"
if 'bool _isFlushingEncryptedOutbox = false;' not in text:
    if state_marker not in text:
        raise SystemExit('Phase 4 outbox hydration marker missing')
    text = text.replace(
        state_marker,
        state_marker + "  bool _isFlushingEncryptedOutbox = false;\n",
        1,
    )

session_old = """    _currentSession = _mapSession(session);
    await _hydrateAuthenticatedState();
    await _subscribeRealtime();
  }
"""
session_new = """    _currentSession = _mapSession(session);
    await _hydrateAuthenticatedState();
    await _subscribeRealtime();
    unawaited(_flushEncryptedOutbox());
  }
"""
if 'unawaited(_flushEncryptedOutbox());' not in text[text.find('Future<void> _handleSession'):text.find('AuthSession _mapSession')]:
    if session_old not in text:
        raise SystemExit('Phase 4 session outbox marker missing')
    text = text.replace(session_old, session_new, 1)

subscribe_old = """        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tasks',
          callback: (_) => _scheduleTaskReconciliation(),
        )
        .subscribe();
    _realtimeChannel = channel;
"""
subscribe_new = """        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tasks',
          callback: (_) => _scheduleTaskReconciliation(),
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(_flushEncryptedOutbox());
          }
        });
    _realtimeChannel = channel;
"""
if '.subscribe((status, error)' not in text:
    if subscribe_old not in text:
        raise SystemExit('Phase 4 realtime subscribe marker missing')
    text = text.replace(subscribe_old, subscribe_new, 1)

send_old = """    final raw = await _client.rpc(
      'send_mls_message_v1',
      params: <String, dynamic>{
        'p_conversation_id': conversationId,
        'p_client_message_id': clientMessageId,
        'p_sender_device_id': deviceId,
        'p_group_id': encrypted.groupId,
        'p_epoch': encrypted.epoch,
        'p_ciphertext': encrypted.ciphertext,
      },
    );
    final messageId = raw?.toString() ?? '';
    await Future.wait<void>(<Future<void>>[
      _loadMessages(conversationId),
      _loadConversations(loadMembers: false),
    ]);
    notifyListeners();

    final result = _messagesByChatId[conversationId]!.firstWhere(
      (message) => message.id == messageId,
      orElse: () => ChatMessage(
        id: messageId,
        conversationId: conversationId,
        senderId: me.id,
        type: type,
        text: text.trim(),
        attachment: attachment,
        createdAt: DateTime.now(),
        deliveryState: DeliveryState.sent,
      ),
    );
    eventBus.publish(
      RealtimeEvent(
        type: RealtimeEventType.messageCreated,
        conversationId: conversationId,
        userId: me.id,
        payload: <String, dynamic>{'messageId': result.id},
      ),
    );
    return result;
"""
send_new = """    final envelope = EncryptedOutboxEnvelope(
      clientMessageId: clientMessageId,
      conversationId: conversationId,
      senderDeviceId: deviceId,
      groupId: encrypted.groupId,
      epoch: encrypted.epoch,
      ciphertext: encrypted.ciphertext,
      createdAt: DateTime.now().toUtc(),
    );

    String messageId;
    try {
      messageId = await _sendEncryptedEnvelope(envelope);
    } catch (error) {
      if (!_isTransientTransportError(error)) rethrow;
      await _encryptedOutbox.enqueue(me.id, envelope);
      final queued = ChatMessage(
        id: 'pending:$clientMessageId',
        conversationId: conversationId,
        senderId: me.id,
        type: type,
        text: text.trim(),
        attachment: attachment,
        metadata: metadata,
        replyToMessageId: replyToMessageId,
        replyToPreviewText: replyToPreviewText,
        replyToSenderName: replyToSenderName,
        linkedTaskId: linkedTaskId,
        createdAt: envelope.createdAt.toLocal(),
        deliveryState: DeliveryState.queued,
      );
      _upsertLocalMessage(queued);
      notifyListeners();
      eventBus.publish(
        RealtimeEvent(
          type: RealtimeEventType.messageCreated,
          conversationId: conversationId,
          userId: me.id,
          payload: <String, dynamic>{
            'messageId': queued.id,
            'queued': true,
          },
        ),
      );
      return queued;
    }

    await Future.wait<void>(<Future<void>>[
      _loadMessages(conversationId),
      _loadConversations(loadMembers: false),
    ]);
    notifyListeners();

    final result = _messagesByChatId[conversationId]!.firstWhere(
      (message) => message.id == messageId,
      orElse: () => ChatMessage(
        id: messageId,
        conversationId: conversationId,
        senderId: me.id,
        type: type,
        text: text.trim(),
        attachment: attachment,
        metadata: metadata,
        replyToMessageId: replyToMessageId,
        replyToPreviewText: replyToPreviewText,
        replyToSenderName: replyToSenderName,
        linkedTaskId: linkedTaskId,
        createdAt: DateTime.now(),
        deliveryState: DeliveryState.sent,
      ),
    );
    eventBus.publish(
      RealtimeEvent(
        type: RealtimeEventType.messageCreated,
        conversationId: conversationId,
        userId: me.id,
        payload: <String, dynamic>{'messageId': result.id},
      ),
    );
    return result;
"""
if 'final envelope = EncryptedOutboxEnvelope(' not in text:
    if send_old not in text:
        raise SystemExit('Phase 4 encrypted send block marker missing')
    text = text.replace(send_old, send_new, 1)

helper_marker = """  void toggleReaction(String conversationId, String messageId, String emoji) {
"""
helpers = r'''  Future<String> _sendEncryptedEnvelope(
    EncryptedOutboxEnvelope envelope,
  ) async {
    final raw = await _client.rpc(
      'send_mls_message_v1',
      params: <String, dynamic>{
        'p_conversation_id': envelope.conversationId,
        'p_client_message_id': envelope.clientMessageId,
        'p_sender_device_id': envelope.senderDeviceId,
        'p_group_id': envelope.groupId,
        'p_epoch': envelope.epoch,
        'p_ciphertext': envelope.ciphertext,
      },
    );
    final messageId = raw?.toString().trim() ?? '';
    if (messageId.isEmpty) {
      throw const FormatException('Encrypted send returned no message id.');
    }
    return messageId;
  }

  bool _isTransientTransportError(Object error) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is HandshakeException ||
        error is HttpException) {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('failed host lookup') ||
        message.contains('connection reset') ||
        message.contains('connection refused') ||
        message.contains('network is unreachable') ||
        message.contains('network unreachable') ||
        message.contains('connection closed') ||
        message.contains('connection terminated') ||
        message.contains('software caused connection abort') ||
        message.contains('timed out') ||
        message.contains('timeout');
  }

  void _upsertLocalMessage(ChatMessage message) {
    final timeline = List<ChatMessage>.from(
      _messagesByChatId[message.conversationId] ?? const <ChatMessage>[],
    );
    final index = timeline.indexWhere((item) => item.id == message.id);
    if (index >= 0) {
      timeline[index] = message;
    } else {
      timeline.add(message);
    }
    timeline.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _messagesByChatId[message.conversationId] = timeline;

    final conversation = _conversationsById[message.conversationId];
    if (conversation != null) {
      _conversationsById[message.conversationId] = conversation.copyWith(
        lastMessageText: message.text,
        lastMessageTime: message.createdAt,
        lastMessageSenderId: message.senderId,
      );
    }
  }

  void _markQueuedMessageSent(
    String clientMessageId,
    String serverMessageId,
  ) {
    final pendingId = 'pending:$clientMessageId';
    for (final entry in _messagesByChatId.entries) {
      final index = entry.value.indexWhere((message) => message.id == pendingId);
      if (index < 0) continue;
      final timeline = List<ChatMessage>.from(entry.value);
      timeline[index] = timeline[index].copyWith(
        id: serverMessageId,
        deliveryState: DeliveryState.sent,
      );
      _messagesByChatId[entry.key] = timeline;
      return;
    }
  }

  void _markQueuedMessageFailed(String clientMessageId) {
    final pendingId = 'pending:$clientMessageId';
    for (final entry in _messagesByChatId.entries) {
      final index = entry.value.indexWhere((message) => message.id == pendingId);
      if (index < 0) continue;
      final timeline = List<ChatMessage>.from(entry.value);
      timeline[index] = timeline[index].copyWith(
        deliveryState: DeliveryState.failed,
      );
      _messagesByChatId[entry.key] = timeline;
      return;
    }
  }

  Future<void> _flushEncryptedOutbox() async {
    if (_isFlushingEncryptedOutbox) return;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    _isFlushingEncryptedOutbox = true;
    final refreshedConversations = <String>{};
    try {
      final pending = await _encryptedOutbox.pending(userId);
      for (final envelope in pending) {
        if (_client.auth.currentUser?.id != userId) return;
        try {
          final messageId = await _sendEncryptedEnvelope(envelope);
          await _encryptedOutbox.remove(userId, envelope.clientMessageId);
          _markQueuedMessageSent(envelope.clientMessageId, messageId);
          refreshedConversations.add(envelope.conversationId);
        } catch (error, stackTrace) {
          if (_isTransientTransportError(error)) {
            debugPrint('Chaty encrypted outbox remains queued: $error');
            break;
          }
          debugPrint(
            'Chaty encrypted outbox permanently rejected '
            '${envelope.clientMessageId}: $error\n$stackTrace',
          );
          await _encryptedOutbox.remove(userId, envelope.clientMessageId);
          _markQueuedMessageFailed(envelope.clientMessageId);
        }
      }

      if (refreshedConversations.isNotEmpty) {
        try {
          await _loadConversations(loadMembers: false);
          for (final conversationId in refreshedConversations) {
            if (_messagesByChatId.containsKey(conversationId)) {
              await _loadMessages(conversationId);
            }
          }
        } catch (error, stackTrace) {
          debugPrint(
            'Chaty outbox post-send reconciliation failed: '
            '$error\n$stackTrace',
          );
        }
        notifyListeners();
      }
    } finally {
      _isFlushingEncryptedOutbox = false;
    }
  }

'''
if 'Future<void> _flushEncryptedOutbox() async' not in text:
    if helper_marker not in text:
        raise SystemExit('Phase 4 outbox helper insertion marker missing')
    text = text.replace(helper_marker, helpers + helper_marker, 1)

logout_old = """  Future<void> logout() async {
    try {
      await setPresence(PresenceState.offline);
    } catch (_) {}
    if (locator.isRegistered<MlsE2eeService>()) {
      await locator<MlsE2eeService>().close();
    }
    await _client.auth.signOut();
    await _handleSession(null);
  }
"""
logout_new = """  Future<void> logout() async {
    final userId = _client.auth.currentUser?.id;
    try {
      await setPresence(PresenceState.offline);
    } catch (_) {}
    if (userId != null) {
      await _encryptedOutbox.clear(userId);
    }
    if (locator.isRegistered<MlsE2eeService>()) {
      await locator<MlsE2eeService>().close();
    }
    await _client.auth.signOut();
    await _handleSession(null);
  }
"""
if 'await _encryptedOutbox.clear(userId);' not in text:
    if logout_old not in text:
        raise SystemExit('Phase 4 logout outbox marker missing')
    text = text.replace(logout_old, logout_new, 1)

required = [
    "import 'dart:io';",
    "import 'encrypted_message_outbox.dart';",
    'final EncryptedMessageOutbox _encryptedOutbox',
    'final envelope = EncryptedOutboxEnvelope(',
    'await _encryptedOutbox.enqueue(me.id, envelope);',
    'Future<void> _flushEncryptedOutbox() async',
    '.subscribe((status, error)',
    'await _encryptedOutbox.clear(userId);',
]
for marker in required:
    if marker not in text:
        raise SystemExit(f'Phase 4 encrypted outbox marker missing: {marker}')

path.write_text(text, encoding='utf-8')
