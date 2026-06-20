import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/chat_models.dart';

/// Talks exclusively to our own local backend server.
///
/// IMPORTANT: This app never holds or sends a Gemini API key. The key lives
/// only in the backend's `.env` file. Flutter just calls these plain REST
/// endpoints, and the backend is the only thing that talks to Gemini.
///
/// Configure [baseUrl] for your setup:
///   • Android emulator   → http://10.0.2.2:4000        (special alias for host machine)
///   • iOS simulator      → http://localhost:4000
///   • Physical device    → http://<your-computer-LAN-IP>:4000
///   • Desktop / web      → http://localhost:4000
class ApiService {
  ApiService({String? baseUrl, this.appKey})
      : baseUrl = baseUrl ?? defaultBaseUrl;

  /// Change this constant (or pass baseUrl explicitly) to match how your
  /// device reaches the backend. See class doc above.
  static const String defaultBaseUrl = 'http://10.0.2.2:4000';

  final String baseUrl;

  /// Optional shared key — only needed if you set APP_SHARED_KEY in the
  /// backend's .env file. Leave null for local development.
  final String? appKey;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (appKey != null && appKey!.isNotEmpty) 'X-App-Key': appKey!,
      };

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  // ─── Chats ──────────────────────────────────────────────────────────────

  Future<List<ChatSummary>> listChats() async {
    final res = await http
        .get(_uri('/chats'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    _checkOk(res);
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .map((e) => ChatSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ChatSummary> createChat({String? title}) async {
    final res = await http
        .post(
          _uri('/chats'),
          headers: _headers,
          body: jsonEncode({if (title != null) 'title': title}),
        )
        .timeout(const Duration(seconds: 15));
    _checkOk(res);
    return ChatSummary.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Fetch a chat's full message history.
  Future<List<BackendChatMessage>> getChatMessages(String chatId) async {
    final res = await http
        .get(_uri('/chats/$chatId'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    _checkOk(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final messages = body['messages'] as List<dynamic>? ?? [];
    return messages
        .map((e) =>
            BackendChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ChatSummary> renameChat(String chatId, String title) async {
    final res = await http
        .put(
          _uri('/chats/$chatId'),
          headers: _headers,
          body: jsonEncode({'title': title}),
        )
        .timeout(const Duration(seconds: 15));
    _checkOk(res);
    return ChatSummary.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> deleteChat(String chatId) async {
    final res = await http
        .delete(_uri('/chats/$chatId'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 204) _checkOk(res);
  }

  // ─── Messaging ──────────────────────────────────────────────────────────

  /// Sends [message] to the backend for [chatId]. The backend persists it,
  /// forwards the whole conversation to Gemini, persists the reply, and
  /// returns just the reply text — Flutter never sees the API key or talks
  /// to Gemini directly.
  Future<String> sendMessage({
    required String chatId,
    required String message,
  }) async {
    final res = await http
        .post(
          _uri('/chat'),
          headers: _headers,
          body: jsonEncode({'chat_id': chatId, 'message': message}),
        )
        .timeout(const Duration(seconds: 60));
    _checkOk(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['reply'] as String? ?? '';
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  void _checkOk(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    String message = 'Server error (${res.statusCode})';
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      message = body['error'] as String? ?? message;
    } catch (_) {
      // response wasn't JSON — keep the generic message
    }
    throw ApiException(message);
  }
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}