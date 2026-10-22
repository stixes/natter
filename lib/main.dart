import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/chat_providers.dart';
import 'ui/chat_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();
  // URL/model come from plain settings, the key from the keystore.
  await container.read(profileProvider.notifier).loadStored();

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
