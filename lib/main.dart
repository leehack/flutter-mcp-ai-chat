import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Application Layer (Providers managed by SettingsService/Notifier)
import 'application/settings_providers.dart';
import 'domains/settings/data/settings_repository_impl.dart';
// Presentation Layer
import 'presentation/chat_screen.dart';
import 'presentation/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Create a temporary repository instance JUST for loading initial values
  final initialSettingsRepo = SettingsRepositoryImpl(prefs);

  // Load initial values directly using the temporary repository
  final initialApiKey = await initialSettingsRepo.getApiKey();
  // REMOVED: final initialShowCodeBlocks = await initialSettingsRepo.getShowCodeBlocks();
  final initialServerList = await initialSettingsRepo.getMcpServerList();

  runApp(
    ProviderScope(
      overrides: [
        // Provide the SharedPreferences instance
        sharedPreferencesProvider.overrideWithValue(prefs),
        // Provide the concrete repository implementation
        settingsRepositoryProvider.overrideWith(
          (ref) => SettingsRepositoryImpl(ref.watch(sharedPreferencesProvider)),
        ),
        // Override state providers with initially loaded values
        apiKeyProvider.overrideWith((ref) => initialApiKey),
        // REMOVED: showCodeBlocksProvider override
        // showCodeBlocksProvider.overrideWith((ref) => initialShowCodeBlocks),
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
        '/': (context) => const ChatScreen(), // From presentation layer
        '/settings':
            (context) => const SettingsScreen(), // From presentation layer
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
