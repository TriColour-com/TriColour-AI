const fetch = require('node-fetch');

const GEMINI_MODEL = process.env.GEMINI_MODEL || 'gemini-2.5-flash';
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;

const GEMINI_URL = (key) =>
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${key}`;

const DEFAULT_SYSTEM_PROMPT =
  'You are a friendly, helpful AI assistant inside a Telegram-style chat app. ' +
  'Keep replies clear and conversational. Use Markdown formatting (bold, lists, ' +
  'code blocks) where it improves readability.';

/**
 * Convert our internal {role, content} message list into Gemini's
 * `contents` array, with the system prompt injected as a leading
 * user/model exchange (Gemini's REST API has no first-class "system" role
 * for this model family, so we simulate one).
 */
function buildGeminiContents(messages, systemPrompt) {
  const contents = [];

  if (systemPrompt) {
    contents.push({
      role: 'user',
      parts: [
        {
          text: `System instruction: ${systemPrompt}\n\nFollow these instructions throughout the conversation.`,
        },
      ],
    });
    contents.push({
      role: 'model',
      parts: [{ text: 'Understood. I will follow these instructions.' }],
    });
  }

  for (const msg of messages) {
    const role = msg.role === 'user' ? 'user' : 'model';
    contents.push({
      role,
      parts: [{ text: msg.content || '' }],
    });
  }

  return contents;
}

function extractGeminiText(data) {
  const candidates = data.candidates;
  if (!candidates || candidates.length === 0) {
    // Could be blocked by safety settings, or an empty response.
    const blockReason = data.promptFeedback?.blockReason;
    if (blockReason) {
      throw new Error(`Gemini blocked the response (${blockReason}).`);
    }
    throw new Error('Gemini returned no candidates.');
  }
  const parts = candidates[0]?.content?.parts || [];
  return parts.map((p) => p.text || '').join('\n').trim();
}

/**
 * Send a conversation to Gemini and return the assistant's reply text.
 * This is the ONLY function in the whole project that touches the API key.
 */
async function sendToGemini({
  messages,
  systemPrompt = DEFAULT_SYSTEM_PROMPT,
  maxOutputTokens = 2048,
}) {
  if (!GEMINI_API_KEY) {
    throw new Error(
      'GEMINI_API_KEY is not set on the server. Create backend/.env from .env.example and add your key.'
    );
  }

  const contents = buildGeminiContents(messages, systemPrompt);

  const response = await fetch(GEMINI_URL(GEMINI_API_KEY), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents,
      generationConfig: {
        maxOutputTokens,
        temperature: 0.8,
      },
      safetySettings: [
        { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_MEDIUM_AND_ABOVE' },
        { category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'BLOCK_MEDIUM_AND_ABOVE' },
        { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'BLOCK_MEDIUM_AND_ABOVE' },
        { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'BLOCK_MEDIUM_AND_ABOVE' },
      ],
    }),
  });

  const data = await response.json();

  if (!response.ok) {
    const message = data?.error?.message || `Gemini API error (${response.status})`;
    throw new Error(message);
  }

  return extractGeminiText(data);
}

module.exports = { sendToGemini, DEFAULT_SYSTEM_PROMPT };
