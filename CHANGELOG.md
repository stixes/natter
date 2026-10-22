# Changelog

Notes here are user-facing, not commit-speak.

## add-streaming-spine

The first version that works: point Natter at an OpenAI-compatible endpoint and
chat.

- Settings holds one base URL, one model name, and an API key if your endpoint
  wants one. The key is kept in the Android keystore, and never appears in
  settings, history, or logs.
- The API key is optional. A local server that needs no authentication works
  out of the box.
- Replies arrive piece by piece as the endpoint produces them, as plain text.
- While an endpoint is working, the reply slot shows Waiting. or Thinking.
  instead of a blank screen. Thinking text is captured but not shown as the
  reply. If an endpoint sends only thinking and no answer, that thinking becomes
  the reply rather than an empty message.
- You can stop a reply in flight. Whatever already arrived is kept as the reply.
  A reply that was only thinking is dropped instead of kept.
- When the endpoint fails, you get a short reason and Retry, which sends what
  you already said again.
- Nothing is saved yet. Conversations live in memory, and closing the app
  discards them.
