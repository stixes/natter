import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natter/ui/message_bubble.dart';
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
}
