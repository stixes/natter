import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natter/data/chat_completions_client.dart';
import 'package:natter/data/key_value_store.dart';
import 'package:natter/domain/chat_message.dart';
import 'package:natter/domain/endpoint_profile.dart';
import 'package:natter/domain/stream_delta.dart';
import 'package:natter/state/chat_providers.dart';

class RecordedRequest {
  RecordedRequest(this.profile, this.messages);

  final EndpointProfile profile;
  final List<ChatMessage> messages;
}

/// Drives a reply stream by hand so cancel / error / retry / blank-answer
/// tests are deterministic.
class ScriptedChatService implements ChatStreamService {
  final requests = <RecordedRequest>[];
  final _controllers = <StreamController<StreamDelta>>[];

  @override
  Stream<StreamDelta> stream({
    required EndpointProfile profile,
    required List<ChatMessage> messages,
  }) {
    requests.add(RecordedRequest(profile, List.of(messages)));
    final controller = StreamController<StreamDelta>();
    _controllers.add(controller);
    return controller.stream;
  }

  void emit(int attempt, List<StreamDelta> deltas) {
    for (final delta in deltas) {
      _controllers[attempt].add(delta);
    }
  }

  void end(int attempt) {
    _controllers[attempt].close();
  }

  void fail(int attempt, Object error) {
    _controllers[attempt]
      ..addError(error)
      ..close();
  }
}

const testProfile = EndpointProfile(
  baseUrl: 'http://127.0.0.1:8080/v1',
  apiKey: 'sk-test-secret-value',
  model: 'qwen3-test',
);

/// A container wired for tests: scripted stream plus inspectable stores.
({ProviderContainer container, ScriptedChatService service, KeyValueStore settings, KeyValueStore secrets})
    createTestContainer() {
  final service = ScriptedChatService();
  final settings = InMemoryKeyValueStore();
  final secrets = InMemoryKeyValueStore();
  final container = ProviderContainer(
    overrides: [
      chatStreamServiceProvider.overrideWith((ref) => service),
      settingsStoreProvider.overrideWith((ref) => settings),
      secretStoreProvider.overrideWith((ref) => secrets),
    ],
  );
  addTearDown(container.dispose);
  return (
    container: container,
    service: service,
    settings: settings,
    secrets: secrets,
  );
}

/// Lets a test wait for the microtask/stream delivery that follows a manual
/// emit, without a real timer.
Future<void> settle() => Future<void>.delayed(Duration.zero);
