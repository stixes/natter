import 'package:flutter_test/flutter_test.dart';
import 'package:natter/domain/endpoint_profile.dart';

void main() {
  group('isConfigured', () {
    test('a base URL and a model are enough - local servers often need no key',
        () {
      const profile = EndpointProfile(
        baseUrl: 'http://192.0.2.10:8080/v1',
        model: 'qwen3-14b',
      );
      expect(profile.isConfigured, isTrue);
    });

    test('a key, when present, is part of the profile', () {
      const profile = EndpointProfile(
        baseUrl: 'http://host/v1',
        apiKey: 'sk-something',
        model: 'm',
      );
      expect(profile.isConfigured, isTrue);
      expect(profile.apiKey, 'sk-something');
    });

    test('a missing base URL leaves the endpoint unconfigured', () {
      expect(const EndpointProfile(model: 'm').isConfigured, isFalse);
    });

    test('a missing model leaves the endpoint unconfigured', () {
      expect(const EndpointProfile(baseUrl: 'http://host/v1').isConfigured,
          isFalse);
    });

    test('whitespace alone does not count as configured', () {
      const profile = EndpointProfile(baseUrl: '   ', model: '  ');
      expect(profile.isConfigured, isFalse);
    });
  });

  test('toString redacts the key so the profile is safe to log', () {
    const profile = EndpointProfile(
      baseUrl: 'http://host/v1',
      apiKey: 'sk-do-not-log-me',
      model: 'm',
    );
    expect(profile.toString(), isNot(contains('sk-do-not-log-me')));
  });
}
