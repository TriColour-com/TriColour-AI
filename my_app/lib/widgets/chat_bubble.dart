import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/app_theme.dart';

// ─── Chat Bubble ──────────────────────────────────────────────────────────────

class ChatBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final bool isLoading;

  const ChatBubble({
    super.key,
    required this.content,
    required this.isUser,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: EdgeInsets.only(
          top: 6,
          bottom: 6,
          left: isUser ? 48 : 0,
          right: isUser ? 0 : 48,
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser ? AppColors.userBubble : AppColors.aiBubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
        ),
        child: isLoading ? const LoadingDots() : _buildMarkdown(content),
      ),
    );
  }

  Widget _buildMarkdown(String text) {
    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: GoogleFonts.inter(
          fontSize: 14.5,
          height: 1.55,
          color: AppColors.textPrimary,
        ),
        strong: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        code: GoogleFonts.jetBrainsMono(fontSize: 13),
        codeblockDecoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      builders: {
        'code': CodeElementBuilder(),
      },
    );
  }
}

// ─── Markdown Code Block Builder ─────────────────────────────────────────────

class CodeElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(
      md.Element element, TextStyle? preferredStyle) {
    final language =
        element.attributes['class']?.replaceFirst('language-', '') ?? '';
    final code = element.textContent;

    if (language.isNotEmpty) {
      return HighlightView(
        code,
        language: language,
        theme: githubTheme,
        padding: const EdgeInsets.all(12),
        textStyle: GoogleFonts.jetBrainsMono(fontSize: 13),
      );
    }

    return Text(
      code,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 13,
        color: AppColors.textPrimary,
      ),
    );
  }
}

// ─── Loading Dots ─────────────────────────────────────────────────────────────

class LoadingDots extends StatefulWidget {
  const LoadingDots({super.key});

  @override
  State<LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final offset = i * 0.2;
            final raw = (_ctrl.value - offset) % 1.0;
            final opacity = raw < 0.5
                ? (raw * 2).clamp(0.2, 1.0)
                : ((1.0 - raw) * 2).clamp(0.2, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.textSecondary
                    .withAlpha((opacity * 255).round()),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

// ─── Typing Indicator ─────────────────────────────────────────────────────────
// FIXED: Added TypingIndicator widget that chat_screen.dart references

class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.aiBubble,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: const LoadingDots(),
      ),
    );
  }
}