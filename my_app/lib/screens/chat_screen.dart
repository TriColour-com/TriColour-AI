import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_history_sidebar.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<ChatSummary> _chats = [];
  List<BackendChatMessage> _messages = [];
  ChatSummary? _activeChat;

  bool _isLoadingChats = true;
  bool _isLoadingMessages = false;
  bool _isSending = false;
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─── Bootstrap ──────────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    await _refreshChats();
    if (_activeChat == null && _chats.isNotEmpty) {
      await _openChat(_chats.first);
    } else if (_chats.isEmpty && _connectionError == null) {
      await _createAndOpenNewChat();
    }
  }

  Future<void> _refreshChats() async {
    setState(() {
      _isLoadingChats = true;
      _connectionError = null;
    });
    try {
      final chats = await _api.listChats();
      setState(() {
        _chats = chats;
        _isLoadingChats = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingChats = false;
        _connectionError = e.toString();
      });
    }
  }

  // ─── Chat selection / creation ──────────────────────────────────────────

  Future<void> _openChat(ChatSummary chat) async {
    setState(() {
      _activeChat = chat;
      _isLoadingMessages = true;
      _messages = [];
    });
    try {
      final messages = await _api.getChatMessages(chat.id);
      setState(() {
        _messages = messages;
        _isLoadingMessages = false;
      });
      _scrollToBottomNextFrame();
    } catch (e) {
      setState(() => _isLoadingMessages = false);
      _showSnack('Failed to load chat: $e', isError: true);
    }
  }

  Future<void> _createAndOpenNewChat() async {
    try {
      final chat = await _api.createChat();
      setState(() {
        _chats = [chat, ..._chats];
        _activeChat = chat;
        _messages = [];
      });
    } catch (e) {
      _showSnack('Failed to create chat: $e', isError: true);
    }
  }

  Future<void> _renameChat(ChatSummary chat, String newTitle) async {
    try {
      final updated = await _api.renameChat(chat.id, newTitle);
      setState(() {
        _chats = _chats.map((c) => c.id == updated.id ? updated : c).toList();
        if (_activeChat?.id == updated.id) _activeChat = updated;
      });
    } catch (e) {
      _showSnack('Failed to rename chat: $e', isError: true);
    }
  }

  Future<void> _deleteChat(ChatSummary chat) async {
    try {
      await _api.deleteChat(chat.id);
      setState(() {
        _chats = _chats.where((c) => c.id != chat.id).toList();
        if (_activeChat?.id == chat.id) {
          _activeChat = null;
          _messages = [];
        }
      });
      if (_activeChat == null) {
        if (_chats.isNotEmpty) {
          await _openChat(_chats.first);
        } else {
          await _createAndOpenNewChat();
        }
      }
    } catch (e) {
      _showSnack('Failed to delete chat: $e', isError: true);
    }
  }

  // ─── Sending messages ───────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isSending) return;

    ChatSummary activeChat;
    if (_activeChat != null) {
      activeChat = _activeChat!;
    } else {
      try {
        final newChat = await _api.createChat();
        setState(() {
          _chats = [newChat, ..._chats];
          _activeChat = newChat;
        });
        activeChat = newChat;
      } catch (e) {
        _showSnack('Failed to create chat: $e', isError: true);
        return;
      }
    }

    _inputCtrl.clear();
    // FIXED: Use BackendChatMessage.local and BackendMessageRole
    final optimisticUserMsg = BackendChatMessage.local(
      chatId: activeChat.id,
      role: BackendMessageRole.user,
      content: text,
    );

    setState(() {
      _messages = [..._messages, optimisticUserMsg];
      _isSending = true;
    });
    _scrollToBottomNextFrame();

    try {
      final reply =
          await _api.sendMessage(chatId: activeChat.id, message: text);

      final assistantMsg = BackendChatMessage.local(
        chatId: activeChat.id,
        role: BackendMessageRole.assistant,
        content: reply,
      );

      setState(() {
        _messages = [..._messages, assistantMsg];
        _isSending = false;
      });
      _scrollToBottomNextFrame();

      // Refresh chat list in background so titles/previews stay in sync
      _refreshChats();
    } catch (e) {
      setState(() => _isSending = false);
      _showSnack('Failed to get a reply: $e', isError: true);
    }
  }

  // ─── UI helpers ─────────────────────────────────────────────────────────

  void _scrollToBottomNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.surfaceElevated,
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: ChatHistorySidebar(
        chats: _chats,
        activeChatId: _activeChat?.id,
        isLoading: _isLoadingChats,
        onNewChat: _createAndOpenNewChat,
        onSelectChat: _openChat,
        onRenameChat: _renameChat,
        onDeleteChat: _deleteChat,
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _activeChat?.title ?? 'New chat',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              _isSending ? 'typing…' : 'online',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: _isSending ? AppColors.warning : AppColors.success,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _createAndOpenNewChat,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildBody()),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_connectionError != null) {
      return _buildConnectionError();
    }
    if (_isLoadingMessages) {
      return const Center(
        child: CircularProgressIndicator(
            color: AppColors.primary, strokeWidth: 2.5),
      );
    }
    if (_messages.isEmpty) {
      return _buildEmptyChat();
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      // FIXED: _isSending adds a TypingIndicator slot at end of list
      itemCount: _messages.length + (_isSending ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _messages.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 2),
            child: TypingIndicator(),
          );
        }
        final msg = _messages[i];
        // FIXED: ChatBubble no longer takes a timestamp parameter
        return ChatBubble(
          content: msg.content,
          isUser: msg.isUser,
        );
      },
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                size: 56, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'Say hello!',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your messages are sent to your local server,\nwhich talks to Gemini for you.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              "Can't reach the local server",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _connectionError ?? '',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check that the backend is running (npm start in /backend) '
              'and that ApiService.defaultBaseUrl matches how your device '
              'reaches it.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _bootstrap,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: bottomPadding > 0 ? bottomPadding : 12,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              style: GoogleFonts.inter(
                  fontSize: 15, color: AppColors.textPrimary),
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              enabled: _connectionError == null,
              onSubmitted: (_) => _sendMessage(),
              decoration: const InputDecoration(
                hintText: 'Message',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isSending ? null : _sendMessage,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _isSending
                    ? AppColors.textMuted
                    : AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}