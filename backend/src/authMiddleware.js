/**
 * Optional, very simple shared-key check between the Flutter app and this
 * server. This is NOT meant to be strong security — it's a basic guard so
 * that if your local server is reachable on a LAN, random devices on the
 * same network can't use it as a free Gemini proxy. Set APP_SHARED_KEY in
 * .env to enable it; leave it empty to disable for local-only development.
 */
function requireAppKey(req, res, next) {
  const expected = process.env.APP_SHARED_KEY;
  if (!expected) return next(); // disabled

  const provided = req.header('X-App-Key');
  if (provided !== expected) {
    return res.status(401).json({ error: 'Missing or invalid X-App-Key header.' });
  }
  next();
}

module.exports = { requireAppKey };
