import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/endpoint_profile.dart';
import '../state/chat_providers.dart';

/// Minimal single-endpoint configuration: one base URL, one key, one model.
/// Values are pre-filled from profile state, so reopening the screen shows
/// what is currently in use.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  bool _revealKey = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider);
    _baseUrl = TextEditingController(text: profile.baseUrl);
    _apiKey = TextEditingController(text: profile.apiKey);
    _model = TextEditingController(text: profile.model);
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(profileProvider.notifier).save(
      EndpointProfile(
        baseUrl: _baseUrl.text,
        apiKey: _apiKey.text,
        model: _model.text,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Endpoint')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _baseUrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              helperText: 'e.g. http://192.0.2.10:8080/v1',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKey,
            obscureText: !_revealKey,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'API key',
              helperText: 'Optional: many local servers need none. Stored in '
                  'the Android keystore, never in history',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _revealKey ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _revealKey = !_revealKey),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _model,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Model',
              helperText: 'Exactly as the endpoint expects it',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
