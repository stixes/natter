// On-device harness for tasks 7.1 and 7.3 of add-streaming-spine.
//
// Each test is a separate process-to-device round trip, because a run against a
// live endpoint over wireless adb takes minutes and a network dropout should
// cost one round rather than the whole suite.
//
// Values come from --dart-define so no key ever reaches the repository. Hosts
// below are placeholders; substitute your own (angle brackets are not shell-safe
// as written):
//
//   flutter test integration_test -d <device> -n "7.1 plain" \
//     --dart-define=NATTER_BASE_URL=http://<llama-swap-host>:8000/v1 \
//     --dart-define=NATTER_BAD_URL=http://<llama-swap-host>:1/v1 \
//     --dart-define=NATTER_PLAIN_MODEL=gemma4-26b-a4b \
//     --dart-define=NATTER_THINKING_MODEL=qwen3.6-35b-a3b \
//     --dart-define=NATTER_API_KEY=
//
// Start each round from a clean slate so the "not configured yet" assertions
// mean something: `adb -s <device> shell pm clear dev.natter.app`.
//
// This is deliberately not CI-clean: it is a task-scoped validation harness for
// a live endpoint, and it goes away with the change once 7.1/7.3 are recorded.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:natter/main.dart' as app;
import 'package:natter/ui/message_bubble.dart';

const baseUrl = String.fromEnvironment('NATTER_BASE_URL');
const badUrl = String.fromEnvironment('NATTER_BAD_URL');
const plainModel = String.fromEnvironment('NATTER_PLAIN_MODEL');
const thinkingModel = String.fromEnvironment('NATTER_THINKING_MODEL');
const apiKey = String.fromEnvironment('NATTER_API_KEY');
const mockUrl = String.fromEnvironment('NATTER_MOCK_URL');

// Emitted only as `reasoning_content` by integration_test/support's mock
// endpoint, so seeing it in the transcript proves the blank-answer fallback.
const mockMarker = 'nothing here is answer text, by construction.';

