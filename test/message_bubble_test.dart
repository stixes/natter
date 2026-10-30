import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natter/ui/message_bubble.dart';
import 'support/fake_clipboard.dart';
import 'support/test_support.dart';

Widget _app(Widget child, {ThemeData? theme, NavigatorObserver? observer}) =>
    MaterialApp(
      theme: theme ?? ThemeData(),
      navigatorObservers: [if (observer != null) observer],
      home: Scaffold(body: child),
    );

/// Counts routes the app pushes, so a test can prove a tap opened nothing.
class _RouteCountingObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

void main() {
  group('MessageBubble', () {
    testWidgets('a committed bubble shows the 24-hour time', (tester) async {
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: 'hello',
            isMine: false,
            createdAt: DateTime(2026, 1, 1, 9, 5),
          ),
        ),
      );

      expect(find.text('hello'), findsOneWidget);
      expect(find.text('09:05'), findsOneWidget);
    });

    testWidgets('a bubble without a time shows none', (tester) async {
      await tester.pumpWidget(
        _app(const MessageBubble(content: 'hello', isMine: false)),
      );

      expect(find.text('hello'), findsOneWidget);
      expect(find.textContaining(':'), findsNothing);
    });

    testWidgets('the time uses a theme on-container token', (tester) async {
      final theme = ThemeData();
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: 'hello',
            isMine: false,
            createdAt: DateTime(2026, 1, 1, 13, 7),
          ),
          theme: theme,
        ),
      );

      final timeText = tester.widget<Text>(find.text('13:07'));
      expect(timeText.style?.color, theme.colorScheme.onSurface);
    });

    testWidgets('the time appears after the message text in widget order', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: 'hello',
            isMine: false,
            createdAt: DateTime(2026, 1, 1, 23, 59),
          ),
        ),
      );

      final column =
          tester
              .widgetList<Column>(
                find.descendant(
                  of: find.byType(MessageBubble),
                  matching: find.byType(Column),
                ),
              )
              .first;
      final children = column.children;
      expect(
        renderedBlocks(tester, find.byType(MessageBubble)),
        contains('hello'),
      );
      expect(children.last, isA<Text>());
      expect((children.last as Text).data, '23:59');
    });

    testWidgets('a committed bubble survives the largest text scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          Builder(
            builder:
                (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(2.0)),
                  child: MessageBubble(
                    content: 'hello',
                    isMine: false,
                    createdAt: DateTime(2026, 1, 1, 9, 5),
                  ),
                ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('09:05'), findsOneWidget);
    });
  });

  group('MessageBubble renders an assistant reply', () {
    const reply = r'''## Title

A **bold** word and `inline` code.

- first
- second

```python
print("hi")
```
''';

    Finder bubble() => find.byType(MessageBubble);

    testWidgets('structure is rendered, and markup characters are gone', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const MessageBubble(content: reply, isMine: false)),
      );

      final shown = renderedBlocks(tester, bubble()).join('\n');
      expect(shown, contains('Title'));
      expect(shown, contains('first'));
      expect(shown, contains('second'));
      expect(shown, contains('print("hi")'));
      expect(shown, isNot(contains('##')));
      expect(shown, isNot(contains('**')));
      expect(shown, isNot(contains('- first')));
      expect(shown, isNot(contains('```')));
      expect(shown, isNot(contains('python')));
    });

    testWidgets('headings, emphasis, and code carry their styling', (
      tester,
    ) async {
      final theme = ThemeData();
      await tester.pumpWidget(
        _app(const MessageBubble(content: reply, isMine: false), theme: theme),
      );

      final spans = renderedSpans(tester, bubble());
      final paragraph = spans.firstWhere((s) => s.text == ' word and ');
      final heading = spans.firstWhere((s) => s.text == 'Title');
      expect(
        heading.style!.fontSize!,
        greaterThan(paragraph.style!.fontSize!),
        reason: 'a heading must read as a heading',
      );

      final emphasized = spans.firstWhere((s) => s.text == 'bold');
      expect(emphasized.style!.fontWeight, FontWeight.bold);
      expect(emphasized.style!.fontSize, paragraph.style!.fontSize);

      final inlineCode = spans.firstWhere((s) => s.text == 'inline');
      final codeBlock = spans.firstWhere((s) => s.text.contains('print("hi")'));
      expect(inlineCode.style!.fontFamily, 'monospace');
      expect(codeBlock.style!.fontFamily, 'monospace');
      expect(codeBlock.style!.color, theme.colorScheme.onSurface);
    });

    testWidgets('a table renders as rows, not pipe characters', (tester) async {
      await tester.pumpWidget(
        _app(
          const MessageBubble(
            content: '''| Name | Qty |
| --- | --- |
| Apple | 3 |''',
            isMine: false,
          ),
        ),
      );

      expect(find.byType(Table), findsOneWidget);
      final shown = renderedBlocks(tester, bubble()).join('\n');
      expect(shown, contains('Apple'));
      expect(shown, isNot(contains('|')));
      expect(shown, isNot(contains('---')));
    });

    testWidgets('a code line wider than the bubble scrolls sideways', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: '```python\n'
                'def a_signature_long_enough_to_exceed_the_width_of_the_bubble_'
                'and_keep_going_and_going_on_and_on_forever_and_ever(a, b, c):\n'
                '    return a + b + c\n'
                '```',
            isMine: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.ancestor(
        of: find.textContaining('a_signature_long_enough'),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);

      // The line is genuinely wider than the bubble, and a sideways drag
      // scrolls it instead of leaving the tail unreachable behind a clip.
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.axis, Axis.horizontal);
      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.pixels, 0);

      // The tail of the line sits past the bubble's right edge, and scrolling
      // brings it back inside instead of leaving it behind a clip.
      final code = find.textContaining('and_ever');
      final edge = tester.getTopRight(scrollable).dx;
      expect(tester.getTopRight(code).dx, greaterThan(edge));

      // Driven by the scroll position rather than a swipe: the swipe is the
      // on-device round's business, this test owns reachability.
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(position.pixels, position.maxScrollExtent);
      expect(tester.getTopRight(code).dx, lessThanOrEqualTo(edge + 0.5));
    });

    testWidgets('a committed code block keeps its sideways scroll', (
      tester,
    ) async {
      // The block is taken over for the copy button, so the scroll it used to
      // have is reproduced here - which is why this pins the same behaviour
      // the draft case above pins, with the button present.
      FakeClipboard(tester).install();
      final source = '```python\n'
          'def a_signature_long_enough_to_exceed_the_width_of_the_bubble_'
          'and_keep_going_and_going_on_and_on_forever_and_ever(a, b, c):\n'
          '```';
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: source,
            isMine: false,
            copyText: source,
            createdAt: DateTime(2026, 1, 1, 9, 5),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.ancestor(
        of: find.textContaining('a_signature_long_enough'),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.axis, Axis.horizontal);
      expect(position.maxScrollExtent, greaterThan(0));

      // The button sits beside the text, not over it: the block's whole width
      // stays draggable.
      final button = find.byTooltip('Copy code block');
      expect(button, findsOneWidget);
      expect(
        tester.getRect(button).top,
        lessThanOrEqualTo(
          tester.getTopLeft(find.textContaining('a_signature_long_enough')).dy,
        ),
        reason: 'the button row sits above the code, never on top of it',
      );
    });

    testWidgets('a block button copies its own block, indentation and all', (
      tester,
    ) async {
      final clipboard = FakeClipboard(tester)..install();
      const source = 'A short prose line.\n\n```python\n'
          'def total(a, b):\n'
          '    return a + b\n'
          '```';
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: source,
            isMine: false,
            copyText: source,
            createdAt: DateTime(2026, 1, 1, 9, 5),
          ),
        ),
      );

      // The block's button is named to a screen reader too.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Copy code block',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Copy code block'));
      await tester.pump();

      final copied = await clipboard.read();
      // The block only, with its leading indentation intact and no trailing
      // blank line: what a paste into an editor should produce.
      expect(copied, 'def total(a, b):\n    return a + b');
      expect(copied, isNot(contains('prose')));
      // And the turn's own control is a different thing: it copies the whole.
      expect(
        find.byTooltip('Copy message'),
        findsOneWidget,
        reason: 'both controls coexist on one committed turn',
      );
    });

    testWidgets('two blocks each carry their own button, and the tapped one ' 'is the one copied', (tester) async {
      final clipboard = FakeClipboard(tester)..install();
      const source =
          'Text before.\n\n```python\nfirst_one()\n```\n\nAnd between.\n\n'
          '```python\ndef second():\n    return 2\n```';
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: source,
            isMine: false,
            copyText: source,
            createdAt: DateTime(2026, 1, 1, 9, 5),
          ),
        ),
      );

      expect(find.byTooltip('Copy code block'), findsNWidgets(2));

      await tester.tap(find
          .byTooltip('Copy code block')
          .first);
      await tester.pump();

      final copied = await clipboard.read();
      expect(copied, 'first_one()');
      expect(copied, isNot(contains('second')));
      expect(copied, isNot(contains('between')));
    });

    testWidgets('a reply with no fenced block carries no block control', (
      tester,
    ) async {
      FakeClipboard(tester).install();
      const source = '# Title\n\n- one\n\n> a quoted line\n';
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: source,
            isMine: false,
            copyText: source,
            createdAt: DateTime(2026, 1, 1, 9, 5),
          ),
        ),
      );

      expect(find.byTooltip('Copy code block'), findsNothing);
      // The turn's own control is still there, and it is the only one.
      expect(find.byIcon(Icons.content_copy), findsOneWidget);
    });

    testWidgets('a second tap writes the clipboard again', (tester) async {
      final clipboard = FakeClipboard(tester)..install();
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: 'first',
            isMine: false,
            copyText: 'first',
            createdAt: DateTime(2026, 1, 1, 9, 5),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Copy message'));
      await tester.pump();
      // The confirmation clears, then the control works again.
      await tester.pump(const Duration(milliseconds: 1200));

      await tester.tap(find.byTooltip('Copy message'));
      await tester.pump();

      expect(clipboard.writes, 2);
      expect(await clipboard.read(), 'first');
    });

    testWidgets('a streaming partial block shows no button at all', (
      tester,
    ) async {
      FakeClipboard(tester).install();
      // The draft shape: an unterminated fence, no committed text to copy.
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: '```python\ndef total(a, b):\n',
            isMine: false,
            placeholderLabel: 'Thinking',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Copy code block'), findsNothing);
      expect(find.byIcon(Icons.content_copy), findsNothing);
      // The block still renders, scrolled rather than wrapped.
      expect(
        find.ancestor(
          of: find.textContaining('def total'),
          matching: find.byType(Scrollable),
        ),
        findsWidgets,
      );
    });

    testWidgets('the block stays selectable text the way reply-rendering says', (
      tester,
    ) async {
      FakeClipboard(tester).install();
      const source = '```text\nhello selectable world\n```';
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: source,
            isMine: false,
            copyText: source,
            createdAt: DateTime(2026, 1, 1, 9, 5),
          ),
        ),
      );

      final code = find.textContaining('hello selectable world');
      final selectable = find.ancestor(
        of: code,
        matching: find.byType(SelectableText),
      );
      expect(selectable, findsOneWidget);
      // The copy button is a separate tap target, and it does not cover the
      // text it copies - so a press over code text is still a press over text.
      expect(
        tester
            .getRect(selectable)
            .intersect(tester.getRect(find.byTooltip('Copy code block')))
            .isEmpty,
        isTrue,
      );
    });

    testWidgets('a blockquote renders as a quoted block', (tester) async {
      await tester.pumpWidget(
        _app(
          const MessageBubble(
            content: 'Before.\n\n> A remembered line.\n\nAfter.',
            isMine: false,
          ),
        ),
      );

      final shown = renderedBlocks(tester, bubble()).join('\n');
      expect(shown, contains('A remembered line.'));
      expect(shown, isNot(contains('>')));

      final quote = tester
          .widgetList<DecoratedBox>(
            find.descendant(of: bubble(), matching: find.byType(DecoratedBox)),
          )
          .where(
            (d) =>
                d.decoration is BoxDecoration &&
                (d.decoration as BoxDecoration).border is Border &&
                ((d.decoration as BoxDecoration).border as Border).left.width >
                    0,
          );
      expect(quote, isNotEmpty);
    });

    testWidgets('a link renders as a link but does nothing when tapped', (
      tester,
    ) async {
      final observer = _RouteCountingObserver();
      await tester.pumpWidget(
        _app(
          const MessageBubble(
            content: '[the docs](https://example.invalid/docs)',
            isMine: false,
          ),
          observer: observer,
        ),
      );

      final shown = renderedBlocks(tester, bubble()).join('\n');
      expect(shown, contains('the docs'));
      expect(shown, isNot(contains('https://')));
      expect(shown, isNot(contains('](')));
      final link = renderedSpans(
        tester,
        bubble(),
      ).firstWhere((s) => s.text == 'the docs');
      expect(link.style!.decoration, TextDecoration.underline);

      // The app's own home route already counts as a push; what matters is that
      // the tap adds none.
      final pushedBefore = observer.pushes;
      await tester.tap(bubble(), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        observer.pushes,
        pushedBefore,
        reason: 'an inert link must open nothing',
      );
      expect(
        renderedBlocks(tester, bubble()).join('\n'),
        shown,
        reason: 'a tapped reply must not change',
      );

      // Inert, not dead: the link text is still selectable text.
      final selectable = tester
          .widgetList<SelectableText>(
            find.descendant(
              of: bubble(),
              matching: find.byType(SelectableText),
            ),
          )
          .where(
            (w) => w.textSpan?.toPlainText().contains('the docs') ?? false,
          );
      expect(selectable, isNotEmpty);
    });

    testWidgets('an image reference shows alt text, never a fetched image', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const MessageBubble(
            content: 'See ![diagram](https://example.invalid/arch.png) below.',
            isMine: false,
          ),
        ),
      );

      final shown = renderedBlocks(tester, bubble()).join('\n');
      expect(shown, contains('diagram'));
      expect(shown, isNot(contains('example.invalid')));
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('an image with no alt text shows a marker', (tester) async {
      await tester.pumpWidget(
        _app(
          const MessageBubble(
            content:
                'An architecture diagram: ![](https://example.invalid/arch.png)',
            isMine: false,
          ),
        ),
      );

      final shown = renderedBlocks(tester, bubble()).join('\n');
      expect(shown, contains('[image]'));
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a user turn stays verbatim', (tester) async {
      const typed = '10 * 5 = 50\n# Notes\n- [ ] **ship it**\n```';
      await tester.pumpWidget(
        _app(const MessageBubble(content: typed, isMine: true)),
      );

      expect(renderedBlocks(tester, bubble()), [typed]);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.byType(Table), findsNothing);
    });

    testWidgets('a rendered reply survives the largest text scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          Builder(
            builder:
                (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(3.0)),
                  child: SingleChildScrollView(
                    child: MessageBubble(content: reply, isMine: false),
                  ),
                ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(renderedBlocks(tester, bubble()).join('\n'), contains('Title'));
    });

    testWidgets(
      'a heading, list, table, and long code line survive a large font on a '
      'narrow surface',
      (tester) async {
        tester.view.physicalSize = const Size(360, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        const dense = r'''## Steps

1. open it
2. run it

| Step | Result |
| --- | --- |
| open | ok |
| run | ok |

```text
echo "a line long enough to exceed the width of a narrow bubble on a phone"
```
''';

        await tester.pumpWidget(
          _app(
            Builder(
              builder:
                  (context) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(2.0)),
                    child: SingleChildScrollView(
                      child: MessageBubble(content: dense, isMine: false),
                    ),
                  ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        final shown = renderedBlocks(tester, bubble()).join('\n');
        expect(shown, contains('Steps'));
        expect(shown, contains('open it'));
        expect(shown, contains('Result'));
        expect(
          shown,
          contains('a line long enough to exceed the width of a narrow bubble'),
          reason: 'a long code line may scroll, but none of it may be lost',
        );
      },
    );

    testWidgets('a wide table on a narrow surface does not overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          const MessageBubble(
            content: '''| Column one | Column two | Column three | Column four |
| --- | --- | --- | --- |
| a fairly long cell | another long cell | and a third | fourth |''',
            isMine: false,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(Table), findsOneWidget);
    });

    testWidgets('a very large reply scrolls inside the transcript', (
      tester,
    ) async {
      final longReply = List.generate(
        60,
        (i) => '## Section $i\n\nSome **text** for section $i.\n',
      ).join('\n');
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: MessageBubble(content: longReply, isMine: false),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        renderedBlocks(tester, bubble()).join('\n'),
        contains('Section 59'),
      );
    });
  });

  group('copy control on a committed turn', () {
    Finder copyBubble() => find.byType(MessageBubble);

    const source =
        'Some **text** with `code` and a line:\n\n```python\nprint("hi")\n```\n';
    const typed = 'What is 10 * 5?\n\n# Notes\n- [ ] keep the hashes';

    testWidgets('a committed turn offers a labelled copy control', (
      tester,
    ) async {
      FakeClipboard(tester).install();
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: 'hello',
            isMine: false,
            copyText: 'hello',
            createdAt: DateTime(2026, 1, 1, 9, 5),
          ),
        ),
      );

      expect(find.byIcon(Icons.content_copy), findsOneWidget);
      expect(find.byTooltip('Copy message'), findsOneWidget);
      // A plain icon control would miss the 48 dp target the guidelines ask for.
      final target = tester.getSize(find.byType(IconButton));
      expect(target.width, greaterThanOrEqualTo(48));
      expect(target.height, greaterThanOrEqualTo(48));
    });

    testWidgets('a turn with no copy text offers no control at all', (
      tester,
    ) async {
      FakeClipboard(tester).install();
      // The in-flight shape: text has arrived, the reply is not committed.
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: 'Hel',
            isMine: false,
            placeholderLabel: 'Thinking',
          ),
        ),
      );

      expect(find.byIcon(Icons.content_copy), findsNothing);
      expect(find.byTooltip('Copy message'), findsNothing);
    });

    testWidgets('the control sits beside the timestamp, not over the text', (
      tester,
    ) async {
      FakeClipboard(tester).install();
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: 'hello',
            isMine: false,
            copyText: 'hello',
            createdAt: DateTime(2026, 1, 1, 9, 5),
          ),
        ),
      );

      final row = find.descendant(
        of: find.byType(MessageBubble),
        matching: find.byType(Row),
      );
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('09:05')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.byIcon(Icons.content_copy),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the control carries the bubble ink token, not a raw grey', (
      tester,
    ) async {
      FakeClipboard(tester).install();
      final theme = ThemeData();
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: 'hello',
            isMine: false,
            copyText: 'hello',
            createdAt: DateTime(2026, 1, 1, 9, 5),
          ),
          theme: theme,
        ),
      );

      expect(
        tester.widget<IconButton>(find.byType(IconButton)).color,
        theme.colorScheme.onSurface,
      );

      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: 'hello',
            isMine: true,
            copyText: 'hello',
            createdAt: DateTime(2026, 1, 1, 9, 5),
          ),
          theme: theme,
        ),
      );

      expect(
        tester.widget<IconButton>(find.byType(IconButton)).color,
        theme.colorScheme.onPrimaryContainer,
      );
    });

    testWidgets('a tap copies an assistant turn in its markdown source', (
      tester,
    ) async {
      final clipboard = FakeClipboard(tester)..install();
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: source,
            isMine: false,
            copyText: source,
            createdAt: DateTime(2026, 1, 1, 9, 5),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Copy message'));
      await tester.pump();

      final copied = await clipboard.read();
      expect(copied, source);
      // The rendering consumed the markup; the clipboard must not have.
      expect(
        renderedBlocks(tester, copyBubble()).join('\n'),
        isNot(contains('**')),
      );
      expect(copied, contains('**text**'));
      expect(copied, contains('print("hi")'));
    });

    testWidgets('a tap copies a user turn verbatim', (tester) async {
      final clipboard = FakeClipboard(tester)..install();
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: typed,
            isMine: true,
            copyText: typed,
            createdAt: DateTime(2026, 1, 1, 9, 5),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.pump();

      expect(await clipboard.read(), typed);
    });

    testWidgets('a copy of the blank fallback copies the text that is shown', (
      tester,
    ) async {
      final clipboard = FakeClipboard(tester)..install();
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: '(no answer)',
            isMine: false,
            copyText: '(no answer)',
            createdAt: DateTime(2026, 1, 1, 9, 5),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.pump();

      expect(await clipboard.read(), '(no answer)');
    });

    testWidgets('the copy is confirmed in place, then clears after a count', (
      tester,
    ) async {
      FakeClipboard(tester).install();
      final observer = _RouteCountingObserver();
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: 'hello',
            isMine: false,
            copyText: 'hello',
            createdAt: DateTime(2026, 1, 1, 9, 5),
          ),
          observer: observer,
        ),
      );

      final pushedBefore = observer.pushes;
      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.pump();

      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.content_copy), findsNothing);

      // Nothing else happened: no route, no surface to dismiss.
      expect(observer.pushes, pushedBefore);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(renderedBlocks(tester, copyBubble()), contains('hello'));

      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byIcon(Icons.content_copy), findsOneWidget);
    });

    testWidgets('the copy is announced to a screen reader', (tester) async {
      FakeClipboard(tester).install();
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: 'hello',
            isMine: false,
            copyText: 'hello',
            createdAt: DateTime(2026, 1, 1, 9, 5),
          ),
        ),
      );

      Finder announced(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.liveRegion == true &&
            widget.properties.label == label,
      );
      // Before the tap the node names the action it offers, and says it is a
      // button - a tooltip alone does not reach the Android tree.
      final idle = announced('Copy message');
      expect(idle, findsOneWidget);
      expect(tester.widget<Semantics>(idle).properties.button, isTrue);
      expect(announced('Copied'), findsNothing);

      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.pump();

      expect(announced('Copied'), findsOneWidget);
      expect(announced('Copy message'), findsNothing);
    });

    testWidgets('the largest text scale still reaches the copy control', (
      tester,
    ) async {
      FakeClipboard(tester).install();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(3.0)),
              child: MessageBubble(
                content: 'hello there',
                isMine: false,
                copyText: 'hello there',
                createdAt: DateTime(2026, 1, 1, 9, 5),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.content_copy), findsOneWidget);
      expect(
        tester.getSize(find.byType(IconButton)).width,
        greaterThanOrEqualTo(48),
      );
    });
  });
}
