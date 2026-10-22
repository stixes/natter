import 'stream_delta.dart';

/// One streamed `chat/completions` answer in progress.
///
/// The phase machine is the placeholder affordance from design.md:
/// `Waiting` until the first text token, then `Thinking` while only reasoning
/// has arrived, then `Answering` as soon as answer text begins. A role-only or
/// empty delta does not advance the phase.
enum AssistantPhase { waiting, thinking, answering }

class AssistantDraft {
  AssistantDraft({
    this.phase = AssistantPhase.waiting,
    this.answer = '',
    this.reasoning = '',
  });

  AssistantPhase phase;
  String answer;
  String reasoning;

  bool get hasAnswerText => answer.isNotEmpty;

  /// Text to render while streaming: answer text once it has begun, otherwise
  /// nothing (the placeholder covers waiting/thinking). Reasoning is captured
  /// but never rendered mid-stream.
  String get visibleText => phase == AssistantPhase.answering ? answer : '';

  /// Applies one delta. Role-only and empty deltas are explicitly ignored so
  /// they cannot end the waiting state.
  void apply(StreamDelta delta) {
    if (!delta.isText) return;
    if (delta.hasReasoning) reasoning += delta.reasoning;
    if (delta.hasContent) answer += delta.content;
    if (answer.isNotEmpty) {
      phase = AssistantPhase.answering;
    } else {
      phase = AssistantPhase.thinking;
    }
  }

  /// Final answer text for the committed message.
  ///
  /// Blank-answer fallback: some qwen3 runs never emit the thinking-end
  /// marker, so the whole answer lands in reasoning and content stays empty.
  /// In that case the reasoning is displayed as the answer.
  String resolveFinalContent() =>
      answer.isEmpty && reasoning.isNotEmpty ? reasoning : answer;
}