// Long enough that tokens keep arriving for seconds. A one-line answer can
// finish inside a single poll and look as if it never streamed.
const countingPrompt = 'Count from 1 to 60, one number per line.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('7.1 plain model streams incrementally', (tester) async {
    await _launch(tester);

    // Fresh install: nothing configured, so the screen must say so and Send
    // must be inert rather than firing a doomed request.
    expect(find.textContaining('Point Natter at an OpenAI-compatible endpoint'),
        findsOneWidget);
    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);

    await _configure(tester, endpoint: baseUrl, model: plainModel);
    await _type(tester, countingPrompt);
    await _tapSend(tester);
    final plain = await _collect(tester);
    _report('7.1 plain', plain);

    // A warm local endpoint can land the first `content` delta inside a single
    // frame, so `Waiting.` is not reliably observable here for a content-only
    // model; that ordering contract is asserted deterministically by the widget
    // test. What a live round proves is that no placeholder ever reached the
    // message body and that no thinking state was invented.
    expect(_placeholderLeaks(plain), isEmpty,
        reason: 'a placeholder label must never be rendered as message body');
    expect(plain.answer, contains('55'), reason: 'the answer must arrive');
    expect(plain.growthSteps, greaterThan(2),
        reason: 'text must arrive in pieces, not all at once');
    expect(plain.labels, isNot(contains('Thinking')),
        reason: 'a plain model must not fake a thinking state');
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('7.1 thinking model keeps reasoning hidden', (tester) async {
    await _launch(tester);

    await _configure(tester, endpoint: baseUrl, model: thinkingModel);
    await _type(tester,
        'Think step by step about how many toes octopuses have, then give the '
        'final number.');
    await _tapSend(tester);
    final thinking = await _collect(tester);
    _report('7.1 thinking', thinking);

    expect(thinking.labels, containsAllInOrder(['Waiting', 'Thinking']),
        reason: 'the thinking state must be observable after Waiting, and '
        'first deltas that carry only a role must not fake an answer state');
    expect(thinking.answer.length, greaterThan(20),
        reason: 'an answer must eventually render');
    expect(_placeholderLeaks(thinking), isEmpty,
        reason: 'the placeholder must never leak into the message body');
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('7.3 cancel mid-stream commits the partial turn',
      (tester) async {
    await _launch(tester);

    await _configure(tester, endpoint: baseUrl, model: thinkingModel);
    await _type(tester,
        'Think step by step, then describe the colour of the sky in as many '
        'words as you can manage.');
    await _tapSend(tester);
    await _streamStarted(tester);
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget,
        reason: 'a stream must be in flight to cancel');

    await tester.tap(find.byIcon(Icons.stop_circle_outlined));
    await _settle(tester);
    final cancelled = await _drain(tester);
    _report('7.3 cancel', cancelled);

    expect(cancelled.answer, isNotEmpty,
        reason: 'a partial stream must commit as a turn');
    expect(cancelled.labels, isEmpty,
        reason: 'no placeholder may survive a cancel');
    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing,
        reason: 'the Stop affordance must go away on cancel');
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('7.3 cancel during thinking commits nothing', (tester) async {
    await _launch(tester);

    // A thinking model gives the cancel path a real workout: abort while only
    // reasoning has arrived. Nothing may be committed - half a chain of thought
    // is not an answer - and the conversation must stay clean and sendable.
    await _configure(tester, endpoint: baseUrl, model: thinkingModel);
    await _type(tester,
        'Think step by step about why the sky looks blue, at some length.');
    await _tapSend(tester);
    await _reachedThinking(tester);

    expect(_placeholderLabel(tester), 'Thinking',
        reason: 'the cancel must land while still in the thinking state');
    expect(_lastAssistantText(tester), isEmpty,
        reason: 'no answer token may have arrived, or the thinking-phase '
        'cancel is not what is being tested');

    await tester.tap(find.byIcon(Icons.stop_circle_outlined));
    await _settle(tester);
    final cancelled = await _drain(tester);
    _report('7.3 cancel during thinking', cancelled);

    expect(_assistantTurns(tester), isEmpty,
        reason: 'a thinking-phase cancel must commit no assistant turn');
    expect(cancelled.labels, isEmpty,
        reason: 'no placeholder may survive a cancel');
    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);

    // The conversation must still be usable after such a cancel.
    await _type(tester, 'Ignore all that. Just answer: what colour is the sky?');
    final after = await _reply(tester, '');
    _report('7.3 usable after thinking cancel', after);
    expect(after.answer, isNotEmpty,
        reason: 'a thinking-phase cancel must not wedge the conversation');
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets('7.3 blank-answer fallback commits the reasoning', (tester) async {
    await _launch(tester);

    // No live model here reliably ends a stream with reasoning and no answer
    // text, so this round runs against the mock endpoint: a real HTTP/SSE
    // exchange, just with a shape only a mock can guarantee.
    await _configure(tester, endpoint: mockUrl, model: 'mock-reasoning-only');
    await _type(tester, 'Say anything.');
    await _tapSend(tester);
    final fallback = await _collect(tester);
    _report('7.3 blank-answer fallback', fallback);

    expect(fallback.labels, containsAllInOrder(['Waiting', 'Thinking']),
        reason: 'reasoning alone must drive the thinking state');
    expect(fallback.answer, contains(mockMarker),
        reason: 'a stream that ends with no answer text must commit the '
        'captured reasoning rather than an empty turn');
    expect(fallback.growthSteps, 1,
        reason: 'reasoning must not render as answer text while it streams; it '
        'arrives once, as the fallback');
    expect(_placeholderLeaks(fallback), isEmpty,
        reason: 'the placeholder must never be rendered as message body');
  }, timeout: const Timeout(Duration(minutes: 6)));

  testWidgets('7.3 error surfaces and retry clears it', (tester) async {
    await _launch(tester);

    await _configure(tester, endpoint: badUrl, model: plainModel);
    final failed = await _reply(tester, 'Say something.');
    _report('7.3 error', failed);
    expect(failed.screen, contains('Retry'),
        reason: 'an unreachable endpoint must surface the retry affordance');
    expect(
      failed.screen.any((text) => text.startsWith('Cannot reach the endpoint')),
      isTrue,
      reason: 'the banner must name the failure, not just appear',
    );

    await _configure(tester, endpoint: baseUrl, model: plainModel);
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await _settle(tester);
    final retried = await _collect(tester);
    _report('7.3 retry', retried);

    expect(
      find.textContaining('Cannot reach the endpoint'),
      findsNothing,
      reason: 'a successful retry must clear the old error',
    );
    expect(retried.answer, isNotEmpty, reason: 'the retry must produce a reply');
  }, timeout: const Timeout(Duration(minutes: 8)));
}

/// A record of one reply, folded from the frames observed while it streamed.
class Reply {
  const Reply({
    required this.labels,
    required this.growthSteps,
    required this.renderedBeforeFirstToken,
    required this.rendered,
    required this.bodies,
    required this.settled,
    required this.screen,
  });

  /// Placeholder labels seen, in first-seen order.
  final List<String> labels;

  /// How many frames the answer grew between.
  final int growthSteps;

  /// Body text rendered before the first answer token arrived.
  final List<String> renderedBeforeFirstToken;

  /// Every distinct answer string, in order, from the first token onward.
  final List<String> rendered;

  /// Every string ever rendered as message body, user turns included.
  final List<String> bodies;

  /// True when the stream closed on its own.
  final bool settled;

  /// Every string seen on screen: labels, banners, hints, composer content.
  final List<String> screen;

  String get answer => rendered.isEmpty ? '' : rendered.last;
}

/// One frame of interest.
class _Observation {
  const _Observation(this.label, this.answer, this.bodies, this.chrome);

  final String? label;
  final String answer;
  final List<String> bodies;
  final List<String> chrome;
}

void _report(String tag, Reply reply) {
  debugPrint('$tag settled=${reply.settled} growth=${reply.growthSteps} '
      'labels=${reply.labels}');
  debugPrint('$tag answer="${_ellipsis(reply.answer)}"');
  debugPrint('$tag screen=${reply.screen}');
}

String _ellipsis(String text) => text.length <= 120
    ? text
    : '${text.substring(0, 60)} ... ${text.substring(text.length - 40)}';

Future<void> _launch(WidgetTester tester) async {
  app.main();
  await _settle(tester);
}

/// A wait that lets the app react without assuming how fast it is.
Future<void> _tick(
    WidgetTester tester, [Duration length = const Duration(milliseconds: 250)]) async {
  await tester.pump(length);
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await _tick(tester);
  }
}

Future<void> _configure(
  WidgetTester tester, {
  required String endpoint,
  required String model,
}) async {
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await _settle(tester);
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), endpoint);
  if (apiKey.isNotEmpty) await tester.enterText(fields.at(1), apiKey);
  await tester.enterText(fields.at(2), model);
  await SystemChannels.textInput.invokeMethod('TextInput.hide');
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await _settle(tester);
}

