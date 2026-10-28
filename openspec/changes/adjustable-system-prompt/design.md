# Design

## Context

See `proposal.md` - Why. Today `ConversationController` hands the committed
turns (`List<ChatMessage>`, roles user and assistant only) to
`ChatStreamService.stream`, and `ChatCompletionsClient` maps them straight onto
the request's `messages`. Settings live on one screen (`SettingsScreen`, titled
`Endpoint`) backed by `ProfileRepository`, which splits base URL and model into
the plain `shared_preferences` store and the API key into the keystore. Both
stores load in `main()` before `runApp`. `ChatRole.name` is what the history
table stores as a turn's role.

## Goals / Non-Goals

**Goals:**
- A system prompt that is on by default, editable, resettable, and clearable,
  with the tri-state (default / edited / cleared) surviving restarts.
- A request shape where the prompt cannot reach conversation storage by
  construction, not by discipline.

**Non-Goals:**
- Tuning the default prompt per model or per endpoint.
- Showing the prompt anywhere on the chat screen.
- Any change to the history schema or stored rows.

## Decisions

### The prompt is a request parameter, not a conversation turn
`ChatStreamService.stream` gains a `systemPrompt` parameter (empty string means
none). `ChatCompletionsClient` prepends `{'role': 'system', 'content': ...}`
when it is non-empty. The controller reads the prompt in effect at the moment
it calls the service, so send and retry both pick up the current value.

Alternative considered: add `ChatRole.system` and prepend a `ChatMessage`.
Rejected: `ChatRole` is what the repository stores as a turn's role, and every
list of `ChatMessage` is a candidate for persistence and for the transcript. A
system role there would make "never stored, never shown" a rule every future
caller must remember. Keeping it out of `ChatMessage` makes the
`Prompt stays out of the conversation` requirement hold by type.

### Tri-state storage in the plain settings store
One `shared_preferences` key, `chat.systemPrompt`, read through the existing
`KeyValueStore` seam:

| Stored state | Prompt in effect | Field shows |
| --- | --- | --- |
| key absent | built-in default | default text |
| key = `""` | none | empty |
| key = text | that text | that text |

Save rules: text that trims to empty stores `""`; text that trims equal to the
built-in default deletes the key, so the user keeps following the default
across releases; anything else stores the text trimmed of leading and trailing
whitespace. The prompt is not a secret, and it is not conversation content, so
the plain settings store is the right home; it never touches the keystore.

Alternative considered: a boolean "use default" flag plus a text key. Rejected:
two keys can disagree, and the absent/empty/text distinction already encodes
all three states.

### A separate repository and provider, not `ProfileRepository`
A `SystemPromptRepository` over `settingsStoreProvider`, and a
`systemPromptProvider` notifier with `loadStored()` and `save()`, mirroring
`ProfileController`. `main()` awaits `loadStored()` beside the profile load.

Alternative considered: fold the prompt into `EndpointProfile`. Rejected:
`EndpointProfile` is shaped to become one of several switchable profiles
(issue #8), and the prompt is an app-wide reply style, not a property of an
endpoint. Coupling them now would force that decision on the profiles change.

### The built-in default lives in code, one constant
A `const` string in `lib/domain/`, starting text:

> You are the assistant in Natter, a small chat app on a phone. Keep replies
> brief and direct; give detail only when asked. Use light formatting: short
> paragraphs, simple lists, and code blocks for code. Avoid tables wider than
> three columns and avoid large headings, because the screen is narrow.

Final wording is settled in the live on-device round (tasks), judged against
real replies, not in review. It stays under ~80 tokens so the per-request cost
is negligible.

### One screen, one Save
The prompt field joins `SettingsScreen` below Model, and the existing Save
button saves both the profile and the prompt. The screen title and the chat
screen's settings tooltip change from `Endpoint` to `Settings`. Reset only
replaces the field text; the Save that follows is what commits it, matching how
every other field on the screen behaves.

Alternative considered: a separate prompt screen. Rejected: a second settings
surface for one field fails "a new screen must earn its place".

## UX and interaction

Per `openspec/design-ux-guidelines.md`.

- **States**: the field has three visible states - default text, edited text,
  empty. Empty shows the helper text explaining that no prompt is sent; there is
  no separate error state, since any text is valid. Loading does not apply: the
  value is loaded before `runApp`. The chat screen's waiting, streaming, error,
  cancel, and retry states are unchanged. A model or gateway that rejects the
  `system` role fails through the existing surfaced HTTP error with Retry.
- **Motion**: none added. The multi-line field grows to its max lines and then
  scrolls internally, so the Save button never jumps off screen while typing.
- **Accessibility**: the field has a visible label (`System prompt`) and helper
  text; Reset is a text button labelled `Reset to default`, at least 48x48 dp,
  in focus order after the field and before Save. The field survives large text
  scaling by wrapping and scrolling, never clipping. Reset is disabled when the
  field already holds the default, which a screen reader announces as disabled.
- **Copy**: label `System prompt`; helper `Sent before every chat. Leave empty
  to send none.`; action `Reset to default`; title `Settings`. No exclamation
  marks, no jargon beyond the field's own name, which is the term gateways use.
- **Dark mode**: only theme-token Material widgets are added; no colors are
  hard-coded. Checked on device in both themes.

## Risks / Trade-offs

- [A model's chat template rejects the `system` role, so an endpoint that
  worked before the upgrade now returns HTTP 400] → The existing error surface
  shows the endpoint's message with Retry; clearing the prompt in settings
  restores the old request shape. The live round sends the default to the
  models in regular use to catch this before release.
- [A gateway already injects its own system prompt, so the model sees two] →
  Accepted: Natter sends exactly one, and the user can clear it. Natter cannot
  see the gateway's injection.
- [Users who upgrade start receiving shorter replies without asking] →
  Intended; the changelog says so plainly and points to the setting.
- [Saving the untouched default deletes the key, so a user who wanted to pin
  today's default text cannot] → Accepted: pinning is one character away (edit
  the text). Following the default is the better default.

## Migration Plan

No data migration: an existing install has no `chat.systemPrompt` key, so it
reads as the default. Rolling back to an older build ignores the key and sends
no system message; reinstalling this build restores whatever was saved.
