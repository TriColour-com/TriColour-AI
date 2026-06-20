import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/bot_server_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/chat_bubble.dart';

class TelegramBotScreen extends StatefulWidget {
  const TelegramBotScreen({super.key});

  @override
  State<TelegramBotScreen> createState() => _TelegramBotScreenState();
}

class _TelegramBotScreenState extends State<TelegramBotScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _isLoading = false;

  // Generated bot state
  String? _generatedBotCode;
  BotState _botState = const BotState();
  StreamSubscription<BotState>? _pollSub;

  @override
  void initState() {
    super.initState();
    _sendInitialGreeting();
  }

  @override
  void dispose() {
    _pollSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─── Greeting ───────────────────────────────────────────────────────────────

  Future<void> _sendInitialGreeting() async {
    setState(() => _isLoading = true);

    // Check whether a completed diagnosis session exists and inject context
    final session = DiagnosisStore.current;
    final systemPrompt = AIService.telegramBotSystemPrompt(
      personalityContext: session?.buildContextSummary(),
    );

    // If personality context is available, hint the AI to acknowledge it
    final firstUserMessage = session != null
        ? 'Hello! I just completed a character diagnosis. '
            'Please start the bot creation process — you can use what you know about me.'
        : 'Hello, start the bot creation process.';

    try {
      final response = await AIService.sendMessage(
        messages: [
          {'role': 'user', 'content': firstUserMessage}
        ],
        systemPrompt: systemPrompt,
      );
      setState(() {
        _messages.add(ChatMessage.assistant(response));
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _messages.add(ChatMessage.assistant(
            '⚠️ Failed to connect to AI. Please check your API key and try again.'));
      });
    }
  }

  // ─── Messaging ──────────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isLoading) return;

    _inputCtrl.clear();
    final userMsg = ChatMessage.user(text);
    setState(() {
      _messages.add(userMsg);
      _isLoading = true;
    });
    _scrollToBottom();

    // Rebuild system prompt each turn in case session appeared mid-chat
    final session = DiagnosisStore.current;
    final systemPrompt = AIService.telegramBotSystemPrompt(
      personalityContext: session?.buildContextSummary(),
    );

    try {
      final history = _messages
          .where((m) => !m.isStatus)
          .map((m) => m.toApiFormat())
          .toList();

      final response = await AIService.sendMessage(
        messages: history,
        systemPrompt: systemPrompt,
        maxTokens: 4096,
      );

      String displayText = response;
      if (response.contains('===BOT_CODE_START===')) {
        final codeMatch = RegExp(
          r'===BOT_CODE_START===\n?([\s\S]*?)\n?===BOT_CODE_END===',
        ).firstMatch(response);

        if (codeMatch != null) {
          _generatedBotCode = codeMatch.group(1)!.trim();

          final beforeCode =
              response.split('===BOT_CODE_START===').first.trim();
          final afterCode =
              response.split('===BOT_CODE_END===').last.trim();

          displayText = [
            if (beforeCode.isNotEmpty) beforeCode,
            '✅ Bot code generated! Ready to deploy to the server.',
            if (afterCode.isNotEmpty) afterCode,
          ].join('\n\n');
        }
      }

      setState(() {
        _messages.add(ChatMessage.assistant(displayText));
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _messages.add(
            ChatMessage.assistant('⚠️ Error: ${e.toString()}'));
      });
    }
  }

  // ─── Server bot lifecycle ────────────────────────────────────────────────────

  Future<void> _deployBot() async {
    if (_generatedBotCode == null) return;

    setState(() {
      _botState = const BotState(status: BotRunStatus.starting);
      _messages.add(ChatMessage.status('🚀 Uploading bot to server…'));
    });
    _scrollToBottom();

    try {
      // 1. Create bot on server
      final botId = await BotServerService.createBot(
        code: _generatedBotCode!,
      );

      setState(() {
        _botState = _botState.copyWith(botId: botId);
        _messages.add(ChatMessage.status(
            '📦 Bot created on server (id: $botId). Starting…'));
      });

      // 2. Run bot
      final status = await BotServerService.runBot(botId);
      setState(() {
        _botState = _botState.copyWith(status: status);
        _messages.add(ChatMessage.status(
            status == BotRunStatus.running
                ? '🟢 Bot is now running on the server!'
                : '⏳ Bot is starting up…'));
      });
      _scrollToBottom();

      // 3. Poll until running or error
      _pollSub = BotServerService.pollStatus(
        botId,
        until: (s) =>
            s.status == BotRunStatus.running ||
            s.status == BotRunStatus.error ||
            s.status == BotRunStatus.stopped,
      ).listen(
        (s) {
          if (!mounted) return;
          setState(() => _botState = s);
          if (s.status == BotRunStatus.error) {
            setState(() {
              _messages.add(ChatMessage.status(
                  '❌ Server error: ${s.errorMessage ?? "unknown"}'));
            });
            _scrollToBottom();
          }
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _botState = _botState.copyWith(
              status: BotRunStatus.error,
              errorMessage: e.toString(),
            );
            _messages.add(
                ChatMessage.status('❌ Polling error: ${e.toString()}'));
          });
          _scrollToBottom();
        },
      );
    } on BotServerException catch (e) {
      setState(() {
        _botState = const BotState(status: BotRunStatus.error);
        _messages.add(ChatMessage.status('❌ Deploy failed: ${e.message}'));
      });
      _scrollToBottom();
      _showSnackbar('Deploy failed: ${e.message}', isError: true);
    }
  }

  Future<void> _stopBot() async {
    final botId = _botState.botId;
    if (botId == null) return;

    _pollSub?.cancel();

    setState(() {
      _messages.add(ChatMessage.status('🛑 Stopping bot on server…'));
    });

    try {
      final status = await BotServerService.stopBot(botId);
      setState(() {
        _botState = _botState.copyWith(status: status);
        _messages.add(ChatMessage.status('⏹ Bot stopped.'));
      });
    } on BotServerException catch (e) {
      setState(() {
        _messages
            .add(ChatMessage.status('⚠️ Stop failed: ${e.message}'));
      });
    }
    _scrollToBottom();
  }

  Future<void> _fetchLogs() async {
    final botId = _botState.botId;
    if (botId == null) return;

    try {
      final logs = await BotServerService.getBotLogs(botId);
      if (!mounted) return;
      setState(() {
        _botState = _botState.copyWith(logs: logs);
      });
      _showLogsSheet(logs);
    } on BotServerException catch (e) {
      _showSnackbar('Failed to fetch logs: ${e.message}', isError: true);
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSnackbar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_generatedBotCode != null) _buildBotControlPanel(),
            Expanded(child: _buildChatList()),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    // Show a personality badge when a diagnosis session is available
    final hasSession = DiagnosisStore.hasSession;
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Telegram Bot Builder',
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (hasSession)
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.diagnosisGold,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Personality context active',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.diagnosisGold,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
        ],
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  // ─── Bot control panel ───────────────────────────────────────────────────────

  Widget _buildBotControlPanel() {
    final status = _botState.status;
    final botId = _botState.botId;
    final isRunning = status == BotRunStatus.running;
    final isStarting = status == BotRunStatus.starting;
    final canDeploy = !isRunning && !isStarting;

    final statusLabel = switch (status) {
      BotRunStatus.idle => 'Ready to deploy',
      BotRunStatus.starting => 'Starting…',
      BotRunStatus.running => 'Running',
      BotRunStatus.error => 'Error',
      BotRunStatus.stopped => 'Stopped',
    };
    final statusType = switch (status) {
      BotRunStatus.running => StatusType.running,
      BotRunStatus.starting => StatusType.starting,
      BotRunStatus.error => StatusType.error,
      BotRunStatus.stopped => StatusType.stopped,
      BotRunStatus.idle => StatusType.stopped,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              StatusBadge(label: statusLabel, type: statusType),
              const Spacer(),
              if (botId != null)
                Text(
                  'ID: ${botId.length > 10 ? botId.substring(0, 10) : botId}…',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'View Code',
                  icon: Icons.code_rounded,
                  color: AppColors.primaryLight,
                  onTap: _showCodeSheet,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: canDeploy ? 'Deploy Bot' : 'Running',
                  icon: Icons.cloud_upload_rounded,
                  color: AppColors.success,
                  onTap: canDeploy ? _deployBot : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: 'Stop',
                  icon: Icons.stop_circle_rounded,
                  color: AppColors.error,
                  onTap: (isRunning || isStarting) ? _stopBot : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: 'Logs',
                  icon: Icons.receipt_long_rounded,
                  color: AppColors.cyan,
                  onTap: botId != null ? _fetchLogs : null,
                ),
              ),
            ],
          ),
          // Server notice
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 13, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Bot runs on your server — not on this device.',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCodeSheet() {
    if (_generatedBotCode == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'telegram_bot.py',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: CodeCard(
                  code: _generatedBotCode ?? '',
                  filename: 'telegram_bot.py',
                  onCopy: () {
                    Clipboard.setData(
                        ClipboardData(text: _generatedBotCode ?? ''));
                    Navigator.pop(context);
                    _showSnackbar('Code copied!');
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogsSheet(List<BotLogEntry> logs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Bot Logs',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        'No logs yet.',
                        style: GoogleFonts.inter(
                            color: AppColors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: logs.length,
                      itemBuilder: (_, i) {
                        final log = logs[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 3),
                          child: Text(
                            '${_formatTime(log.timestamp)}  ${log.message}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              color: log.isError
                                  ? AppColors.error
                                  : AppColors.textSecondary,
                              height: 1.5,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Widget _buildChatList() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _messages.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: ChatBubble(
                content: '', isUser: false, isLoading: true),
          );
        }
        final msg = _messages[i];
        if (msg.isStatus) return _StatusLine(text: msg.content);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: ChatBubble(
              content: msg.content, isUser: msg.isUser),
        );
      },
    );
  }

  Widget _buildInputBar() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: bottomPadding > 0 ? bottomPadding : 14,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              style: GoogleFonts.inter(
                  fontSize: 14.5, color: AppColors.textPrimary),
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: const InputDecoration(
                hintText: 'Describe your bot idea…',
                hintStyle: TextStyle(color: AppColors.textMuted),
                contentPadding: EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _sendMessage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.telegramBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withAlpha(102),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Status Line ──────────────────────────────────────────────────────────────

class _StatusLine extends StatelessWidget {
  final String text;
  const _StatusLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            text,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Action Button ────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: color.withAlpha(31),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withAlpha(77)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 3),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}