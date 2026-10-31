import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/key_value_store.dart';
import 'state/chat_providers.dart';
import 'ui/chat_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      settingsStoreProvider.overrideWithValue(
        SharedPreferencesKeyValueStore(preferences: preferences),
      ),
    ],
  );
  // URL/model come from durable settings, the key from the keystore. The
  // system prompt is plain settings too, loaded before runApp so the
  // settings screen never shows a value it is about to overwrite.
  await container.read(profileProvider.notifier).loadStored();
  await container.read(systemPromptProvider.notifier).loadStored();

  // Expired chats are gone before anything reads history. A storage failure
  // here must not stop startup; expiry simply waits for the next launch.
  try {
    await container
        .read(conversationRepositoryProvider)
        .deleteExpiredBefore(DateTime.now().subtract(const Duration(days: 90)));
  } catch (error) {
    debugPrint('Startup expiry cleanup failed: $error');
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const NatterApp(),
    ),
  );
}

class NatterApp extends StatelessWidget {
  const NatterApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6750A4);
    return MaterialApp(
      title: 'Natter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const ChatScreen(),
    );
  }
}
