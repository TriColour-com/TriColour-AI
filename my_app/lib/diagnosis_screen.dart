import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/chat_bubble.dart';
import 'diagnosis_result_screen.dart';

enum DiagnosisPhase { intro, questioning, analyzing, done }

class DiagnosisScreen extends StatefulWidget {
  const DiagnosisScreen({super.key});

  @override
  State<DiagnosisScreen> createState() => _DiagnosisScreenState();
}

class _DiagnosisScreenState extends State<DiagnosisScreen>
    with SingleTickerProviderStateMixin {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  DiagnosisPhase _phase = DiagnosisPhase.intro;
  bool _isLoading = false;
  int _currentQuestion = 0;
  static const int _totalQuestions = 10;

  late AnimationController _introAnim;
  late Animation<double> _fadeAnim;

  final List<String> _questionCategories = [
    'Decision Making',
    'Conflict',
    'Energy',
    'Goals',
    'Emotions',
    'Social',
    'Thinking',
    'Motivation',
    'Strengths',
    'Growth',
  ];

  @override
  void initState() {
    super.initState();
    _introAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _introAnim, curve: Curves.easeOut);
    _introAnim.forward();
  }

  @override
  void dispose() {
    _introAnim.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _startDiagnosis() {
    setState(() => _phase = DiagnosisPhase.questioning);
    _askFirstQuestion();
  }

  Future<void> _askFirstQuestion() async {
    setState(() => _isLoading = true);
    try {
      final response = await AIService.sendMessage(
        messages: [
          {
            'role': 'user',
            'content':
                'Start the character diagnosis. Ask me question 1 of 10. '
                'Pick and rephrase a question from Category 1 (Decision Making).',
          }
        ],
        systemPrompt: AIService.diagnosisSystemPrompt,
      );
      setState(() {
        _messages.add(ChatMessage.assistant(response));
        _currentQuestion = 1;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _messages.add(ChatMessage.assistant(
            '⚠️ Connection error. Please check your API key.'));
      });
    }
  }

  Future<void> _sendAnswer() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isLoading) return;

    HapticFeedback.selectionClick();
    _inputCtrl.clear();

    final userMsg = ChatMessage.user(text);
    setState(() {
      _messages.add(userMsg);
      _isLoading = true;
    });
    _scrollToBottom();

    final history = _messages.map((m) => m.toApiFormat()).toList();

    try {
      final response = await AIService.sendMessage(
        messages: history,
        systemPrompt: AIService.diagnosisSystemPrompt,
        maxTokens: 3000,
      );

      if (response.contains('DIAGNOSIS_COMPLETE')) {
        final cleanResponse =
            response.replaceAll('DIAGNOSIS_COMPLETE', '').trim();

        // ── Save session so the bot builder can use it later ──────────────────
        final session = DiagnosisSession(
          conversationHistory: history,
          analysisResult: cleanResponse,
        );
        DiagnosisStore.save(session);
        // ─────────────────────────────────────────────────────────────────────

        setState(() {
          _messages.add(ChatMessage.assistant(cleanResponse));
          _phase = DiagnosisPhase.done;
          _isLoading = false;
        });
        _scrollToBottom();

        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          _navigateToResult(cleanResponse);
        }
      } else {
        setState(() {
          _messages.add(ChatMessage.assistant(response));
          _isLoading = false;
          if (_currentQuestion < _totalQuestions) {
            _currentQuestion++;
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _messages.add(
            ChatMessage.assistant('⚠️ Error: ${e.toString()}'));
      });
    }
  }

  void _navigateToResult(String result) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) =>
            DiagnosisResultScreen(result: result),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

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

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // resizeToAvoidBottomInset=true (default): body shrinks when keyboard
      // opens. The input bar only adds the physical safe-area inset, NOT
      // viewInsets, to avoid a double-shift.
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      body: SafeArea(
        // bottom: false — we handle the home-bar inset manually in _buildInputBar
        bottom: false,
        child: _phase == DiagnosisPhase.intro
            ? _buildIntroScreen()
            : Column(
                children: [
                  if (_phase == DiagnosisPhase.questioning)
                    _buildProgressBar(),
                  Expanded(child: _buildChatList()),
                  if (_phase == DiagnosisPhase.questioning)
                    _buildInputBar(),
                  if (_phase == DiagnosisPhase.analyzing)
                    _buildAnalyzingIndicator(),
                ],
              ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Character Diagnosis',
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (_phase == DiagnosisPhase.questioning)
            Text(
              'Question $_currentQuestion of $_totalQuestions',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.diagnosisGold,
              ),
            ),
        ],
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        onPressed: () {
          if (_phase != DiagnosisPhase.intro) {
            _showExitDialog();
          } else {
            Navigator.pop(context);
          }
        },
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProgressSteps(
              total: _totalQuestions, current: _currentQuestion),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _currentQuestion > 0 &&
                        _currentQuestion <= _questionCategories.length
                    ? _questionCategories[_currentQuestion - 1]
                    : '',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.diagnosisGold,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${(_currentQuestion / _totalQuestions * 100).round()}%',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIntroScreen() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF78350F), AppColors.diagnosisGold],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.diagnosisGold.withAlpha(77),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.psychology_rounded,
                  color: Colors.white, size: 32),
            ),
            const SizedBox(height: 22),
            Text(
              'Character Diagnosis',
              style: GoogleFonts.inter(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '10 thoughtful questions. A deep personality analysis. '
              'Each session uses different question phrasings so '
              'every run feels fresh.',
              style: GoogleFonts.inter(
                fontSize: 15,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            const GlowDivider(color: AppColors.diagnosisGold),
            const SizedBox(height: 24),
            Text(
              'What we explore',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 14),
            _buildTraitGrid(),
            const SizedBox(height: 32),
            // Start button
            GestureDetector(
              onTap: _startDiagnosis,
              child: Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF78350F), AppColors.diagnosisGold],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.diagnosisGold.withAlpha(77),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Start Diagnosis',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Takes about 5 minutes',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTraitGrid() {
    final traits = [
      ('🧠', 'Thinking style'),
      ('❤️', 'Emotional control'),
      ('🎯', 'Goals & Drive'),
      ('🤝', 'Social behavior'),
      ('⚡', 'Decision making'),
      ('💪', 'Strengths'),
      ('🌱', 'Growth areas'),
      ('🔮', 'Core personality'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 3.2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: traits.length,
      itemBuilder: (_, i) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Text(traits[i].$1, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                traits[i].$2,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
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
            child:
                ChatBubble(content: '', isUser: false, isLoading: true),
          );
        }
        final msg = _messages[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: ChatBubble(content: msg.content, isUser: msg.isUser),
        );
      },
    );
  }

  Widget _buildInputBar() {
    // Only use physical safe-area bottom (home bar / notch).
    // resizeToAvoidBottomInset=true already moved the Scaffold body up.
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
              onSubmitted: (_) => _sendAnswer(),
              decoration: const InputDecoration(
                hintText: 'Type your answer…',
                hintStyle: TextStyle(color: AppColors.textMuted),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _sendAnswer,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF78350F), AppColors.diagnosisGold],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.diagnosisGold.withAlpha(77),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.arrow_upward_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzingIndicator() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              color: AppColors.diagnosisGold,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Analyzing your answers…',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Exit diagnosis?',
          style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
        content: Text(
          'Your progress will be lost. Are you sure?',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Continue',
                style: GoogleFonts.inter(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: Text('Exit',
                style: GoogleFonts.inter(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}