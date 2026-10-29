import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/endpoint_profile.dart';
import '../domain/system_prompt.dart';
import '../state/chat_providers.dart';

/// Configuration for what the app talks to and how it answers: one base URL,
/// one key, one model, and the system prompt. Values are pre-filled from
/// state, so reopening the screen shows what is currently in use.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late final TextEditingController _systemPrompt;
  bool _revealKey = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider);
    _baseUrl = TextEditingController(text: profile.baseUrl);
    _apiKey = TextEditingController(text: profile.apiKey);
    _model = TextEditingController(text: profile.model);
    // Pre-filled with the prompt in effect, so the default shows as text and
    // an edited or cleared prompt shows what was saved.
    _systemPrompt = TextEditingController(
      text: ref.read(systemPromptProvider).fieldText,
    );
    // The initial enabled state needs no listener call: it follows the text
    // the field was just pre-filled with, and setState during initState
    // would be an error.
    _promptIsDefault = _systemPrompt.text == kDefaultSystemPrompt;
    _systemPrompt.addListener(_refreshResetEnabled);
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _systemPrompt.dispose();
    super.dispose();
  }

  /// Typing only updates the enabled state of Reset; the Save below is what
  /// commits an edit.
  void _refreshResetEnabled() {
    final isDefault = _systemPrompt.text == kDefaultSystemPrompt;
    if (isDefault != _promptIsDefault) {
      setState(() => _promptIsDefault = isDefault);
    }
  }

  bool _promptIsDefault = true;

  Future<void> _save() async {
    await ref.read(profileProvider.notifier).save(
      EndpointProfile(
        baseUrl: _baseUrl.text,
        apiKey: _apiKey.text,
        model: _model.text,
      ),
    );
    await ref.read(systemPromptProvider.notifier).save(_systemPrompt.text);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
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
          const SizedBox(height: 16),
          // minLines/maxLines: the field grows with the text and stops at
          // eight lines, scrolling internally, so the list does not stretch
          // without bound as the user types.
          TextField(
            controller: _systemPrompt,
            minLines: 3,
            maxLines: 8,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'System prompt',
              helperText: 'Sent before every chat. Leave empty to send none.',
              border: OutlineInputBorder(),
            ),
          ),
          // Reset only replaces the field text; the Save below commits it,
          // matching how every other field on this screen behaves. It sits in
          // focus order after the field and before Save.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _promptIsDefault
                ? null
                : () => _systemPrompt.text = kDefaultSystemPrompt,
              child: const Text('Reset to default'),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
