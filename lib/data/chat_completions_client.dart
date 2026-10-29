import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../domain/chat_message.dart';
import '../domain/endpoint_profile.dart';
import '../domain/stream_delta.dart';

/// A failure surfaced to the chat screen. Its [message] is user-facing and is
/// built so that it can never carry the API key.
class ChatRequestFailure implements Exception {
  const ChatRequestFailure(
    this.message, {
    this.statusCode,
    this.isSilenceFailure = false,
  });

  final String message;
  final int? statusCode;

  /// True when the failure came from the silence bound on an open stream, so
  /// the controller can keep answer text that already reached the screen.
  final bool isSilenceFailure;

  @override
  String toString() => message;
}

/// The streaming request seam: the conversation controller depends on this,
/// never on `http` directly, so tests can drive streams deterministically.
abstract interface class ChatStreamService {
  /// [systemPrompt] is the prompt in effect at send time; an empty string
  /// means no system message. It is a request parameter, never a
  /// [ChatMessage] — the prompt must not be able to reach conversation
  /// storage (see design.md).
  Stream<StreamDelta> stream({
    required EndpointProfile profile,
    required List<ChatMessage> messages,
    String systemPrompt = '',
  });
}

/// Extracts the payload of an SSE `data:` line, or null for comments,
/// keepalives, and non-data fields.
String? sseData(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith(':')) return null; // comment / keepalive
  if (!trimmed.startsWith('data:')) return null; // event:, id:, retry:
  return trimmed.substring(5).trim();
}

/// OpenAI-compatible `chat/completions` over SSE using `http` only.
///
/// No SDK: the dialect differences (reasoning field naming, keepalives,
/// malformed chunks) must stay visible and handled here explicitly.
class ChatCompletionsClient implements ChatStreamService {
  ChatCompletionsClient({
    http.Client? httpClient,
    this.connectionTimeout = defaultConnectionTimeout,
    this.responseStartTimeout = defaultResponseStartTimeout,
    this.silenceTimeout = defaultSilenceTimeout,
  }) : _http = httpClient ?? _createClient(connectionTimeout);

  /// Bounds DNS + TCP + TLS for a request. A mistyped or black-holed host
  /// never reaches the response phase, so this is what makes the socket
  /// layer deterministic.
  static const Duration defaultConnectionTimeout = Duration(seconds: 15);

  /// Bounds the wait for response headers. Generous enough for a cold local
  /// model load (measured at ~12.3 s on the dev llama-swap), and still finite.
  static const Duration defaultResponseStartTimeout = Duration(seconds: 120);

  /// Bounds silence once the stream is open. Any line resets it, including
  /// SSE comments and keepalives.
  static const Duration defaultSilenceTimeout = Duration(seconds: 60);

  final http.Client _http;

  /// Socket-phase budget; only used when this client creates its own client.
  final Duration connectionTimeout;

  /// Budget for response headers and for the HTTP >= 400 error body.
  final Duration responseStartTimeout;

  /// Per-event budget once the SSE stream is open.
  final Duration silenceTimeout;

  /// Closes the underlying HTTP client. The provider owns one long-lived
  /// instance per app and closes it on dispose.
  void close() => _http.close();

  /// Accepts a base URL with or without a trailing slash and with or without
  /// a trailing `/v1` (or a full `/chat/completions` URL).
  static Uri completionsUri(String baseUrl) {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/chat/completions')) return Uri.parse(base);
    return Uri.parse('$base/chat/completions');
  }

  static http.Client _createClient(Duration connectionTimeout) {
    final httpClient = HttpClient()..connectionTimeout = connectionTimeout;
    return IOClient(httpClient);
  }

  @override
  Stream<StreamDelta> stream({
    required EndpointProfile profile,
    required List<ChatMessage> messages,
    String systemPrompt = '',
  }) async* {
    final request =
        http.Request('POST', completionsUri(profile.baseUrl))
          ..headers.addAll({
            'accept': 'text/event-stream',
            'content-type': 'application/json',
            if (profile.apiKey.isNotEmpty)
              'authorization': 'Bearer ${profile.apiKey}',
          })
          ..body = jsonEncode({
            'model': profile.model,
            'stream': true,
            'messages': [
              // The system prompt rides ahead of the conversation as one
              // wire-level message; it never becomes a ChatMessage.
              if (systemPrompt.isNotEmpty) {
                'role': 'system',
                'content': systemPrompt,
              },
              ...messages.map((m) => m.toWireFormat()),
            ],
          });

    http.StreamedResponse response;
    try {
      response = await _http.send(request).timeout(responseStartTimeout);
    } on TimeoutException {
      throw const ChatRequestFailure('The endpoint did not respond.');
    } on http.ClientException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('timed out') || message.contains('timeout')) {
        throw const ChatRequestFailure('The endpoint did not respond.');
      }
      throw ChatRequestFailure('Cannot reach the endpoint: ${error.message}');
    }

    if (response.statusCode >= 400) {
      String body;
      try {
        body = await response.stream
            .bytesToString()
            .timeout(responseStartTimeout);
      } on TimeoutException {
        throw const ChatRequestFailure('The endpoint did not respond.');
      }
      throw ChatRequestFailure(
        'Endpoint returned HTTP ${response.statusCode}: ${_excerpt(body)}',
        statusCode: response.statusCode,
      );
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(silenceTimeout);

    try {
      await for (final line in lines) {
        final data = sseData(line);
        if (data == null) continue;
        if (data == '[DONE]') return;
        final delta = parseCompletionDelta(data);
        if (delta == null) continue;
        yield delta;
      }
    } on TimeoutException {
      throw const ChatRequestFailure(
        'The reply stopped arriving.',
        isSilenceFailure: true,
      );
    } on http.ClientException catch (error) {
      throw ChatRequestFailure('The stream failed: ${error.message}');
    } on FormatException {
      throw const ChatRequestFailure('The endpoint sent malformed data.');
    }
  }

  static String _excerpt(String body) {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= 240) return flat;
    return '${flat.substring(0, 240)}...';
  }
}
