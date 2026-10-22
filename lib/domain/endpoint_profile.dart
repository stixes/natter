/// The degenerate one-endpoint form of the future profiles model: exactly one
/// base URL, one API key, one model name. Shaped like a profile so the
/// profiles change generalizes this instead of rewriting it.
class EndpointProfile {
  const EndpointProfile({
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  /// A key is not required. A local llama.cpp or llama-swap server usually
  /// needs none, and the client sends no `Authorization` header when the key is
  /// empty, so URL plus model is a usable endpoint.
  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  EndpointProfile copyWith({String? baseUrl, String? apiKey, String? model}) {
    return EndpointProfile(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
    );
  }

  /// Deliberately redacts the key: this must be safe to put in logs.
  @override
  String toString() =>
      'EndpointProfile(baseUrl: $baseUrl, model: $model, apiKey: <redacted>)';

  @override
  bool operator ==(Object other) =>
      other is EndpointProfile &&
      other.baseUrl == baseUrl &&
      other.apiKey == apiKey &&
      other.model == model;

  @override
  int get hashCode => Object.hash(baseUrl, apiKey, model);
}
