# Changelog

Notes here are user-facing, not commit-speak.

## launch-on-new-chat

Open the app and start talking. No previous chat gets in the way.

- Launching Natter now opens a new, empty chat. Type and send; the reply comes
  back in that new chat. Before, the app reopened the last conversation you were
  in, so a first message could land in an old chat without you noticing.
- Every earlier chat is one tap away: the history list at the top left still
  shows them, grouped by day, and opening one puts it on screen with its turns
  intact. Nothing was removed from storage.
- A chat you were in stays put when you leave and come back - switching to
  another app and returning finds the same conversation, mid-reply and all.

## message-copy-actions

Copy a reply, a turn, or a single code block without selecting any of it first.

- Every finished turn carries a copy button next to its timestamp - yours and
  the assistant's alike. One tap puts that text on the clipboard.
- A reply that shows a code block gives that block its own button as well, so
  you can take the code alone, indentation and line breaks and all, instead of
  the reply wrapped around it.
- Copying your own turn puts down exactly what you typed, characters of any
  kind included. Copying a reply puts down the markdown the endpoint sent,
  which pastes back whole into anything that understands markdown.
- The button briefly becomes a check mark so you can see the copy landed, and
  nothing opens that you have to dismiss. The buttons name themselves to a
  screen reader (`Copy message`, `Copy code block`), and the label becomes
  `Copied` once the copy is on the clipboard.
- A reply that is still arriving offers nothing to copy. Stop one partway,
  though, and the answer you got is copyable like any other.
- Selecting part of a reply and copying from the platform's own toolbar still
  works exactly as before.

## adjustable-system-prompt

Every chat now carries a short instruction, and it is yours to change.

- Natter sends a built-in instruction ahead of every message: keep replies brief
  and direct, use light formatting, avoid wide tables and large headings. It
  shapes reply length and shape for a phone screen. Before this, nothing was
  sent, so replies came back at whatever length the endpoint chose.
- Settings holds a `System prompt` field below Model, with the shipped text
  already in it. Edit it for your own wording - a persona, a length rule, a
  "answer in one sentence" constraint - and the next message you send uses it.
- `Reset to default` puts the shipped text back in the field, then Save keeps
  it. The button is greyed out while the field already holds that text.
- Clear the field to send no instruction at all. An empty field saves as empty,
  and the reply comes back unshaped.
- The instruction is not part of your conversation. It never appears in the
  chat, in a reply, or in saved history. It does go to your endpoint with each
  request, like the rest of the chat, and it is a plain setting rather than a
  secret, so it is not kept in the keystore.

## add-ci-acceptance-gate

Every push now gets a verdict on its own commit.

- A build runs on every branch: static analysis, the widget test suite, and the
  acceptance gate, each with its own verdict, on a test device the build creates
  for itself and throws away afterwards.
- Nothing to configure, and nothing to hand over: the build needs no key and no
  endpoint, and it never contacts your own gateway. The rounds that check a live
  endpoint still happen on a real device, run by a person.
- A newer push replaces an in-flight build on a working branch. The default
  branch always gets a verdict, and a build that was cancelled does not count as
  a pass.
- Device failures name the stage: "the device could not be provisioned" is a
  different verdict from "this build is not releasable", and the logs from the
  failing stage are attached to the run.

## render-markdown-replies

Replies are formatted now, not raw markdown.

- Headings, bold and italic text, lists, task lists, quotes, tables, dividing
  lines, and fenced code blocks in a reply appear as structure, so no `#`, `**`,
  or backticks are left on screen. Your own messages still show exactly what you
  typed.
- Formatting arrives while the reply streams: a heading becomes a heading part-way
  through a sentence, and a code block that has not finished opening still shows
  the text that has arrived.
- A code block wider than its bubble scrolls sideways with a swipe.
- Links are drawn as links but do not open yet - a separate change will make
  them tappable. An image a reply mentions is named by its description and never
  downloaded.
- Tables keep their rows and columns, but their widths are still even, so a
  wide table can break a long word in a narrow column.

## chat-history-grouping-and-expiry

The history list now reads at a glance, and old chats clean themselves up.

- Saved conversations in the history drawer are grouped under headers: Today,
  Yesterday, This week, and Older. A section with no conversations shows no
  header, and chats inside each section stay newest first.
- Chats older than 90 days are removed from the device when Natter starts.
  Nothing is archived: a chat untouched for three months is deleted for good,
  so the drawer holds only the recent period you can actually browse.

## add-message-timestamps

Every message now shows when it was sent or answered.

- A small time label sits at the lower right of each message bubble, on the
  24-hour clock, so a reopened conversation keeps its sense of when things
  happened.
- The label stays quiet and follows light and dark mode. It is not a button and
  does not interrupt the reply as it streams.

## add-app-icon

Natter has a face of its own.

- The home-screen icon is now a chatty little speech bubble instead of the
  default placeholder, and it follows themed icons on Android 13 and later.
- The same bubble sits beside the Natter name at the top of the chat screen,
  in colours that match light and dark mode.

## local-conversation-history

Your conversations now survive closing the app.

- Every message you send and every answer you receive is saved on the device,
  so reopening Natter picks up where you left off.
- A history list shows your saved conversations, newest first. Tap one to
  reopen it or start a new chat; earlier conversations stay available.
- Conversation history never leaves the device. Android Auto Backup is turned
  off for Natter, and opening history makes no network request.

## add-endpoint-timeouts

Natter no longer waits forever on an endpoint that is not answering.

- If the endpoint never starts replying, Natter gives up after a short wait and
  tells you so, with Retry.
- If a reply stops arriving mid-stream, Natter keeps the text that already
  reached the screen as the reply, shows a short reason, and offers Retry.
- A slow endpoint that keeps sending data is left alone; only silence triggers
  the timeout.

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
