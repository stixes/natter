import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/chat_message.dart';
import '../domain/endpoint_profile.dart';
import '../domain/stream_delta.dart';

/// A failure surfaced to the chat screen. Its [message] is user-facing and is
/// built so that it can never carry the API key.
class ChatRequestFailure implements Exception {
  const ChatRequestFailure(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// The streaming request seam: the conversation controller depends on this,
/// never on `http` directly, so tests can drive streams deterministically.
abstract interface class ChatStreamService {
  Stream<StreamDelta> stream({
    required EndpointProfile profile,
    required List<ChatMessage> messages,
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
  ChatCompletionsClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

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

  @override
  Stream<StreamDelta> stream({
    required EndpointProfile profile,
    required List<ChatMessage> messages,
  }) async* {
    final request =
        http.Request('POST', completionsUri(profile.baseUrl))
          ..headers.addAll({
            'accept': 'text/event-stream',
            'content-type': 'application/json',
            if (profile.apiKey.isNotEmpty)
              'authorization': 'Bearer ${profile.apiKey}',
          })
          ..body =
              jsonEncode({
                'model': profile.model,
                'stream': true,
                'messages': messages.map((m) => m.toWireFormat()).toList(),
              });

    http.StreamedResponse response;
    try {
      response = await _http.send(request);
    } on http.ClientException catch (error) {
      throw ChatRequestFailure('Cannot reach the endpoint: ${error.message}');
    }

    if (response.statusCode >= 400) {
      final body = await response.stream.bytesToString();
      throw ChatRequestFailure(
        'Endpoint returned HTTP ${response.statusCode}: ${_excerpt(body)}',
        statusCode: response.statusCode,
      );
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    try {
      await for (final line in lines) {
        final data = sseData(line);
        if (data == null) continue;
        if (data == '[DONE]') return;
        final delta = parseCompletionDelta(data);
        if (delta == null) continue;
        yield delta;
      }
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
