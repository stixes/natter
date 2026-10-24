import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:natter/data/chat_completions_client.dart';
import 'package:natter/domain/endpoint_profile.dart';
import 'package:natter/domain/chat_message.dart';

import 'support/test_support.dart';

/// A canned SSE fixture replayed by the fake client, chunked the way a real
/// gateway dribbles bytes out.
const sseFixture = '''
data: {"choices":[{"index":0,"delta":{"role":"assistant"}}]}

data: {"choices":[{"index":0,"delta":{"reasoning_content":"Let me think"}}]}

data: {"choices":[{"index":0,"delta":{"reasoning_content":" about 2+2"}}]}

data: {"choices":[{"index":0,"delta":{"content":"4"}}]}

data: [DONE]

data: {"choices":[{"index":0,"delta":{"content":"MUST NOT APPEAR"}}]}

''';

/// Response headers for the SSE stream, chunked at awkward boundaries so the
/// parser must reassemble lines split across chunks.
MockClient streamingClient({
  String body = sseFixture,
  int status = 200,
  List<int>? chunkSizes,
  void Function(http.BaseRequest request, String body)? onRequest,
}) {
  return MockClient((request) async {
    onRequest?.call(request, request.body);
    return http.Response(body, status, headers: {
      'content-type': 'text/event-stream',
    });
  });
}

