enum MessageType {
  text,
  image,
  video,
  audio,
  document,
  location,
  contact,
  taskCard,
  system,
}

enum DeliveryState { queued, sending, sent, delivered, read, failed }

class MessageReaction {
  final String emoji;
  final List<String> userIds;

  const MessageReaction({required this.emoji, required this.userIds});

  MessageReaction copyWith({String? emoji, List<String>? userIds}) {
    return MessageReaction(
      emoji: emoji ?? this.emoji,
      userIds: userIds ?? this.userIds,
    );
  }
}

class MessageAttachment {
  final String id;
  final String type;
  final String name;
  final String size;
  final String? url;
  final int durationSeconds;

  /// End-to-end attachment encryption metadata. These values are serialized
  /// only inside the MLS application payload; the Storage object contains only
  /// opaque ciphertext bytes and never receives this key material.
  final int encryptionVersion;
  final String? encryptionAlgorithm;
  final String? encryptionKeyBase64;
  final String? encryptionNonceBase64;
  final String? encryptionMacBase64;
  final String? originalMimeType;
  final int? originalSizeBytes;

  const MessageAttachment({
    required this.id,
    required this.type,
    required this.name,
    required this.size,
    this.url,
    this.durationSeconds = 0,
    this.encryptionVersion = 0,
    this.encryptionAlgorithm,
    this.encryptionKeyBase64,
    this.encryptionNonceBase64,
    this.encryptionMacBase64,
    this.originalMimeType,
    this.originalSizeBytes,
  });

  bool get isEncrypted =>
      encryptionVersion > 0 &&
      encryptionAlgorithm != null &&
      encryptionKeyBase64 != null &&
      encryptionNonceBase64 != null &&
      encryptionMacBase64 != null;
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final MessageType type;
  final String text;
  final MessageAttachment? attachment;
  final Map<String, dynamic> metadata;
  final String? replyToMessageId;
  final String? replyToPreviewText;
  final String? replyToSenderName;
  final String? linkedTaskId;
  final List<MessageReaction> reactions;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DeliveryState deliveryState;
  final bool isPinned;
  final bool isStarred;
  final bool isDeletedForEveryone;
  final bool isDeletedForMe;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.type = MessageType.text,
    required this.text,
    this.attachment,
    this.metadata = const <String, dynamic>{},
    this.replyToMessageId,
    this.replyToPreviewText,
    this.replyToSenderName,
    this.linkedTaskId,
    this.reactions = const [],
    required this.createdAt,
    this.editedAt,
    this.deliveryState = DeliveryState.delivered,
    this.isPinned = false,
    this.isStarred = false,
    this.isDeletedForEveryone = false,
    this.isDeletedForMe = false,
  });

  ChatMessage copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    MessageType? type,
    String? text,
    MessageAttachment? attachment,
    Map<String, dynamic>? metadata,
    String? replyToMessageId,
    String? replyToPreviewText,
    String? replyToSenderName,
    String? linkedTaskId,
    List<MessageReaction>? reactions,
    DateTime? createdAt,
    DateTime? editedAt,
    DeliveryState? deliveryState,
    bool? isPinned,
    bool? isStarred,
    bool? isDeletedForEveryone,
    bool? isDeletedForMe,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      type: type ?? this.type,
      text: text ?? this.text,
      attachment: attachment ?? this.attachment,
      metadata: metadata ?? this.metadata,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToPreviewText: replyToPreviewText ?? this.replyToPreviewText,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      linkedTaskId: linkedTaskId ?? this.linkedTaskId,
      reactions: reactions ?? this.reactions,
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt ?? this.editedAt,
      deliveryState: deliveryState ?? this.deliveryState,
      isPinned: isPinned ?? this.isPinned,
      isStarred: isStarred ?? this.isStarred,
      isDeletedForEveryone: isDeletedForEveryone ?? this.isDeletedForEveryone,
      isDeletedForMe: isDeletedForMe ?? this.isDeletedForMe,
    );
  }
}
