import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A tiny key/value seam so tests can inspect *where* a value landed.
///
/// Two instances exist: a plain settings store (non-secret fields) and a
/// keystore-backed store (the API key). The repository routes values between
/// them; the API key must only ever reach the secure one.
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// Everything this store holds. Used by tests that assert a secret is not
  /// present in a non-secure location.
  Future<Map<String, String>> contents();
}

/// Plain settings location. Not persisted across restarts in this change -
/// the profiles change decides the durable settings home.
class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<Map<String, String>> contents() async => Map.of(_values);
}

/// Keystore-backed location for the API key.
class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> contents() => _storage.readAll();
}
