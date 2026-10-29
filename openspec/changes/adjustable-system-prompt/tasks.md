# Tasks

The prompt changes the request body, so this change touches the network path
and closes with a live on-device round in 5.1, recorded in `validation.md`.
It modifies `chat-streaming`, which the acceptance suite covers: 4.2 adds the
request-shape assertion to the existing streaming scenario, and 4.1 adds a
suite file for the new `system-prompt` capability. Durability across a restart
is confirmed by unit tests (2.2) rather than the suite, because the suite
launches the app in-process and cannot kill and relaunch it.

## 1. Request path

- [x] 1.1 Add a `systemPrompt` parameter (empty string means none) to
  `ChatStreamService.stream` in `lib/data/chat_completions_client.dart`, and
  have `ChatCompletionsClient` prepend one `{'role': 'system', 'content': ...}`
  when it is non-empty. Update `ScriptedChatService` and `RecordedRequest` in
  `test/support/test_support.dart` to record it. In
  `test/chat_completions_client_test.dart`, extend the existing payload test
  pattern with: a non-empty prompt lands as the single first message ahead of
  user and assistant turns; an empty prompt leaves `messages` exactly as today.
  Verify `flutter test test/chat_completions_client_test.dart`.
- [x] 1.2 Leave `ChatMessage` and `ChatRole` user/assistant only, per design.md;
  verify with `grep -n "system" lib/domain/chat_message.dart` returning
  nothing and `flutter analyze` clean.

## 2. Prompt setting

- [x] 2.1 Add the built-in default as one `const` string in `lib/domain/`
  (starting text from design.md), plus a small setting type that resolves the
  prompt in effect from the stored state. Verify with unit tests in a new
  `test/system_prompt_test.dart` covering default, edited, and cleared.
- [x] 2.2 Add `SystemPromptRepository` in `lib/data/` over `KeyValueStore`,
  mirroring `ProfileRepository`, with the `chat.systemPrompt` tri-state and
  save rules from design.md (whitespace-only stores `""`, default text deletes
  the key, other text is stored trimmed). Extend `test/system_prompt_test.dart`
  using `SharedPreferences.setMockInitialValues` as
  `test/durable_settings_test.dart` does: an edited prompt and a cleared prompt
  each survive a simulated restart; saving the default leaves the key absent;
  the prompt never appears in the secure store's `contents()`. Verify
  `flutter test test/system_prompt_test.dart`.
- [x] 2.3 Add `systemPromptProvider` (a notifier with `loadStored()` and
  `save()`, mirroring `ProfileController`) in `lib/state/chat_providers.dart`,
  await `loadStored()` in `lib/main.dart` beside the profile load, and pass the
  prompt in effect from `ConversationController` on both send and retry. In
  `test/conversation_controller_test.dart`, verify: send carries the current
  prompt; a retry after the prompt changed carries the new one; a reopened
  conversation's next send carries the current prompt; saved turns and the
  title contain no prompt text. Verify
  `flutter test test/conversation_controller_test.dart`.

## 3. Settings screen

- [ ] 3.1 In `lib/ui/settings_screen.dart`, add the multi-line `System prompt`
  field below Model (pre-filled with the prompt in effect; min 3, max 8 lines,
  then internal scroll), the helper text and `Reset to default` text button
  from design.md (disabled while the field holds the default), save it with the
  existing Save, and change the title to `Settings`. Change the settings
  `IconButton` tooltip in `lib/ui/chat_screen.dart` to `Settings` and update
  the `find.byTooltip('Endpoint')` case in `test/chat_screen_test.dart`. States
  implemented: default, edited, empty, reset-then-save, leave-without-save.
  Verify with widget cases in a new `test/settings_screen_test.dart` for each
  state, plus a semantics check that Reset has its label and a 48x48 dp target,
  and that the field does not clip at 2.0 text scale. Run
  `flutter test test/settings_screen_test.dart test/chat_screen_test.dart`.
- [ ] 3.2 On-device look on the emulator on `<dev-box>` (or `<device>` as
  fallback): settings screen in light and dark, a long prompt scrolling inside
  the field with the keyboard up and Save still reachable, Reset enabled and
  disabled, and TalkBack focus order field, Reset, Save. Check against
  `openspec/design-ux-guidelines.md` and record the look and any deliberate
  exception in `validation.md`.

## 4. Acceptance suite

- [ ] 4.1 Add `integration_test/accept/system_prompt_accept_test.dart`, one
  scenario per requirement it confirms and named in the suite's
  `capability / requirement` style, plus a `setPromptField` helper in
  `harness.dart` (field index 3, after Model; `configureEndpoint` keeps using
  indices 0 and 2). Scenarios: `Built-in default prompt` - after
  `clearStoredConfig`, the first message on the wire is `system` with the
  default text; `Editable prompt setting` - an edited and saved prompt rides
  the next request; `Cleared prompt sends no system message` - a cleared
  prompt sends user turns only; `Prompt stays out of the conversation` - no
  rendered text contains the prompt after a reply. The file's last scenario
  resets to default so later suite files see a default install. Verify
  `scripts/accept.sh` exits 0 on the emulator on `<dev-box>`.
- [ ] 4.2 Extend `chat-streaming / Streaming reply` in
  `integration_test/accept/chat_streaming_accept_test.dart` to confirm the
  modified `Streaming reply delivery` scenario: `lastRequestBody['messages']`
  starts with one `system` message followed by the user turn. Verify
  `scripts/accept.sh` exits 0 and the full suite stays under five minutes.

## 5. Live round and release notes

- [ ] 5.1 Live on-device round against a live endpoint on
  `<llama-swap-host>` (URL, model, and key via `--dart-define`, never
  committed), recorded in a new `validation.md`: with the default prompt, send
  the same three probes (a short factual question, a "compare these options"
  question that tempts a wide table, a code request) to each model in regular
  use, and record reply length and shape against the same probes with the
  prompt cleared. Record any model whose template rejects the `system` role and
  confirm the surfaced error and the clear-to-recover path. Settle the final
  default wording from these replies and update the constant if it changes.
- [ ] 5.2 Add a user-facing `CHANGELOG.md` entry: replies are now brief and
  phone-friendly by default, where the setting lives, how to edit, reset, or
  clear it, and that it never appears in chats or history. Verify the entry
  reads as user-facing prose with no commit-speak.
- [ ] 5.3 Verify `flutter analyze && flutter test` pass in the devcontainer and
  `openspec validate adjustable-system-prompt --strict` is green.

## Workflow follow-up

- Run the publishable scan over every commit on the branch and the pushed
  tree before merge.
- Read the CI verdict for the pushed commit (`gh run list --branch
  adjustable-system-prompt --limit 1`); a red or pending run blocks archive.
- Archive with `/opsx-archive` after review, which syncs `system-prompt` and
  the `chat-streaming` delta into `openspec/specs/`.