Future<void> _type(WidgetTester tester, String prompt) async {
  final field = find.byType(TextField).first;
  await tester.tap(field);
  await _tick(tester);
  await tester.enterText(field, prompt);
  await _tick(tester);
  await SystemChannels.textInput.invokeMethod('TextInput.hide');
  await _tick(tester);
}

Future<void> _tapSend(WidgetTester tester) async {
  await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_upward));
  await _tick(tester, const Duration(milliseconds: 50));
  final left =
      tester.widget<TextField>(find.byType(TextField).first).controller?.text ??
          '';
  if (left.isNotEmpty) {
    throw StateError('Send did not fire: the composer still holds "$left"');
  }
  debugPrint('send fired; screen=${_texts(tester)}');
}

Future<Reply> _reply(WidgetTester tester, String prompt) async {
  if (prompt.isNotEmpty) await _type(tester, prompt);
  await _tapSend(tester);
  return _collect(tester);
}

/// Committed assistant turns on screen, excluding any in-flight draft.
List<MessageBubble> _assistantTurns(WidgetTester tester) => [
      for (final bubble in _bubbles(tester))
        if (!bubble.isMine && bubble.placeholderLabel == null) bubble,
    ];

/// Polls until the stream closes. Polls fast early: a warm local endpoint can
/// start streaming within a tenth of a second.
Future<void> _streamStarted(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(minutes: 4));
  while (DateTime.now().isBefore(deadline)) {
    for (var i = 0; i < 4; i++) {
      await _tick(tester, const Duration(milliseconds: 50));
    }
    if (_lastAssistantText(tester).isNotEmpty) return;
  }
  throw StateError('no answer text ever appeared to cancel');
}

