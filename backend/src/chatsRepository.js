const { v4: uuidv4 } = require('uuid');
const db = require('./db');

const nowIso = () => new Date().toISOString();

/** Create a new chat row. Returns the chat object. */
function createChat(title) {
  const id = uuidv4();
  const ts = nowIso();
  const chatTitle = (title && title.trim()) || 'New chat';
  db.prepare(
    `INSERT INTO chats (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)`
  ).run(id, chatTitle, ts, ts);
  return getChat(id);
}

/** Fetch one chat by id (without messages). */
function getChat(id) {
  return db.prepare(`SELECT * FROM chats WHERE id = ?`).get(id);
}

/** List all chats, most recently updated first. */
function listChats() {
  return db
    .prepare(`SELECT * FROM chats ORDER BY updated_at DESC`)
    .all();
}

/** Rename a chat. Returns the updated chat, or null if not found. */
function renameChat(id, title) {
  const chat = getChat(id);
  if (!chat) return null;
  db.prepare(`UPDATE chats SET title = ?, updated_at = ? WHERE id = ?`).run(
    title.trim() || chat.title,
    nowIso(),
    id
  );
  return getChat(id);
}

/** Delete a chat (cascades to its messages). Returns true if a row was deleted. */
function deleteChat(id) {
  const result = db.prepare(`DELETE FROM chats WHERE id = ?`).run(id);
  return result.changes > 0;
}

/** Touch a chat's updated_at timestamp (bumps it to the top of the list). */
function touchChat(id) {
  db.prepare(`UPDATE chats SET updated_at = ? WHERE id = ?`).run(nowIso(), id);
}

/** Append a message to a chat. Returns the inserted message row. */
function addMessage(chatId, role, content) {
  const id = uuidv4();
  const ts = nowIso();
  db.prepare(
    `INSERT INTO messages (id, chat_id, role, content, created_at) VALUES (?, ?, ?, ?, ?)`
  ).run(id, chatId, role, content, ts);
  touchChat(chatId);
  return { id, chat_id: chatId, role, content, created_at: ts };
}

/** Get all messages for a chat, oldest first. */
function getMessages(chatId) {
  return db
    .prepare(
      `SELECT * FROM messages WHERE chat_id = ? ORDER BY created_at ASC`
    )
    .all(chatId);
}

module.exports = {
  createChat,
  getChat,
  listChats,
  renameChat,
  deleteChat,
  touchChat,
  addMessage,
  getMessages,
};
