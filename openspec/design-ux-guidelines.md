# Natter Design and UX Guidelines

This document is the design and UX source of truth for Natter. It sits beside
`openspec/config.yaml` and is referenced by the per-artifact rules there. The
product principles in AGENTS.md remain authoritative; this document translates
them into design and UX expectations. The bar is the ChatGPT app's conversation
feel: smooth token streaming, sensible auto-titling, instant thread switching.
Flutter is chosen for velocity, not as an excuse.

## Principles

- The chat screen is the product. Every other surface supports it; a new screen
  must earn its place.
- Subtraction over addition. Prefer removing or simplifying a control before
  adding one.
- Polish is part of the feature. If scrolling, keyboard handling, markdown,
  copy affordances, or dark mode feels cheap on Android, the change is not done.
- Local and private by default. History is instant and never leaves the device
  without explicit user action. Search and export are destinations, not shipped;
  see `openspec/specs/conversation-history/spec.md` for what exists today.
- Material 3 is the base. Use platform conventions unless the conversation
  experience gives a clear reason to differ.
- Calm over clever. Motion, color, and copy should explain state, not perform.

## Interaction states

Every user-facing surface must define its states, not just the happy path. The
chat screen must cover at least:

### Empty

- First launch, no threads, or no endpoint configured. Say what to do next in
  one sentence; do not show a blank page or a disabled Send without a reason.
- An empty thread shows a composer and a short prompt, not a marketing page.

### Loading and streaming

- Before the first token, show an animated placeholder. The label is `Waiting`
  before any token, then `Thinking` while reasoning is active and no answer
  text has begun.
- Streaming appends tokens without layout jumps. The composer stays usable and
  the transcript stays readable while text arrives.
- A role-only or empty delta does not end the waiting state.

### Error

- Distinguish network, auth, rate limit, malformed SSE, and server errors.
- Say what happened and what to do next. Offer retry where it is safe.
- Never silently swallow a failed request or leave a spinner running.

### Offline

- Say the endpoint is unreachable. Keep local history readable. Export is a
  destination, not shipped; do not require it today.
- Do not block access to existing threads because the network is down.

### Cancel and retry

- Cancel stops the stream. Any answer text already received is saved as a
  normal assistant message; if only reasoning streamed and no answer text
  arrived, no assistant turn is saved.
- Cancel does not offer Retry. Retry is offered after a failed reply and
  re-sends the existing conversation.
- A cancelled partial answer is not specially marked. A retry-after-cancel
  affordance or a partial-answer marker would be a new behavior and needs its
  own proposal.

### Empty answer

- If the stream ends with empty answer text but non-empty reasoning, use the
  shipped blank-answer fallback and render the reasoning as the answer.
- If both answer text and reasoning are empty, surface an error or placeholder;
  a richer fallback for that case would be a new behavior and needs its own
  proposal.

## Motion and scroll behavior

- Motion explains state change; it does not decorate. No gratuitous animation.
- Streaming must not fight the user. Auto-scroll only when the user is at the
  bottom; if they scroll up, stop following until they return.
- The composer stays above the keyboard. Sending a message must not hide the
  input or jump the transcript.
- Placeholder animation runs on its own timer and stops on cancel or error; it
  must not depend on token arrival.
- Dark and light themes share the same motion and layout; only color changes.
- Respect reduced-motion settings where the platform exposes them.

## Accessibility

- Meet WCAG AA contrast in light and dark themes. Do not rely on color alone to
  convey state; pair it with text or an icon.
- Touch targets are at least 48x48 dp. The composer, send, cancel, retry, and
  thread actions must be easy to hit one-handed.
- Support Android text scaling without clipping or truncating message content.
- Provide screen-reader labels for icon-only controls. Announce streaming state
  changes without reading every token.
- Keyboard and focus order follow the visual order; the composer is reachable
  without a pointer.
- Do not disable accessibility services or rely on long-press as the only path
  to a common action.

## Copy tone

- Concise, direct, human. No jargon, no filler, no exclamation marks.
- Error messages say what happened and what to do next. Avoid blaming the user.
- Empty states and permission prompts explain the benefit in one sentence.
- Auto-titles are short and specific, derived from the first user message; do
  not fall back to "New chat" after the first exchange.
- Copy is part of design review, not a last-minute string swap.

## Dark mode

- Dark mode is a first-class theme, not an inverted light theme. Check contrast,
  surfaces, dividers, and disabled states separately.
- Avoid pure black and pure white for large surfaces; use the Material 3 tonal
  palette so elevation reads correctly.
- Streaming text, placeholders, and error states must remain legible in both
  themes.
- Do not hard-code colors in widgets; use theme tokens so dark mode stays
  consistent.

## Review checklist

Use this checklist at each artifact. If a row does not apply, say so in one
sentence instead of leaving it blank.

- **Proposal**: name the user-facing surface and its UX impact, or state that
  the change has no user-facing surface. Call out any interaction state that is
  changing.
- **Specs**: for user-facing behavior, scenarios cover loading, empty, error,
  and cancellation where relevant. State the accessibility expectation when the
  change affects it.
- **Design**: include a `## UX and interaction` section covering states, motion,
  accessibility, copy, and dark mode; cite this document; state when a row does
  not apply. Point to this document instead of restating it.
- **Tasks**: a UI task names the states it implements and how to verify them.
  A visual change owes an on-device look on the emulator on `<dev-box>`, or on
  `<device>` as a fallback. A task that cannot be verified on device must say
  why.
- **Apply**: before marking a UI task done, check the implementation against
  this document and note any deliberate exception in the task or a follow-up.
