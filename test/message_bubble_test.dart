import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natter/ui/message_bubble.dart';

Widget _app(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? ThemeData(),
  home: Scaffold(body: child),
);

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
        _app(
          const MessageBubble(content: 'hello', isMine: false),
        ),
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

    testWidgets('the time appears after the message text in widget order',
        (tester) async {
      await tester.pumpWidget(
        _app(
          MessageBubble(
            content: 'hello',
            isMine: false,
            createdAt: DateTime(2026, 1, 1, 23, 59),
          ),
        ),
      );

      final column = tester.widget<Column>(
        find.descendant(
          of: find.byType(MessageBubble),
          matching: find.byType(Column),
        ),
      );
      final children = column.children;
      expect(children.first, isA<SelectableText>());
      expect(children.last, isA<Text>());
      expect((children.last as Text).data, '23:59');
    });

    testWidgets('a committed bubble survives the largest text scale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2.0),
              ),
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
}
