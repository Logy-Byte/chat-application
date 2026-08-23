from pathlib import Path
import re

backend = Path('lib/data/services/backend_service.dart')
text = backend.read_text(encoding='utf-8')

if 'static const int _messagePageSize = 50;' not in text:
    marker = "  bool _pendingTaskRefresh = false;\n"
    if marker not in text:
        raise SystemExit('Phase 4 backend pending-task marker missing')
    text = text.replace(
        marker,
        marker
        + "  static const int _messagePageSize = 50;\n"
        + "  final Map<String, bool> _messageHasMoreByChatId = <String, bool>{};\n",
        1,
    )

    block = re.search(
        r"  Future<void> ensureConversationLoaded\(String conversationId\) async \{.*?\n  Future<Map<String, dynamic>> _hydrateEncryptedMessageRow\(",
        text,
        flags=re.S,
    )
    if block is None:
        raise SystemExit('Phase 4 backend message-load block missing')
    replacement = '''  Future<void> ensureConversationLoaded(String conversationId) async {
    if (!_conversationsById.containsKey(conversationId)) {
      await _loadConversations();
    }
    await _loadConversationMembers(conversationId);
    await _loadMessages(conversationId, replaceTimeline: true);
    await markAsRead(conversationId);
  }

  bool hasOlderMessages(String conversationId) =>
      _messageHasMoreByChatId[conversationId] ?? false;

  Future<bool> loadOlderMessages(String conversationId) async {
    final current = _messagesByChatId[conversationId];
    if (current == null || current.isEmpty) {
      await _loadMessages(conversationId, replaceTimeline: true);
      return _messagesByChatId[conversationId]?.isNotEmpty ?? false;
    }
    if (!hasOlderMessages(conversationId)) return false;

    final before = current.first.createdAt;
    final previousCount = current.length;
    await _loadMessages(
      conversationId,
      before: before,
      appendOlder: true,
    );
    return (_messagesByChatId[conversationId]?.length ?? 0) > previousCount;
  }

  Future<void> _loadMessages(
    String conversationId, {
    DateTime? before,
    bool appendOlder = false,
    bool replaceTimeline = false,
  }) async {
    final raw = await _client.rpc(
      'get_conversation_messages',
      params: <String, dynamic>{
        'p_conversation_id': conversationId,
        'p_limit': _messagePageSize,
        if (before != null) 'p_before': before.toUtc().toIso8601String(),
      },
    );
    final rows = _asRows(raw);
    final hydratedRows = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row['is_hidden'] == true) continue;
      hydratedRows.add(await _hydrateEncryptedMessageRow(conversationId, row));
    }
    final fetched = hydratedRows.map(_messageFromRow).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final existing = _messagesByChatId[conversationId] ?? const <ChatMessage>[];
    List<ChatMessage> next;
    if (replaceTimeline || existing.isEmpty) {
      next = fetched;
      _messageHasMoreByChatId[conversationId] = rows.length >= _messagePageSize;
    } else if (appendOlder) {
      final byId = <String, ChatMessage>{
        for (final message in fetched) message.id: message,
        for (final message in existing) message.id: message,
      };
      next = byId.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _messageHasMoreByChatId[conversationId] = rows.length >= _messagePageSize;
    } else {
      final earliestFetched = fetched.isEmpty ? null : fetched.first.createdAt;
      final byId = <String, ChatMessage>{};
      if (earliestFetched != null) {
        for (final message in existing) {
          if (message.createdAt.isBefore(earliestFetched)) {
            byId[message.id] = message;
          }
        }
      }
      for (final message in fetched) {
        byId[message.id] = message;
      }
      next = byId.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    _messagesByChatId[conversationId] = next;

    final conversation = _conversationsById[conversationId];
    if (conversation != null && next.isNotEmpty) {
      final latest = next.last;
      _conversationsById[conversationId] = conversation.copyWith(
        lastMessageText: latest.text,
        lastMessageTime: latest.createdAt,
        lastMessageSenderId: latest.senderId,
      );
    }
  }

  Future<Map<String, dynamic>> _hydrateEncryptedMessageRow('''
    text = text[: block.start()] + replacement + text[block.end() :]
    text = text.replace(
        "      _messagesByChatId.clear();\n      _tasks.clear();",
        "      _messagesByChatId.clear();\n      _messageHasMoreByChatId.clear();\n      _tasks.clear();",
        1,
    )
    text = text.replace(
        "      _messagesByChatId.removeWhere((id, _) => !next.containsKey(id));",
        "      _messagesByChatId.removeWhere((id, _) => !next.containsKey(id));\n"
        "      _messageHasMoreByChatId.removeWhere((id, _) => !next.containsKey(id));",
        1,
    )
