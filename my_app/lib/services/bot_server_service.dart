import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Status values that map to the server's bot lifecycle states.
enum BotRunStatus { idle, starting, running, error, stopped }

/// A single log entry returned by the server.
class BotLogEntry {
  final DateTime timestamp;
  final String message;
  final bool isError;

  BotLogEntry({
    required this.timestamp,
    required this.message,
    this.isError = false,
  });

  factory BotLogEntry.fromJson(Map<String, dynamic> json) => BotLogEntry(
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        message: json['message'] as String? ?? '',
        isError: json['is_error'] as bool? ?? false,
      );
}

/// A snapshot of the bot's current state from the server.
class BotState {
  final String? botId;
  final BotRunStatus status;
  final String? errorMessage;
  final List<BotLogEntry> logs;

  const BotState({
    this.botId,
    this.status = BotRunStatus.idle,
    this.errorMessage,
    this.logs = const [],
  });

  BotState copyWith({
    String? botId,
    BotRunStatus? status,
    String? errorMessage,
    List<BotLogEntry>? logs,
  }) =>
      BotState(
        botId: botId ?? this.botId,
        status: status ?? this.status,
        errorMessage: errorMessage ?? this.errorMessage,
        logs: logs ?? this.logs,
      );
}

/// Service layer that talks to your backend API.
///
/// ─── Backend contract ────────────────────────────────────────────────────────
///
///  POST   /bots/create    body: { code, token? }  → { bot_id }
///  POST   /bots/:id/run                           → { status }
///  POST   /bots/:id/stop                          → { status }
///  GET    /bots/:id/status                        → { status, error? }
///  GET    /bots/:id/logs                          → [{ timestamp, message, is_error }]
///
/// Set [baseUrl] to your actual server URL before shipping.
/// Set [apiKey] if your server requires Bearer authentication.
/// ─────────────────────────────────────────────────────────────────────────────
class BotServerService {
  // ─── Configuration – change these before deploying ──────────────────────────
  static const String baseUrl = 'https://your-bot-server.example.com';
  static const String apiKey = ''; // leave empty if not needed

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      };

  // ─── API calls ──────────────────────────────────────────────────────────────

  /// Upload generated Python code (and optional bot token) to the server.
  /// Returns the server-assigned [botId] on success.
  static Future<String> createBot({
    required String code,
    String? botToken,
  }) async {
    final response = await _post('/bots/create', {
      'code': code,
      if (botToken != null && botToken.isNotEmpty) 'token': botToken,
    });
    final id = response['bot_id'] as String?;
    if (id == null || id.isEmpty) {
      throw BotServerException('Server returned no bot_id');
    }
    return id;
  }

  /// Tell the server to start running the bot identified by [botId].
  static Future<BotRunStatus> runBot(String botId) async {
    final response = await _post('/bots/$botId/run', {});
    return _parseStatus(response['status'] as String? ?? '');
  }

  /// Tell the server to stop the bot.
  static Future<BotRunStatus> stopBot(String botId) async {
    final response = await _post('/bots/$botId/stop', {});
    return _parseStatus(response['status'] as String? ?? '');
  }

  /// Fetch the current status of the bot.
  static Future<BotState> getBotStatus(String botId) async {
    final response = await _get('/bots/$botId/status');
    return BotState(
      botId: botId,
      status: _parseStatus(response['status'] as String? ?? ''),
      errorMessage: response['error'] as String?,
    );
  }

  /// Fetch recent log lines from the server.
  static Future<List<BotLogEntry>> getBotLogs(String botId) async {
    final response = await _getList('/bots/$botId/logs');
    return response
        .map((e) => BotLogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── Polling helper ─────────────────────────────────────────────────────────

  /// Polls [getBotStatus] every [interval] until [until] returns true or
  /// [timeout] elapses. Yields each [BotState] as it arrives.
  static Stream<BotState> pollStatus(
    String botId, {
    Duration interval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 5),
    bool Function(BotState)? until,
  }) async* {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final state = await getBotStatus(botId);
      yield state;
      if (until != null && until(state)) break;
      await Future.delayed(interval);
    }
  }

  // ─── Internal HTTP helpers ──────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(res);
    } on BotServerException {
      rethrow;
    } catch (e) {
      throw BotServerException('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> _get(String path) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl$path'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(res);
    } on BotServerException {
      rethrow;
    } catch (e) {
      throw BotServerException('Network error: $e');
    }
  }

  static Future<List<dynamic>> _getList(String path) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl$path'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) return decoded;
        throw BotServerException('Expected list response from $path');
      }
      _handleResponse(res); // throws
      return [];
    } on BotServerException {
      rethrow;
    } catch (e) {
      throw BotServerException('Network error: $e');
    }
  }

  static Map<String, dynamic> _handleResponse(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      try {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        return {};
      }
    }
    String? serverMsg;
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      serverMsg = body['error'] as String? ?? body['message'] as String?;
    } catch (_) {}
    throw BotServerException(
      serverMsg ?? 'Server error ${res.statusCode}',
    );
  }

  static BotRunStatus _parseStatus(String raw) {
    switch (raw.toLowerCase()) {
      case 'starting':
        return BotRunStatus.starting;
      case 'running':
        return BotRunStatus.running;
      case 'error':
        return BotRunStatus.error;
      case 'stopped':
        return BotRunStatus.stopped;
      default:
        return BotRunStatus.idle;
    }
  }
}

class BotServerException implements Exception {
  final String message;
  const BotServerException(this.message);
  @override
  String toString() => message;
}