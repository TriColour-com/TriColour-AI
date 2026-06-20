import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import 'telegram_bot_screen.dart';

class DiagnosisResultScreen extends StatefulWidget {
  final String result;

  const DiagnosisResultScreen({super.key, required this.result});

  @override
  State<DiagnosisResultScreen> createState() =>
      _DiagnosisResultScreenState();
}

class _DiagnosisResultScreenState extends State<DiagnosisResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  String? _archetypeName;
  List<_ResultSection> _sections = [];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim =
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
    _parseResult();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _parseResult() {
    final text = widget.result;

    // Extract archetype name from header
    final archetypeMatch = RegExp(
      r'Character Profile:\s*(.+)',
      caseSensitive: false,
    ).firstMatch(text);
    _archetypeName = archetypeMatch?.group(1)?.trim() ?? 'Your Profile';

    // Parse sections by ** headers **
    final sectionPattern =
        RegExp(r'\*\*(.+?)\*\*\n([\s\S]*?)(?=\n\*\*|\n?$)');
    final matches = sectionPattern.allMatches(text);

    _sections = matches
        .where((m) => !m.group(1)!.contains('Character Profile'))
        .map((m) => _ResultSection(
              title: m.group(1)!.trim(),
              content: m.group(2)!.trim(),
            ))
        .toList();

    if (_sections.isEmpty) {
      _sections = [
        _ResultSection(title: 'Your Analysis', content: text)
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: CustomScrollView(
            slivers: [
              _buildHeroSliver(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ..._sections.map(_buildSection),
                      const SizedBox(height: 24),
                      _buildActions(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSliver() {
    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF1C1208),
              Color(0xFF2D1B00),
              AppColors.background,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back button → home
                GestureDetector(
                  onTap: () =>
                      Navigator.popUntil(context, (r) => r.isFirst),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(20),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.home_rounded,
                            size: 16, color: Colors.white70),
                        const SizedBox(width: 6),
                        Text(
                          'Home',
                          style: GoogleFonts.inter(
                              fontSize: 13, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Result badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.diagnosisGold.withAlpha(51),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.diagnosisGold.withAlpha(102)),
                  ),
                  child: Text(
                    '✨  Diagnosis Complete',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.diagnosisGold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _archetypeName ?? 'Your Profile',
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Based on your 10 answers',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(_ResultSection section) {
    final isTraits = section.title.toLowerCase().contains('trait') ||
        section.title.toLowerCase().contains('core');
    final isSuperpower =
        section.title.toLowerCase().contains('superpower');
    final isConclusion =
        section.title.toLowerCase().contains('bottom line') ||
            section.title.toLowerCase().contains('conclusion');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: isConclusion
              ? AppColors.diagnosisGold.withAlpha(20)
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isConclusion
                ? AppColors.diagnosisGold.withAlpha(77)
                : isSuperpower
                    ? AppColors.success.withAlpha(77)
                    : AppColors.border,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _sectionEmoji(section.title),
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      section.title,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isConclusion
                            ? AppColors.diagnosisGold
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildSectionContent(section.content, isTraits),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionContent(String content, bool isTraits) {
    final lines = content.split('\n');
    final hasBullets = lines.any((l) =>
        l.trimLeft().startsWith('•') ||
        (l.trimLeft().startsWith('-') && l.trim().length > 2));

    if (hasBullets && isTraits) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines.map((line) {
          final isBullet = line.trimLeft().startsWith('•') ||
              line.trimLeft().startsWith('-');
          if (isBullet) {
            final text =
                line.replaceFirst(RegExp(r'^[\s•\-]+'), '');
            final colonIdx = text.indexOf(':');
            if (colonIdx > 0) {
              final trait = text.substring(0, colonIdx).trim();
              final desc = text.substring(colonIdx + 1).trim();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin:
                          const EdgeInsets.only(top: 6, right: 10),
                      decoration: BoxDecoration(
                        color: AppColors.diagnosisGold,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '$trait: ',
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            TextSpan(
                              text: desc,
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                color: AppColors.textSecondary,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin:
                        const EdgeInsets.only(top: 6, right: 10),
                    decoration: const BoxDecoration(
                      color: AppColors.diagnosisGold,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      text,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          if (line.trim().isEmpty) return const SizedBox(height: 4);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              line,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                color: AppColors.textSecondary,
                height: 1.55,
              ),
            ),
          );
        }).toList(),
      );
    }

    return Text(
      content,
      style: GoogleFonts.inter(
        fontSize: 14,
        color: AppColors.textSecondary,
        height: 1.65,
      ),
    );
  }

  String _sectionEmoji(String title) {
    final t = title.toLowerCase();
    if (t.contains('overview') || t.contains('personality')) return '🧬';
    if (t.contains('trait') || t.contains('core')) return '✦';
    if (t.contains('think') || t.contains('decide')) return '🧠';
    if (t.contains('connect') || t.contains('social')) return '🤝';
    if (t.contains('superpower') || t.contains('strength')) return '⚡';
    if (t.contains('growth') || t.contains('edge')) return '🌱';
    if (t.contains('bottom') || t.contains('conclusion')) return '🎯';
    return '◆';
  }

  Widget _buildActions() {
    final hasSession = DiagnosisStore.hasSession;
    return Column(
      children: [
        const GlowDivider(color: AppColors.diagnosisGold),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _ResultAction(
                label: 'Copy Profile',
                icon: Icons.copy_rounded,
                color: AppColors.primary,
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: widget.result));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Profile copied to clipboard'),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ResultAction(
                label: 'Start Over',
                icon: Icons.refresh_rounded,
                color: AppColors.diagnosisGold,
                onTap: () =>
                    Navigator.popUntil(context, (r) => r.isFirst),
              ),
            ),
          ],
        ),
        if (hasSession) ...[
          const SizedBox(height: 12),
          // ── Create personalised Telegram bot with this profile ──────────────
          GestureDetector(
            onTap: () {
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, anim, __) =>
                      const TelegramBotScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                        parent: anim, curve: Curves.easeOutCubic)),
                    child: child,
                  ),
                  transitionDuration: const Duration(milliseconds: 320),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1565C0), AppColors.telegramBlue],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.telegramBlue.withAlpha(77),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'Create Bot Using My Profile',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'The bot builder will use your personality context',
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textMuted),
            ),
          ),
        ],
      ],
    );
  }
}

class _ResultSection {
  final String title;
  final String content;
  _ResultSection({required this.title, required this.content});
}

class _ResultAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ResultAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withAlpha(26),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(77)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}