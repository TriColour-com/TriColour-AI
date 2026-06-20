/// Role of a chat message — mirrors the `role` column constraint on the
/// server (`user` | `assistant` | `system`).
enum BackendMessageRole { user, assistant, system }

BackendMessageRole _roleFromString(String raw) {
  switch (raw) {
    case 'user':
      return BackendMessageRole.user;
    case 'system':
      return BackendMessageRole.system;
    default:
      return BackendMessageRole.assistant;
  }
}

String _roleToString(BackendMessageRole role) {
  switch (role) {
    case BackendMessageRole.user:
      return 'user';
    case BackendMessageRole.system:
      return 'system';
    case BackendMessageRole.assistant:
      return 'assistant';
  }
}

/// A single chat message, as stored/returned by the backend.
class BackendChatMessage {
  final String id;
  final String chatId;
  final BackendMessageRole role;
  final String content;
  final DateTime createdAt;

  BackendChatMessage({
    required this.id,
    required this.chatId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  factory BackendChatMessage.fromJson(Map<String, dynamic> json) =>
      BackendChatMessage(
        id: json['id'] as String,
        chatId: json['chat_id'] as String,
        role: _roleFromString(json['role'] as String? ?? 'assistant'),
        content: json['content'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ??
                DateTime.now(),
      );

  /// Builds a transient, locally-rendered message (e.g. optimistic UI before
  /// the server confirms it, or a typing indicator placeholder).
  factory BackendChatMessage.local({
    required String chatId,
    required BackendMessageRole role,
    required String content,
  }) =>
      BackendChatMessage(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        chatId: chatId,
        role: role,
        content: content,
        createdAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'chat_id': chatId,
        'role': _roleToString(role),
        'content': content,
        'created_at': createdAt.toIso8601String(),
      };

  bool get isUser => role == BackendMessageRole.user;
}

/// A chat conversation summary, as shown in the sidebar list.
class ChatSummary {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;
  final String? lastMessage;

  ChatSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
    this.lastMessage,
  });

  factory ChatSummary.fromJson(Map<String, dynamic> json) => ChatSummary(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'New chat',
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ??
                DateTime.now(),
        updatedAt:
            DateTime.tryParse(json['updated_at'] as String? ?? '') ??
                DateTime.now(),
        messageCount: json['message_count'] as int? ?? 0,
        lastMessage: json['last_message'] as String?,
      );

  ChatSummary copyWith({String? title, DateTime? updatedAt}) => ChatSummary(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        messageCount: messageCount,
        lastMessage: lastMessage,
      );
}