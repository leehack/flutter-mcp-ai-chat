import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'application/settings_providers.dart';
import 'domains/settings/data/settings_repository_impl.dart';
import 'presentation/chat_screen.dart';
import 'presentation/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final initialSettingsRepo = SettingsRepositoryImpl(prefs);
  final initialApiKey = await initialSettingsRepo.getApiKey();
  final initialServerList = await initialSettingsRepo.getMcpServerList();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        settingsRepositoryProvider.overrideWith(
          (ref) => SettingsRepositoryImpl(ref.watch(sharedPreferencesProvider)),
        ),
        apiKeyProvider.overrideWith((ref) => initialApiKey),
        mcpServerListProvider.overrideWith((ref) => initialServerList),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemini Chat Desktop (Refactored)',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: ThemeMode.system,
      initialRoute: '/',
      routes: {
        '/': (context) => const ChatScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