Future<void> _reachedThinking(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (_placeholderLabel(tester) == 'Thinking') return;
    await _tick(tester, const Duration(milliseconds: 50));
  }
  throw StateError('the thinking state never appeared; labels observed were '
      '${_texts(tester)}');
}

Future<Reply> _collect(WidgetTester tester) =>
    _poll(tester, const Duration(minutes: 6));

Future<Reply> _drain(WidgetTester tester) =>
    _poll(tester, const Duration(minutes: 2));

Future<Reply> _poll(WidgetTester tester, Duration budget) async {
  final observations = <_Observation>[];
  final deadline = DateTime.now().add(budget);
  while (DateTime.now().isBefore(deadline)) {
    observations.add(_observe(tester));
    if (!_streaming()) return _summarize(observations);
    // Brief states are the interesting ones: sample densely at the start.
    final quick = observations.length < 12;
    await _tick(tester,
        quick ? const Duration(milliseconds: 50) : const Duration(milliseconds: 250));
  }
  debugPrint('poll exhausted its budget with the stream still open');
  return _summarize(observations, settled: false);
}

_Observation _observe(WidgetTester tester) => _Observation(
      _placeholderLabel(tester),
      _lastAssistantText(tester),
      [for (final body in _renderedTexts(tester)) body.trim()],
      _texts(tester),
    );

/// Folds frames into one record. What changed between frames is what a user
/// actually sees, so growth and ordering are derived from the sequence.
Reply _summarize(List<_Observation> observations, {bool settled = true}) {
  final labels = <String>[];
  final screen = <String>[];
  for (final observation in observations) {
    final label = observation.label;
    if (label != null && !labels.contains(label)) labels.add(label);
    for (final text in observation.chrome) {
      if (!screen.contains(text)) screen.add(text);
    }
  }

  final firstToken = observations.indexWhere((o) => o.answer.isNotEmpty);

  final beforeFirstToken = <String>[];
  for (final observation in observations.take(max(firstToken, 0))) {
    for (final body in observation.bodies) {
      if (!beforeFirstToken.contains(body)) beforeFirstToken.add(body);
    }
  }

  final bodies = <String>[];
  for (final observation in observations) {
    for (final body in observation.bodies) {
      if (body.trim().isEmpty) continue;
      if (!bodies.contains(body)) bodies.add(body);
    }
  }

  final rendered = <String>[];
  var growthSteps = 0;
  var previous = '';
  for (final observation in observations.skip(max(firstToken, 0))) {
    final answer = observation.answer;
    if (answer.isEmpty) continue;
    if (!rendered.contains(answer)) rendered.add(answer);
    if (answer.length > previous.length) growthSteps++;
    previous = answer;
  }

  return Reply(
    labels: labels,
    growthSteps: growthSteps,
    renderedBeforeFirstToken: beforeFirstToken,
    rendered: rendered,
    bodies: bodies,
    settled: settled,
    screen: screen,
  );
}

List<MessageBubble> _bubbles(WidgetTester tester) =>
    tester.widgetList<MessageBubble>(find.byType(MessageBubble)).toList();

/// Every plain `Text` on screen: placeholders, banners, hints, labels.
List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((widget) => widget.data ?? '')
    .where((text) => text.isNotEmpty)
    .toList();

/// Message body text only.
List<String> _renderedTexts(WidgetTester tester) => tester
    .widgetList<SelectableText>(find.byType(SelectableText))
    .map((widget) => widget.data ?? '')
    .toList();

String _lastAssistantText(WidgetTester tester) {
  for (final bubble in _bubbles(tester).reversed) {
    if (!bubble.isMine && bubble.content.isNotEmpty) return bubble.content;
  }
  return '';
}

String? _placeholderLabel(WidgetTester tester) {
  for (final bubble in _bubbles(tester)) {
    if (bubble.placeholderLabel != null) return bubble.placeholderLabel;
  }
  return null;
}

/// Any rendered message body that is actually a placeholder label. The dots are
/// animated onto the label, so every trailing-dot variant counts.
List<String> _placeholderLeaks(Reply reply) => [
      for (final body in reply.bodies)
        if (RegExp(r'^(Waiting|Thinking|Answering)\.{0,3}$')
            .hasMatch(body.trim()))
          body,
    ];

bool _streaming() =>
    find.byIcon(Icons.stop_circle_outlined).evaluate().isNotEmpty;
