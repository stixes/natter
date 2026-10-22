import '../domain/endpoint_profile.dart';
import 'key_value_store.dart';

/// Stores the single endpoint config, splitting it by sensitivity:
/// base URL and model are ordinary settings, the API key goes only to secure
/// storage. Conversation content is never written here.
class ProfileRepository {
  ProfileRepository({required this.settings, required this.secrets});

  final KeyValueStore settings;
  final KeyValueStore secrets;

  static const baseUrlField = 'endpoint.baseUrl';
  static const modelField = 'endpoint.model';
  static const apiKeyField = 'endpoint.apiKey';

  Future<EndpointProfile> load() async {
    return EndpointProfile(
      baseUrl: await settings.read(baseUrlField) ?? '',
      model: await settings.read(modelField) ?? '',
      apiKey: await secrets.read(apiKeyField) ?? '',
    );
  }

  Future<void> save(EndpointProfile profile) async {
    await settings.write(baseUrlField, profile.baseUrl.trim());
    await settings.write(modelField, profile.model.trim());
    final key = profile.apiKey.trim();
    if (key.isEmpty) {
      await secrets.delete(apiKeyField);
    } else {
      await secrets.write(apiKeyField, key);
    }
  }
}
