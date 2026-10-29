// Shared plumbing for the acceptance suite (add-acceptance-suite).
//
// The suite drives the real app on-device against a scripted
// `chat/completions` SSE endpoint served by this harness on the device's own
// loopback interface: hermetic, no external endpoint, no key, no
// --dart-define. The app reaches it through its own dart:io socket, so no
// cleartext exception is needed.
//
// Helpers reuse the plumbing proven by the task-scoped harnesses (see
// integration_test/timestamp_visibility_test.dart): launch through
// `app.main()`, drive the UI through real finders, and poll with pump loops
// because the placeholder animation never lets pumpAndSettle settle.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natter/main.dart' as app;
import 'package:natter/ui/message_bubble.dart';
import 'package:natter/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A scripted OpenAI-compatible endpoint on the device's loopback interface.
///
/// Each scenario assigns [script] right before sending, so one server covers
/// a whole test file. The handler gets a [SseWriter] to stream with real
/// wall-clock delays; the test pump loop advances in real time.
class ScriptedEndpoint {
  ScriptedEndpoint._(this._server) {
    _server.listen(_handle);
  }

  static Future<ScriptedEndpoint> start() async => ScriptedEndpoint._(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      );

  final HttpServer _server;

  /// Value to type into the settings Base URL field for this endpoint.
  String get baseUrl => 'http://127.0.0.1:${_server.port}/v1';

  /// Requests received so far, for shallow "did it call" checks.
  int requestCount = 0;

  /// Decoded body of the most recent request, or null before the first.
  Map<String, Object?>? lastRequestBody;

  /// The reply the next request gets; assign per scenario.
  void Function(SseWriter out)? script;

  Future<void> close() => _server.close(force: true);

  void _handle(HttpRequest request) {
    requestCount++;
    final current = script;
    if (current == null) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..close();
      return;
    }
    unawaited(
      utf8.decoder.bind(request.cast<List<int>>()).join().then((body) {
        try {
          lastRequestBody = jsonDecode(body) as Map<String, Object?>;
        } on FormatException {
          lastRequestBody = null;
        }
        current(SseWriter(request.response));
      }),
    );
  }
}

/// One SSE response body: data lines, raw lines for keepalives and malformed
/// payloads, gaps that hold the stream open, and terminal behaviours.
class SseWriter {
  SseWriter(this._response) {
    // dart:io buffers the whole response until close() by default, which
    // would deliver nothing to a client that reads incrementally - exactly
    // the behaviour this suite is here to exercise.
    _response.bufferOutput = false;
    _response.headers.contentType =
        ContentType('text', 'event-stream', charset: 'utf-8');
  }

  final HttpResponse _response;

  void data(Map<String, Object?> payload) =>
      _response.write('data: ${jsonEncode(payload)}\n\n');

  /// A literal line, for keepalives (`: ping`) and malformed payloads.
  void raw(String line) => _response.write('$line\n');

  Future<void> gap(Duration length) => Future.delayed(length);

  Future<void> done() async {
    _response.write('data: [DONE]\n\n');
    await _response.close();
  }

  /// Ends the response with an HTTP error status instead of SSE.
  Future<void> failStatus(int status) async {
    _response
      ..statusCode = status
      ..write('{"error":{"message":"scripted failure"}}');
    await _response.close();
  }
}

// Scenario-shaped scripts. Each assigns `endpoint.script`.

/// Answer chunks with keepalive comments, role-only and empty deltas, one
/// malformed line, and a usage-style payload mixed in, then `[DONE]`. This
/// is the everyday gateway dialect the shipped SSE parser promises to eat.
void scriptNormalStream(
  ScriptedEndpoint endpoint, {
  required List<String> chunks,
  Duration chunkGap = const Duration(milliseconds: 250),
}) {
  endpoint.script = (out) async {
    out.data({'choices': [{'delta': {'role': 'assistant'}}]});
    out.raw(': keepalive');
    for (final chunk in chunks) {
      out.data({'choices': [{'delta': {'content': chunk}}]});
      out.raw('data: {not json at all');
      await out.gap(chunkGap);
    }
    out.data({'choices': [{'delta': {}}]});
    await out.done();
  };
}

/// Reasoning-only deltas (`reasoning_content`), then `[DONE]`: the shape
/// that lands the blank-answer fallback.
void scriptReasoningOnly(
  ScriptedEndpoint endpoint, {
  required List<String> chunks,
  Duration chunkGap = const Duration(milliseconds: 250),
}) {
  endpoint.script = (out) async {
    for (final chunk in chunks) {
      out.data({
        'choices': [
          {'delta': {'reasoning_content': chunk}},
        ],
      });
      await out.gap(chunkGap);
    }
    await out.done();
  };
}

/// Answer chunks, then hold the stream open (no `[DONE]`) until the user
/// stops it.
void scriptAnswerThenHang(
  ScriptedEndpoint endpoint, {
  required List<String> chunks,
}) {
  endpoint.script = (out) async {
    for (final chunk in chunks) {
      out.data({'choices': [{'delta': {'content': chunk}}]});
      await out.gap(const Duration(milliseconds: 250));
    }
    // Keep the response open; the app will cancel its read.
    await out.gap(const Duration(seconds: 30));
  };
}

