require('dotenv').config();

const express = require('express');
const cors = require('cors');

const repo = require('./chatsRepository');
const { sendToGemini } = require('./geminiClient');
const { requireAppKey } = require('./authMiddleware');

const app = express();
app.use(cors());
app.use(express.json({ limit: '2mb' }));
app.use(requireAppKey);

const PORT = process.env.PORT || 4000;

// ─── Health check ────────────────────────────────────────────────────────────

app.get('/health', (_req, res) => {
  res.json({ ok: true, time: new Date().toISOString() });
});

// ─── Chats ────────────────────────────────────────────────────────────────────

// GET /chats — list all chats (most recently updated first), each with a
// lightweight preview of its last message.
app.get('/chats', (_req, res) => {
  const chats = repo.listChats();
  const withPreview = chats.map((chat) => {
    const messages = repo.getMessages(chat.id);
    const last = messages[messages.length - 1];
    return {
      ...chat,
      message_count: messages.length,
      last_message: last ? last.content.slice(0, 120) : null,
    };
  });
  res.json(withPreview);
});

// POST /chats — create a new chat. Body: { title?: string }
app.post('/chats', (req, res) => {
  const { title } = req.body || {};
  const chat = repo.createChat(title);
  res.status(201).json(chat);
});

// GET /chats/:id — fetch one chat with its full message history
app.get('/chats/:id', (req, res) => {
  const chat = repo.getChat(req.params.id);
  if (!chat) return res.status(404).json({ error: 'Chat not found.' });
  const messages = repo.getMessages(chat.id);
  res.json({ ...chat, messages });
});

// PUT /chats/:id — rename a chat. Body: { title: string }
app.put('/chats/:id', (req, res) => {
  const { title } = req.body || {};
  if (!title || !title.trim()) {
    return res.status(400).json({ error: '"title" is required.' });
  }
  const chat = repo.renameChat(req.params.id, title);
  if (!chat) return res.status(404).json({ error: 'Chat not found.' });
  res.json(chat);
});

// DELETE /chats/:id — delete a chat and its messages
app.delete('/chats/:id', (req, res) => {
  const deleted = repo.deleteChat(req.params.id);
  if (!deleted) return res.status(404).json({ error: 'Chat not found.' });
  res.status(204).send();
});

// ─── Chat messaging ───────────────────────────────────────────────────────────

// POST /chat — send a message to Gemini within a chat.
// Body: { chat_id: string, message: string }
// Behavior:
//   1. Persists the user's message.
//   2. Loads the full prior history for that chat from the DB (server is the
//      source of truth — Flutter never needs to resend history).
//   3. Calls Gemini.
//   4. Persists the assistant's reply.
//   5. Auto-titles the chat from the first user message if it's still
//      "New chat".
app.post('/chat', async (req, res) => {
  const { chat_id, message } = req.body || {};

  if (!chat_id || typeof message !== 'string' || !message.trim()) {
    return res.status(400).json({ error: '"chat_id" and "message" are required.' });
  }

  const chat = repo.getChat(chat_id);
  if (!chat) return res.status(404).json({ error: 'Chat not found.' });

  // 1. Persist user message
  repo.addMessage(chat_id, 'user', message.trim());

  // 2. Build history for Gemini (exclude nothing — server owns the context)
  const history = repo
    .getMessages(chat_id)
    .map((m) => ({ role: m.role, content: m.content }));

  try {
    // 3. Call Gemini
    const reply = await sendToGemini({ messages: history });

    // 4. Persist assistant reply
    const saved = repo.addMessage(chat_id, 'assistant', reply);

    // 5. Auto-title new chats from the first user message
    if (chat.title === 'New chat') {
      const autoTitle = message.trim().slice(0, 40) + (message.trim().length > 40 ? '…' : '');
      repo.renameChat(chat_id, autoTitle);
    }

    res.json({
      reply: saved.content,
      message_id: saved.id,
      chat_id,
      created_at: saved.created_at,
    });
  } catch (err) {
    console.error('[POST /chat] Gemini error:', err.message);
    res.status(502).json({ error: err.message || 'Failed to reach Gemini.' });
  }
});

// ─── Fallback 404 ─────────────────────────────────────────────────────────────

app.use((req, res) => {
  res.status(404).json({ error: `No route for ${req.method} ${req.path}` });
});

// ─── Error handler ────────────────────────────────────────────────────────────

app.use((err, _req, res, _next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error.' });
});

app.listen(PORT, () => {
  console.log(`✅ AI Studio backend listening on http://localhost:${PORT}`);
  console.log(`   Gemini model: ${process.env.GEMINI_MODEL || 'gemini-2.5-flash'}`);
  console.log(`   API key set:  ${process.env.GEMINI_API_KEY ? 'yes' : 'NO — set it in .env!'}`);
});
