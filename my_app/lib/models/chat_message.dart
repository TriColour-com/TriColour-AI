enum MessageRole { user, assistant, system }

enum MessageType { text, code, file, status }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.type = MessageType.text,
    DateTime? timestamp,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ChatMessage.user(String content) => ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user,
        content: content,
      );

  factory ChatMessage.assistant(
    String content, {
    MessageType? type,
    Map<String, dynamic>? metadata,
  }) =>
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.assistant,
        content: content,
        type: type ?? MessageType.text,
        metadata: metadata,
      );

  factory ChatMessage.status(String content) => ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.assistant,
        content: content,
        type: MessageType.status,
      );

  Map<String, String> toApiFormat() => {
        'role': role == MessageRole.user ? 'user' : 'assistant',
        'content': content,
      };

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
  bool get isCode => type == MessageType.code;
  bool get isStatus => type == MessageType.status;
}

class DiagnosisQuestion {
  final int number;
  final String question;
  final String? answer;
  final String category;

  DiagnosisQuestion({
    required this.number,
    required this.question,
    this.answer,
    required this.category,
  });

  DiagnosisQuestion withAnswer(String answer) => DiagnosisQuestion(
        number: number,
        question: question,
        answer: answer,
        category: category,
      );
}

/// Holds the completed diagnosis session so it can be reused in the
/// Telegram Bot builder for personalised bot generation.
class DiagnosisSession {
  /// Full Q&A conversation history (user + assistant turns).
  final List<Map<String, String>> conversationHistory;

  /// The final analysis text returned by the AI.
  final String analysisResult;

  /// Timestamp when the session finished.
  final DateTime completedAt;

  DiagnosisSession({
    required this.conversationHistory,
    required this.analysisResult,
    DateTime? completedAt,
  }) : completedAt = completedAt ?? DateTime.now();

  /// Returns a concise summary string suitable for injecting into a bot-
  /// builder prompt without sending the entire transcript.
  String buildContextSummary() {
    final buffer = StringBuffer();
    buffer.writeln('=== USER PERSONALITY CONTEXT (from Character Diagnosis) ===');
    buffer.writeln(analysisResult);
    buffer.writeln('=== END CONTEXT ===');
    return buffer.toString();
  }
}

/// Singleton in-memory store for the latest diagnosis session.
/// Cleared when the app restarts (privacy by default).
class DiagnosisStore {
  DiagnosisStore._();
  static DiagnosisSession? _current;

  static DiagnosisSession? get current => _current;

  static void save(DiagnosisSession session) => _current = session;

  static void clear() => _current = null;

  static bool get hasSession => _current != null;
}