/// Reasoning chunks, then hold the stream open: thinking that never answers,
/// for the cancel-during-thinking scenario.
void scriptReasoningThenHang(
  ScriptedEndpoint endpoint, {
  required List<String> chunks,
}) {
  endpoint.script = (out) async {
    for (final chunk in chunks) {
      out.data({
        'choices': [
          {'delta': {'reasoning_content': chunk}},
        ],
      });
      await out.gap(const Duration(milliseconds: 250));
    }
    await out.gap(const Duration(seconds: 30));
  };
}

// UI plumbing.

/// Starts the real app and waits for it to settle enough to interact with.
Future<void> launchApp(WidgetTester tester) async {
  await app.main();
  await settle(tester);
}

/// Wipes stored config (plain settings + keystore) so an unconfigured
/// first launch is testable without a shell-level `pm clear`.
Future<void> clearStoredConfig() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await const FlutterSecureStorage().deleteAll();
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tick(tester);
  }
}

Future<void> tick(
  WidgetTester tester, [
  Duration length = const Duration(milliseconds: 250),
]) async {
  await tester.pump(length);
  await tester.pump();
}

Future<void> hideKeyboard(WidgetTester tester) =>
    SystemChannels.textInput.invokeMethod('TextInput.hide');

/// Types a base URL and model into the settings screen (key left empty; the
/// helper text says local servers often need none) and saves.
Future<void> configureEndpoint(
  WidgetTester tester, {
  required String baseUrl,
  required String model,
}) async {
  await openSettings(tester);
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), baseUrl);
  await tester.enterText(fields.at(2), model);
  await hideKeyboard(tester);
  await saveSettings(tester);
}

/// Opens the settings screen over the chat screen.
Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await settle(tester);
}

/// The settings screen's System prompt field: the fourth, after Model.
///
/// Found by its label rather than by index, so a field on the chat screen
/// cannot shift what the helper types into.
Finder promptField() => find.descendant(
  of: find.byType(SettingsScreen),
  matching: find.widgetWithText(TextField, 'System prompt'),
);

/// What the System prompt field currently holds, as the screen has it.
String promptFieldText(WidgetTester tester) =>
    tester.widget<TextField>(promptField()).controller!.text;

/// Replaces the System prompt field's text and saves; an empty [prompt] is
/// the cleared state, which sends no system message.
Future<void> setPromptField(WidgetTester tester, String prompt) async {
  await openSettings(tester);
  await tester.enterText(promptField(), prompt);
  await hideKeyboard(tester);
  await saveSettings(tester);
}

/// Scrolls the settings list to its end and taps Save.
///
/// The list builds its children lazily, and the multi-line prompt field makes
/// it tall enough that Save can sit outside the built range - a bare tap would
/// fail on an empty finder rather than on the behaviour under test. The offset
/// is moved directly because a gesture drag at the list's centre is swallowed
/// by whichever text field sits there.
Future<void> saveSettings(WidgetTester tester) async {
  final position = tester.state<ScrollableState>(
    find.descendant(
      of: find.byType(SettingsScreen),
      matching: find.byType(Scrollable),
    ).first,
  ).position;
  if (position.pixels < position.maxScrollExtent) {
    position.jumpTo(position.maxScrollExtent);
    await tick(tester);
  }
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await settle(tester);
}

Future<void> sendMessage(WidgetTester tester, String text) async {
  final field = find.byType(TextField).first;
  await tester.tap(field);
  await tick(tester);
  await tester.enterText(field, text);
  await tick(tester);
  await hideKeyboard(tester);
  await tick(tester);
  await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_upward));
  await tick(tester, const Duration(milliseconds: 50));
}

/// Sends [text] and waits until the endpoint saw the request (so the stream
/// really started) and the in-flight state has ended.
Future<void> awaitExchange(
  WidgetTester tester,
  ScriptedEndpoint endpoint,
  String text,
) async {
  final baseline = endpoint.requestCount;
  await sendMessage(tester, text);
  final startDeadline = DateTime.now().add(const Duration(seconds: 20));
  while (endpoint.requestCount == baseline) {
    if (DateTime.now().isAfter(startDeadline)) {
      throw StateError('the app never called the scripted endpoint');
    }
    await tick(tester, const Duration(milliseconds: 50));
  }
  await waitForNoStream(tester);
}

/// Polls until the reply finishes (Stop icon gone) or [seconds] elapse.
Future<void> waitForNoStream(WidgetTester tester, {int seconds = 60}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    await tick(tester, const Duration(milliseconds: 100));
    if (find.byIcon(Icons.stop_circle_outlined).evaluate().isEmpty) return;
  }
  throw StateError('the reply never finished streaming');
}

