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
  // URL/model come from durable settings, the key from the keystore.
  await container.read(profileProvider.notifier).loadStored();
  await container.read(conversationProvider.notifier).restoreMostRecent();

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
