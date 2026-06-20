import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/chat_models.dart';
import '../../theme/app_theme.dart';

class ChatHistorySidebar extends StatelessWidget {
  final List<ChatSummary> chats;
  final String? activeChatId;
  final bool isLoading;
  final VoidCallback onNewChat;
  final Future<void> Function(ChatSummary) onSelectChat;
  final Future<void> Function(ChatSummary, String) onRenameChat;
  final Future<void> Function(ChatSummary) onDeleteChat;

  const ChatHistorySidebar({
    super.key,
    required this.chats,
    required this.activeChatId,
    required this.isLoading,
    required this.onNewChat,
    required this.onSelectChat,
    required this.onRenameChat,
    required this.onDeleteChat,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.sidebar,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Chats',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'New chat',
                    icon: const Icon(Icons.add_rounded,
                        color: AppColors.textSecondary),
                    onPressed: () {
                      Navigator.pop(context);
                      onNewChat();
                    },
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            // Body
            Expanded(
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2),
                    )
                  : chats.isEmpty
                      ? Center(
                          child: Text(
                            'No chats yet',
                            style: GoogleFonts.inter(
                                color: AppColors.textMuted, fontSize: 14),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: chats.length,
                          itemBuilder: (context, i) =>
                              _ChatTile(
                            chat: chats[i],
                            isActive: chats[i].id == activeChatId,
                            onTap: () {
                              Navigator.pop(context);
                              onSelectChat(chats[i]);
                            },
                            onRename: (newTitle) =>
                                onRenameChat(chats[i], newTitle),
                            onDelete: () => onDeleteChat(chats[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final ChatSummary chat;
  final bool isActive;
  final VoidCallback onTap;
  final Future<void> Function(String) onRename;
  final VoidCallback onDelete;

  const _ChatTile({
    required this.chat,
    required this.isActive,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  void _showRenameDialog(BuildContext context) {
    final ctrl = TextEditingController(text: chat.title);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Rename chat',
          style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.inter(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Chat title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final newTitle = ctrl.text.trim();
              if (newTitle.isNotEmpty) {
                onRename(newTitle);
              }
              Navigator.pop(context);
            },
            child: Text('Rename',
                style: GoogleFonts.inter(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: isActive,
      selectedTileColor: AppColors.primary.withAlpha(26),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Text(
        chat.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          color:
              isActive ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
      subtitle: chat.lastMessage != null
          ? Text(
              chat.lastMessage!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textMuted),
            )
          : null,
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded,
            size: 18, color: AppColors.textMuted),
        color: AppColors.surfaceElevated,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'rename',
            child: Row(
              children: [
                const Icon(Icons.edit_rounded,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text('Rename',
                    style: GoogleFonts.inter(
                        color: AppColors.textPrimary)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete_outline_rounded,
                    size: 16, color: AppColors.error),
                const SizedBox(width: 8),
                Text('Delete',
                    style: GoogleFonts.inter(color: AppColors.error)),
              ],
            ),
          ),
        ],
        onSelected: (value) {
          if (value == 'rename') _showRenameDialog(context);
          if (value == 'delete') onDelete();
        },
      ),
    );
  }
}