/// Polls until the error banner (with Retry) appears.
Future<void> waitForRetry(WidgetTester tester, {int seconds = 60}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    await tick(tester, const Duration(milliseconds: 200));
    if (find.widgetWithText(TextButton, 'Retry').evaluate().isNotEmpty) {
      return;
    }
  }
  throw StateError('the failure never surfaced a Retry');
}

Future<void> waitForText(WidgetTester tester, Pattern pattern,
    {int seconds = 60, ScriptedEndpoint? endpoint}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    await tick(tester, const Duration(milliseconds: 100));
    if (find.textContaining(pattern).evaluate().isNotEmpty) return;
  }
  final parts = ['text matching "$pattern" never appeared'];
  if (endpoint != null) {
    parts.add(
        'the endpoint saw ${endpoint.requestCount} request(s); last body: '
        '${endpoint.lastRequestBody}');
  }
  parts.add('on-screen text: ${visibleTexts(tester)}');
  throw StateError(parts.join('\n'));
}

/// Every rendered Text/RichText datum, for failure diagnostics.
List<String> visibleTexts(WidgetTester tester) {
  final texts = <String>[];
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    if (text.data != null && text.data!.isNotEmpty) texts.add(text.data!);
  }
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    final plain = rich.text.toPlainText();
    if (plain.isNotEmpty) texts.add(plain);
  }
  return texts;
}

/// True while the history drawer is on screen.
bool drawerIsOpen() => find.byType(Drawer).evaluate().isNotEmpty;

/// Opens the history drawer and waits for it to finish sliding in.
///
/// `ScaffoldState.openDrawer()` is idempotent: calling it while the drawer is
/// already open is harmless, so callers can re-assert the open state cheaply.
Future<void> openDrawer(WidgetTester tester) async {
  final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
  if (!scaffold.isDrawerOpen) {
    scaffold.openDrawer();
  }
  await settle(tester);
  if (!drawerIsOpen()) {
    throw StateError('the history drawer did not open; on-screen text: '
        '${visibleTexts(tester)}');
  }
}

/// Every conversation title the open drawer is showing.
List<String> drawerTileTitles(WidgetTester tester) {
  final titles = <String>[];
  for (final tile in tester.widgetList<ListTile>(
    find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(ListTile),
    ),
  )) {
    final title = tile.title;
    if (title is Text && title.data != null) titles.add(title.data!);
  }
  return titles;
}

/// Polls until [text] appears as a drawer tile (the list loads from storage
/// asynchronously, so opening alone is not enough). Re-opens the drawer if it
/// slid shut while polling, since a rebuild of the screen can dismiss it.
Future<void> waitForDrawerTile(WidgetTester tester, String text,
    {int seconds = 30}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    if (!drawerIsOpen()) {
      await openDrawer(tester);
    }
    if (find.descendant(
      of: find.byType(Drawer),
      matching: find.text(text),
    ).evaluate().isNotEmpty) {
      return;
    }
    await tick(tester, const Duration(milliseconds: 100));
  }
  throw StateError('the drawer never listed "$text"; '
      'drawer titles: ${drawerTileTitles(tester)}');
}

Future<void> startNewChat(WidgetTester tester) async {
  await openDrawer(tester);
  await tester.tap(find.text('New chat'));
  await settle(tester);
}

/// The rendered text of every assistant bubble currently on screen.
List<String> assistantBubbleTexts(WidgetTester tester) => [
      for (final bubble in tester.widgetList<MessageBubble>(
        find.byType(MessageBubble),
      ))
        if (!bubble.isMine) bubble.content,
    ];

/// True if any on-screen assistant bubble contains [text].
bool hasAssistantBubbleWith(WidgetTester tester, String text) =>
    assistantBubbleTexts(tester).any((content) => content.contains(text));

/// Message bodies as actually drawn, markdown consumed.
///
/// A user turn draws as one [SelectableText]; a rendered assistant reply draws
/// as one selectable block per markdown block, so this reads the text widgets
/// rather than `MessageBubble.content`. [assistantBubbleTexts] keeps reading
/// that raw text - a different question, and both are needed: storage whole,
/// screen formatted. Screen-wide needles should therefore be markup-specific.
List<String> renderedMessageTexts(WidgetTester tester) => [
      for (final widget in tester.widgetList(
        find.byWidgetPredicate((w) => w is RichText || w is SelectableText),
      ))
        if (widget is RichText)
          widget.text.toPlainText()
        else if (widget is SelectableText)
          widget.textSpan?.toPlainText() ?? widget.data ?? '',
    ];

/// True if any rendered text on screen contains [needle].
bool renderedTextContains(WidgetTester tester, String needle) =>
    renderedMessageTexts(tester).any((body) => body.contains(needle));

final timePattern = RegExp(r'^\d{2}:\d{2}$');

/// `HH:MM` labels currently rendered (the timestamp affordance).
List<String> timestampLabels(WidgetTester tester) => [
      for (final text in tester.widgetList<Text>(find.byType(Text)))
        if (text.data != null && timePattern.hasMatch(text.data!)) text.data!,
    ];
