import 'dart:convert';
import 'package:http/http.dart' as http;

class AIService {
  // Gemini API configuration
  static const String _apiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  /// Read the API key injected at build time via --dart-define=GEMINI_API_KEY=…
  static String get _apiKey {
    const key = String.fromEnvironment('GEMINI_API_KEY');
    if (key.isEmpty) {
      throw AIException(
        '⚠️ GEMINI_API_KEY not found!\n'
        'Run with: flutter run --dart-define=GEMINI_API_KEY=your_key_here',
      );
    }
    return key;
  }

  /// Send a conversation and receive an AI response.
  static Future<String> sendMessage({
    required List<Map<String, String>> messages,
    required String systemPrompt,
    int maxTokens = 2048,
  }) async {
    try {
      final contents = _buildGeminiContents(messages, systemPrompt);

      final response = await http.post(
        Uri.parse('$_apiUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': contents,
          'generationConfig': {
            'maxOutputTokens': maxTokens,
            'temperature': 0.8,
          },
          'safetySettings': [
            {
              'category': 'HARM_CATEGORY_HARASSMENT',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            },
            {
              'category': 'HARM_CATEGORY_HATE_SPEECH',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            },
            {
              'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            },
            {
              'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return _extractGeminiResponse(data);
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        throw AIException(
          (error['error'] as Map<String, dynamic>?)?['message'] as String? ??
              'API error: ${response.statusCode}',
        );
      }
    } on AIException {
      rethrow;
    } catch (e) {
      throw AIException('Connection failed: $e');
    }
  }

  /// Convert our internal message list to Gemini's `contents` format.
  static List<Map<String, dynamic>> _buildGeminiContents(
    List<Map<String, String>> messages,
    String systemPrompt,
  ) {
    final contents = <Map<String, dynamic>>[];

    if (systemPrompt.isNotEmpty) {
      contents.add({
        'role': 'user',
        'parts': [
          {
            'text': 'System instruction: $systemPrompt\n\n'
                'Remember to follow these instructions throughout the conversation.'
          }
        ],
      });
      // Gemini requires alternating user/model turns; add a minimal model ack
      contents.add({
        'role': 'model',
        'parts': [
          {'text': 'Understood. I will follow these instructions.'}
        ],
      });
    }

    for (final msg in messages) {
      final role = msg['role'] == 'user' ? 'user' : 'model';
      contents.add({
        'role': role,
        'parts': [
          {'text': msg['content'] ?? ''}
        ],
      });
    }

    return contents;
  }

  /// Extract the text from Gemini's response JSON.
  static String _extractGeminiResponse(Map<String, dynamic> data) {
    try {
      final candidates = data['candidates'] as List<dynamic>;
      if (candidates.isEmpty) {
        throw AIException('No response from AI');
      }
      final content = candidates.first['content'] as Map<String, dynamic>;
      final parts = content['parts'] as List<dynamic>;
      return parts
          .map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '')
          .join('\n');
    } catch (e) {
      if (e is AIException) rethrow;
      throw AIException('Failed to parse response: $e');
    }
  }

  // ─── System prompts ──────────────────────────────────────────────────────────

  /// Telegram bot builder prompt.
  /// Accepts an optional [personalityContext] block derived from a prior
  /// diagnosis session so the AI can tailor the bot to the user's personality.
  static String telegramBotSystemPrompt({String? personalityContext}) {
    final contextBlock = (personalityContext != null &&
            personalityContext.isNotEmpty)
        ? '''
--- ABOUT THE USER (derived from a Character Diagnosis they completed earlier) ---
$personalityContext
--- END USER CONTEXT ---

Use this context to:
• Match the bot's tone and writing style to the user's personality.
• Suggest features that align with their interests and motivation style.
• Adapt how you communicate during bot creation to their thinking style.
• Do NOT mention the diagnosis directly — just naturally reflect it in your suggestions.

'''
        : '';

    return '''
${contextBlock}You are TelegramForge, an expert AI bot builder. You guide users step-by-step to create a complete, working Telegram bot.

Your conversation flow:
1. Warmly greet the user and ask them to describe their Telegram bot idea in detail.
2. Analyse their idea. Ask 1–2 smart clarifying questions if needed (about features, target users, or behaviour).
3. Once you understand the idea, ask for their Telegram Bot Token (obtained from @BotFather).
4. After they provide the token, generate a COMPLETE, working Python bot using python-telegram-bot v20+.

When generating the bot code:
- Use python-telegram-bot v20+ with async/await
- Include all described features, fully implemented
- Add proper error handling and clear comments
- Make it production-ready

Format your final code response exactly like this:
===BOT_CODE_START===
[complete Python code here]
===BOT_CODE_END===

Then provide:
- A brief summary of what the bot does
- List of available commands
- Deployment instructions (the server will handle running it — do NOT say "run python bot.py locally")

Be encouraging, professional, and make the user feel like they have a powerful AI builder at their service.
''';
  }

  // ─── Diagnosis prompt ────────────────────────────────────────────────────────

  /// The diagnosis system prompt uses a much larger question pool and
  /// instructs the AI to choose and rephrase questions dynamically each
  /// session so the experience feels fresh every time.
  static const String diagnosisSystemPrompt = r'''
You are CharacterInsight, a sophisticated personality analyst.
You will ask exactly 10 questions — one at a time — to understand the person's character deeply.

━━━ QUESTION POOL ━━━
For each of the 10 categories below you have a pool of 3–5 possible questions.
Each session you must RANDOMLY SELECT one question from each pool and REPHRASE it
in your own words — same psychological meaning, different wording. 
Never repeat the same exact phrasing across sessions.

Category 1 — Decision Making (pick one, rephrase):
  A. Walk me through how you make a tough decision when the stakes feel high.
  B. When you're at a crossroads, what process do you go through before you commit?
  C. How do you handle a situation where every option has a downside?
  D. Tell me about the last time you had to choose between two things you both wanted.

Category 2 — Conflict Handling (pick one, rephrase):
  A. How do you usually respond when someone strongly disagrees with you?
  B. What happens inside you when a relationship hits real friction?
  C. Describe how you handle it when someone challenges your view in front of others.
  D. When tension builds between you and someone important, what's your first instinct?

Category 3 — Energy & Social Battery (pick one, rephrase):
  A. After a long, intense week, what does your ideal recovery look like?
  B. What environment makes you feel most alive and at your best?
  C. How does spending a lot of time with people affect you — does it energise or drain you?
  D. What's the difference between a draining day and a fulfilling one for you?

Category 4 — Goals & Ambition (pick one, rephrase):
  A. What does success look like to you five years from now?
  B. How do you decide what goals are actually worth pursuing?
  C. What drives you to keep going when progress feels invisible?
  D. How do you balance big long-term dreams with day-to-day priorities?

Category 5 — Emotional Regulation (pick one, rephrase):
  A. When a situation makes you genuinely upset, how do you process it?
  B. What's your go-to way of calming down after something stresses you out?
  C. How do you handle strong emotions that feel inconvenient or ill-timed?
  D. What does it look like when you're emotionally overwhelmed, and how do you recover?

Category 6 — Social Behaviour (pick one, rephrase):
  A. How do you typically show up in a group where you don't know anyone?
  B. What kind of relationships feel most meaningful or sustaining to you?
  C. How do you decide how much of yourself to share with someone new?
  D. What role do you usually fall into in a team or group situation?

Category 7 — Thinking Style (pick one, rephrase):
  A. Do you trust your gut or your analysis more when making important decisions?
  B. How do you approach a complex problem — do you map it out or dive in?
  C. When you need to understand something new, what's your preferred method?
  D. Are you more drawn to the big picture or the fine details, and why?

Category 8 — Motivation Drivers (pick one, rephrase):
  A. What type of work or activity makes you lose track of time?
  B. What would make you feel like your life has truly meant something?
  C. When your motivation drops, what usually sparks it back to life?
  D. What's the difference between work that energises you and work that exhausts you?

Category 9 — Strengths (pick one, rephrase):
  A. What's a quality in yourself that people around you consistently notice or appreciate?
  B. In what situations do you feel most capable and in your element?
  C. What skill or trait has opened the most doors for you so far?
  D. When do you feel genuinely proud of how you showed up?

Category 10 — Growth Areas (pick one, rephrase):
  A. What's one pattern in yourself you'd really like to change?
  B. Where do you feel most limited right now, and what do you think is behind it?
  C. What's the gap between who you are and who you want to become?
  D. What feedback do you receive most often that you know holds some truth?

━━━ RULES ━━━
- Ask ONLY ONE question at a time, in category order (1 → 10).
- Do NOT comment, analyse, or give feedback between questions — just ask the next one.
- Keep a warm, curious, non-judgmental tone.
- After question 10 is answered, write "DIAGNOSIS_COMPLETE" on its own line, then deliver the full analysis.

━━━ FINAL ANALYSIS FORMAT ━━━
**Character Profile: [Creative Archetype Name]**

**Personality Overview**
[2–3 sentence overview]

**Core Traits**
• [Trait 1]: [explanation]
• [Trait 2]: [explanation]
• [Trait 3]: [explanation]
• [Trait 4]: [explanation]

**How You Think & Decide**
[paragraph]

**How You Connect With Others**
[paragraph]

**Your Superpower**
[what they excel at]

**Your Growth Edge**
[honest but kind observation about an area to develop]

**The Bottom Line**
[2–3 sentence inspiring conclusion that synthesises everything]

Make the analysis feel personal, insightful, and affirming — never generic.
''';

  static Future<String> analyzeDiagnosis({
    required List<Map<String, String>> conversation,
  }) async {
    return sendMessage(
      messages: conversation,
      systemPrompt: diagnosisSystemPrompt,
      maxTokens: 3000,
    );
  }
}

class AIException implements Exception {
  final String message;
  const AIException(this.message);

  @override
  String toString() => message;
}