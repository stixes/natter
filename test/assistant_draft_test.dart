import 'package:flutter_test/flutter_test.dart';
import 'package:natter/domain/assistant_draft.dart';
import 'package:natter/domain/stream_delta.dart';

void main() {
  group('placeholder state machine', () {
    test('starts in Waiting and stays there on a role-only delta', () {
      final draft = AssistantDraft();
      expect(draft.phase, AssistantPhase.waiting);

      draft.apply(const StreamDelta(hasRole: true));
      expect(
        draft.phase,
        AssistantPhase.waiting,
        reason: 'a role-only delta must not end the waiting state',
      );
    });

    test('an empty delta does not advance the state', () {
      final draft = AssistantDraft()..apply(const StreamDelta());
      expect(draft.phase, AssistantPhase.waiting);
    });

    test('first reasoning token moves Waiting to Thinking', () {
      final draft = AssistantDraft()
        ..apply(const StreamDelta(hasRole: true))
        ..apply(const StreamDelta(reasoning: 'pondering'));
      expect(draft.phase, AssistantPhase.thinking);
      expect(draft.visibleText, isEmpty, reason: 'reasoning is not rendered');
    });

    test('first answer token moves Waiting straight to answering', () {
      final draft = AssistantDraft()..apply(const StreamDelta(content: 'Hi'));
      expect(draft.phase, AssistantPhase.answering);
      expect(draft.visibleText, 'Hi');
    });

    test('Thinking moves to answering when answer text begins', () {
      final draft = AssistantDraft()
        ..apply(const StreamDelta(reasoning: 'thinking '))
        ..apply(const StreamDelta(content: 'answer'));
      expect(draft.phase, AssistantPhase.answering);
      expect(draft.visibleText, 'answer');
    });

    test('reasoning is captured but excluded from the answer text', () {
      final draft = AssistantDraft()
        ..apply(const StreamDelta(reasoning: 'secret chain of thought '))
        ..apply(const StreamDelta(content: 'the answer'));

      expect(draft.reasoning, 'secret chain of thought ');
      expect(draft.answer, 'the answer');
      expect(draft.visibleText, 'the answer');
      expect(draft.resolveFinalContent(), 'the answer');
    });

    test('blank-answer fallback: empty content with reasoning resolves to it',
        () {
      final draft = AssistantDraft()
        ..apply(const StreamDelta(reasoning: 'the whole answer landed here'));
      expect(draft.answer, isEmpty);
      expect(draft.resolveFinalContent(), 'the whole answer landed here');
    });

    test('no fallback when both are empty', () {
      expect(AssistantDraft().resolveFinalContent(), isEmpty);
    });
  });
}