backend.write_text(text, encoding='utf-8')

store = Path('lib/data/repositories/mock_data_store.dart')
text = store.read_text(encoding='utf-8')
marker = """  Future<void> ensureConversationLoaded(String conversationId) =>
      _backend.ensureConversationLoaded(conversationId);
"""
addition = marker + """
  bool hasOlderMessages(String conversationId) =>
      _backend.hasOlderMessages(conversationId);

  Future<bool> loadOlderMessages(String conversationId) =>
      _backend.loadOlderMessages(conversationId);
"""
if 'Future<bool> loadOlderMessages(String conversationId)' not in text:
    if marker not in text:
        raise SystemExit('Phase 4 data-store conversation marker missing')
    text = text.replace(marker, addition, 1)
store.write_text(text, encoding='utf-8')

screen = Path('lib/features/chats/chat_detail_screen.dart')
text = screen.read_text(encoding='utf-8')
if 'bool _loadingOlderMessages = false;' not in text:
    marker = "  bool _loadingMessages = true;\n"
    if marker not in text:
        raise SystemExit('Phase 4 loading-messages marker missing')
    text = text.replace(
        marker,
        marker + "  bool _loadingOlderMessages = false;\n",
        1,
    )

handler = """  void _handleScrollChanged() {
    if (!_scrollCtrl.hasClients) return;
    final position = _scrollCtrl.position;
"""
new_handler = """  void _handleScrollChanged() {
    if (!_scrollCtrl.hasClients) return;
    final position = _scrollCtrl.position;
    if (position.pixels <= 180 &&
        !_loadingOlderMessages &&
        widget.dataStore.hasOlderMessages(widget.conversationId)) {
      unawaited(_loadOlderMessages());
    }
"""
if 'unawaited(_loadOlderMessages());' not in text:
    if handler not in text:
        raise SystemExit('Phase 4 scroll handler marker missing')
    text = text.replace(handler, new_handler, 1)

insert_before = """  /// Store listener implementing the shared WhatsApp/Telegram/Instagram
"""
load_method = """  Future<void> _loadOlderMessages() async {
    if (_loadingOlderMessages || !_scrollCtrl.hasClients) return;
    if (!widget.dataStore.hasOlderMessages(widget.conversationId)) return;

    final beforeExtent = _scrollCtrl.position.maxScrollExtent;
    final beforePixels = _scrollCtrl.position.pixels;
    setState(() => _loadingOlderMessages = true);
    try {
      final loaded = await widget.dataStore.loadOlderMessages(
        widget.conversationId,
      );
      if (!mounted || !loaded) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollCtrl.hasClients) return;
        final extentDelta = _scrollCtrl.position.maxScrollExtent - beforeExtent;
        if (extentDelta <= 0) return;
        final target = (beforePixels + extentDelta).clamp(
          _scrollCtrl.position.minScrollExtent,
          _scrollCtrl.position.maxScrollExtent,
        );
        _scrollCtrl.jumpTo(target.toDouble());
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load older messages: $error')),
      );
    } finally {
      if (mounted) setState(() => _loadingOlderMessages = false);
    }
  }

"""
if 'Future<void> _loadOlderMessages() async' not in text:
    if insert_before not in text:
        raise SystemExit('Phase 4 store-listener marker missing')
    text = text.replace(insert_before, load_method + insert_before, 1)

listener_start = text.find('void _onDataStoreChanged()')
if listener_start < 0:
    raise SystemExit('Phase 4 data-store listener missing')
if 'if (_loadingOlderMessages) {' not in text[listener_start:]:
    old = """    final grew = count > previous;
    if (!mounted) return;
    if (!grew) {
"""
    new = """    final grew = count > previous;
    if (!mounted) return;
    if (_loadingOlderMessages) {
      _lastKnownMessageCount = count;
      return;
    }
    if (!grew) {
"""
    if old not in text:
        raise SystemExit('Phase 4 data-store listener growth marker missing')
    text = text.replace(old, new, 1)

screen.write_text(text, encoding='utf-8')

checks = {
    backend: [
        'static const int _messagePageSize = 50;',
        'Future<bool> loadOlderMessages(String conversationId)',
    ],
    store: ['Future<bool> loadOlderMessages(String conversationId)'],
    screen: [
        'unawaited(_loadOlderMessages());',
        'Future<void> _loadOlderMessages() async',
    ],
}
for file, markers in checks.items():
    current = file.read_text(encoding='utf-8')
    for marker in markers:
        if marker not in current:
            raise SystemExit(f'Phase 4 pagination marker missing in {file}: {marker}')
