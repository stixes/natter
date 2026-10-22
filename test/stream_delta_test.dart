import 'package:flutter_test/flutter_test.dart';
import 'package:natter/domain/stream_delta.dart';

void main() {
  group('delta classification', () {
    test('answer text is classified as answer, not reasoning', () {
      final delta = parseCompletionDelta(
        '{"choices":[{"index":0,"delta":{"content":"token"}}]}',
      )!;
      expect(delta.content, 'token');
      expect(delta.reasoning, isEmpty);
      expect(delta.hasContent, isTrue);
      expect(delta.isRoleOnly, isFalse);
      expect(delta.isEmpty, isFalse);
    });

    test('reasoning is read from reasoning_content', () {
      final delta = parseCompletionDelta(
        '{"choices":[{"index":0,"delta":{"reasoning_content":"thinking"}}]}',
      )!;
      expect(delta.reasoning, 'thinking');
      expect(delta.hasReasoning, isTrue);
      expect(delta.hasContent, isFalse);
    });

    test('reasoning is read from reasoning', () {
      final delta = parseCompletionDelta(
        '{"choices":[{"index":0,"delta":{"reasoning":"thinking"}}]}',
      )!;
      expect(delta.reasoning, 'thinking');
      expect(delta.hasReasoning, isTrue);
    });

    test('reasoning_content wins when both field names are present', () {
      final delta = parseCompletionDelta(
        '{"choices":[{"index":0,"delta":{"reasoning_content":"llamacpp",'
            '"reasoning":"openrouter"}}]}',
      )!;
      expect(delta.reasoning, 'llamacpp');
    });

    test('empty reasoning_content falls through to reasoning', () {
      final delta = parseCompletionDelta(
        '{"choices":[{"index":0,"delta":{"reasoning_content":"",'
            '"reasoning":"openrouter"}}]}',
      )!;
      expect(delta.reasoning, 'openrouter');
    });

    test('a role-only delta carries no text and is classified role-only', () {
      final delta = parseCompletionDelta(
        '{"choices":[{"index":0,"delta":{"role":"assistant"}}]}',
      )!;
      expect(delta.isRoleOnly, isTrue);
      expect(delta.isText, isFalse);
      expect(delta.isEmpty, isFalse);
    });

    test('a role delta that also carries text is a text delta', () {
      final delta = parseCompletionDelta(
        '{"choices":[{"index":0,"delta":{"role":"assistant","content":"x"}}]}',
      )!;
      expect(delta.isRoleOnly, isFalse);
      expect(delta.isText, isTrue);
    });

    test('a delta with neither role nor text is empty', () {
      final delta = parseCompletionDelta(
        '{"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}',
      )!;
      expect(delta.isEmpty, isTrue);
      expect(delta.isRoleOnly, isFalse);
    });

    test('payloads with no text-bearing delta parse to null', () {
      expect(parseCompletionDelta('{"choices":[]}'), isNull);
      expect(parseCompletionDelta('{"usage":{"total_tokens":4}}'), isNull);
      expect(parseCompletionDelta('{not json'), isNull);
      expect(parseCompletionDelta('[]'), isNull);
    });
  });
}