void main() {
  const messages = [
    ChatMessage(role: ChatRole.user, content: 'what is 2+2?'),
  ];

  test('replays a canned SSE fixture into ordered deltas', () async {
    final client = ChatCompletionsClient(httpClient: streamingClient());

    final deltas = await client
        .stream(profile: testProfile, messages: messages)
        .toList();

    // The role-only delta is delivered but carries no text; reasoning and
    // answer deltas arrive in order; nothing after [DONE] is read.
    expect(deltas.map((d) => d.toString()).join(), isNotEmpty);
    expect(
      deltas.where((d) => d.isRoleOnly).length,
      1,
      reason: 'the role-only delta is classified, not dropped',
    );
    expect(
      deltas.where((d) => d.hasReasoning).map((d) => d.reasoning).toList(),
      ['Let me think', ' about 2+2'],
    );
    expect(
      deltas.where((d) => d.hasContent).map((d) => d.content).toList(),
      ['4'],
    );
    expect(
      deltas.any((d) => d.content.contains('MUST NOT APPEAR')),
      isFalse,
      reason: 'parsing stops at [DONE]',
    );
  });

  test('replays a fixture split into arbitrary byte chunks', () async {
    final bytes = utf8.encode(sseFixture);
    final client = ChatCompletionsClient(
      httpClient: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          _chunked(bytes, const [1, 3, 17, 64, 200]),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );

    final deltas = await client
        .stream(profile: testProfile, messages: messages)
        .toList();

    expect(
      deltas.where((d) => d.hasReasoning).map((d) => d.reasoning).join(),
      'Let me think about 2+2',
    );
    expect(
      deltas.where((d) => d.hasContent).map((d) => d.content).join(),
      '4',
    );
  });

  test('ignores keepalives, comments, and malformed chunks', () async {
    final client = ChatCompletionsClient(
      httpClient: streamingClient(
        body: '''
: keepalive ping

data:
data: this is not json
data: {"choices":[]}
data: {"choices":[{"index":0,"delta":{"content":"ok"}}]}
data: [DONE]

''',
      ),
    );

    final deltas = await client
        .stream(profile: testProfile, messages: messages)
        .toList();
    expect(deltas.map((d) => d.content).join(), 'ok');
  });

  test('sends model, stream flag, wire messages, and the bearer key', () async {
    http.BaseRequest? seen;
    String? seenBody;
    final client = ChatCompletionsClient(
      httpClient: streamingClient(
        onRequest: (request, body) {
          seen = request;
          seenBody = body;
        },
      ),
    );

    await client
        .stream(profile: testProfile, messages: const [
          ChatMessage(role: ChatRole.user, content: 'a'),
          ChatMessage(role: ChatRole.assistant, content: 'b'),
        ])
        .toList();

    expect(seen, isNotNull);
    expect(seen!.method, 'POST');
    expect(seen!.url.toString(), 'http://127.0.0.1:8080/v1/chat/completions');
    expect(seen!.headers['authorization'], 'Bearer sk-test-secret-value');
    expect(seen!.headers['accept'], 'text/event-stream');

    final payload = jsonDecode(seenBody!) as Map<String, Object?>;
    expect(payload['model'], 'qwen3-test');
    expect(payload['stream'], true);
    expect(payload['messages'], [
      {'role': 'user', 'content': 'a'},
      {'role': 'assistant', 'content': 'b'},
    ]);
  });

  test('an empty api key sends no authorization header at all', () async {
    // Local llama.cpp and llama-swap servers are the app's headline use case
    // and they accept unauthenticated requests.
    http.BaseRequest? seen;
    final client = ChatCompletionsClient(
      httpClient: streamingClient(onRequest: (request, _) => seen = request),
    );

    await client
        .stream(
          profile: const EndpointProfile(
            baseUrl: 'http://127.0.0.1:8080/v1',
            model: 'qwen3-test',
          ),
          messages: const [ChatMessage(role: ChatRole.user, content: 'a')],
        )
        .toList();

    expect(seen, isNotNull);
    expect(seen!.headers.containsKey('authorization'), isFalse,
        reason: 'no key means no Authorization header, not an empty bearer');
  });

  test('a base URL without a version path still resolves', () {
    expect(
      ChatCompletionsClient.completionsUri('http://host:8080').toString(),
      'http://host:8080/chat/completions',
    );
    expect(
      ChatCompletionsClient.completionsUri('https://openrouter.ai/api/v1/')
          .toString(),
      'https://openrouter.ai/api/v1/chat/completions',
    );
  });

  test('a non-200 response becomes a failure that omits the key', () async {
    final client = ChatCompletionsClient(
      httpClient: streamingClient(
        status: 401,
        body: '{"error":{"message":"Invalid API key passed"}}',
      ),
    );

    await expectLater(
      client.stream(profile: testProfile, messages: messages).toList(),
      throwsA(
        isA<ChatRequestFailure>()
            .having((f) => f.statusCode, 'statusCode', 401)
            .having((f) => f.message, 'message mentions status',
                contains('HTTP 401'))
            .having((f) => f.message.contains(testProfile.apiKey),
                'message never contains the key', isFalse),
      ),
    );
  });

  test('a transport failure becomes a user-facing failure', () async {
    final client = ChatCompletionsClient(
      httpClient: MockClient((request) async {
        throw http.ClientException('connection refused');
      }),
    );

    await expectLater(
      client.stream(profile: testProfile, messages: messages).toList(),
      throwsA(
        isA<ChatRequestFailure>()
            .having((f) => f.message, 'message', contains('Cannot reach')),
      ),
    );
  });

  test('cancelling the subscription stops reading the stream', () async {
    final controller = StreamController<List<int>>();
    final client = ChatCompletionsClient(
      httpClient: MockClient.streaming((request, body) async {
        return http.StreamedResponse(controller.stream, 200);
      }),
    );

    var upstreamCancelled = false;
    controller.onCancel = () => upstreamCancelled = true;

    final received = <String>[];
    final subscription = client
        .stream(profile: testProfile, messages: messages)
        .listen((delta) => received.add(delta.content));

    controller.add(utf8.encode(
      'data: {"choices":[{"index":0,"delta":{"content":"one"}}]}\n\n',
    ));
    await pumpEventQueue();
    expect(received, ['one']);

    // The app cancels without awaiting; the upstream must stop being read.
    final cancelled = subscription.cancel();
    controller.add(utf8.encode(
      'data: {"choices":[{"index":0,"delta":{"content":"two"}}]}\n\n',
    ));
    await pumpEventQueue();
    expect(received, ['one'], reason: 'nothing is delivered after cancel');

    await controller.close();
    await cancelled;
    expect(
      upstreamCancelled,
      isTrue,
      reason: 'cancelling must release the response stream',
    );
  });

  test('the api key never reaches a log line', () async {
    final logs = <String>[];
    final client = ChatCompletionsClient(httpClient: streamingClient());

    await runZoned(
      () async {
        final deltas = await client
            .stream(profile: testProfile, messages: messages)
            .toList();
        for (final delta in deltas) {
          print(delta); // ignore: avoid_print
        }
        print(testProfile); // ignore: avoid_print
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => logs.add(line),
      ),
    );

    expect(logs, isNotEmpty);
    expect(
      logs.any((line) => line.contains(testProfile.apiKey)),
      isFalse,
      reason: 'delta and profile logging must not include the key',
    );
  });

  test('a refused connection fails well under the connection budget', () async {
    final reserved = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = reserved.port;
    await reserved.close();
    final client = ChatCompletionsClient(
      connectionTimeout: const Duration(seconds: 1),
    );
    addTearDown(client.close);
    final stopwatch = Stopwatch()..start();
    await expectLater(
      client
          .stream(
            profile: EndpointProfile(
              baseUrl: 'http://127.0.0.1:$port/v1',
              model: 'm',
            ),
            messages: messages,
          )
          .toList(),
      throwsA(isA<ChatRequestFailure>()),
    );
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('a server that accepts but never responds hits the response-start '
      'bound', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      // Deliberately never complete the response: the client must give up.
    });
    final client = ChatCompletionsClient(
      responseStartTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(client.close);
    await expectLater(
      client
          .stream(
            profile: EndpointProfile(
              baseUrl: 'http://127.0.0.1:${server.port}/v1',
              model: 'm',
            ),
            messages: messages,
          )
          .toList(),
      throwsA(
        isA<ChatRequestFailure>().having(
          (f) => f.message,
          'message',
          'The endpoint did not respond.',
        ),
      ),
    );
  });

  test('a hung HTTP error body hits the response-start bound', () async {
    final controller = StreamController<List<int>>();
    addTearDown(controller.close);
    final client = ChatCompletionsClient(
      httpClient: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(controller.stream, 503);
      }),
      responseStartTimeout: const Duration(milliseconds: 100),
    );
    await expectLater(
      client.stream(profile: testProfile, messages: messages).toList(),
      throwsA(
        isA<ChatRequestFailure>().having(
          (f) => f.message,
          'message',
          'The endpoint did not respond.',
        ),
      ),
    );
  });

  test('a stalled stream hits the silence bound after some data', () async {
    final controller = StreamController<List<int>>();
    addTearDown(controller.close);
    final client = ChatCompletionsClient(
      httpClient: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(controller.stream, 200);
      }),
      silenceTimeout: const Duration(milliseconds: 100),
    );
    final received = <String>[];
    final future = client
        .stream(profile: testProfile, messages: messages)
        .listen((delta) => received.add(delta.content))
        .asFuture<void>();
    controller.add(utf8.encode(
      'data: {"choices":[{"index":0,"delta":{"content":"partial"}}]}\n\n',
    ));
    await pumpEventQueue();
    expect(received.join(), 'partial');
    await expectLater(
      future,
      throwsA(
        isA<ChatRequestFailure>()
            .having(
              (f) => f.message,
              'message',
              'The reply stopped arriving.',
            )
            .having((f) => f.isSilenceFailure, 'isSilenceFailure', isTrue),
      ),
    );
  });

  test('a keepalive line resets the silence bound', () async {
    final controller = StreamController<List<int>>();
    final keepalive = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!controller.isClosed) {
        controller.add(utf8.encode(': keepalive\n\n'));
      }
    });
    final finish = Timer(const Duration(milliseconds: 200), () {
      keepalive.cancel();
      controller.add(utf8.encode(
        'data: {"choices":[{"index":0,"delta":{"content":"done"}}]}\n\n',
      ));
      controller.add(utf8.encode('data: [DONE]\n\n'));
      controller.close();
    });
    addTearDown(() {
      keepalive.cancel();
      finish.cancel();
      controller.close();
    });
    final client = ChatCompletionsClient(
      httpClient: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(controller.stream, 200);
      }),
      silenceTimeout: const Duration(milliseconds: 100),
    );
    final received = <String>[];
    await client
        .stream(profile: testProfile, messages: messages)
        .forEach((delta) => received.add(delta.content));
    expect(received, ['done']);
  });

  test('budgets default to the documented constants and are injectable', () {
    expect(
      ChatCompletionsClient.defaultConnectionTimeout,
      const Duration(seconds: 15),
    );
    expect(
      ChatCompletionsClient.defaultResponseStartTimeout,
      const Duration(seconds: 120),
    );
    expect(
      ChatCompletionsClient.defaultSilenceTimeout,
      const Duration(seconds: 60),
    );

    final client = ChatCompletionsClient(
      connectionTimeout: const Duration(seconds: 1),
      responseStartTimeout: const Duration(seconds: 2),
      silenceTimeout: const Duration(seconds: 3),
    );
    addTearDown(client.close);
    expect(client.connectionTimeout, const Duration(seconds: 1));
    expect(client.responseStartTimeout, const Duration(seconds: 2));
    expect(client.silenceTimeout, const Duration(seconds: 3));
  });
}

Stream<List<int>> _chunked(List<int> bytes, List<int> sizes) async* {
  var offset = 0;
  var i = 0;
  while (offset < bytes.length) {
    final size = sizes[i % sizes.length];
    final end = offset + size > bytes.length ? bytes.length : offset + size;
    yield bytes.sublist(offset, end);
    offset = end;
    i++;
  }
}
