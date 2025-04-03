// lib/main.dart (Modified for Pre-loading Settings with isActive)
import 'dart:convert'; // For JSON decoding

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_screen.dart';
import 'mcp_server_config.dart'; // Import updated config class
import 'settings_screen.dart';
import 'settings_service.dart'; // Import service and providers

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Load initial values directly from prefs
  final initialApiKey = prefs.getString(apiKeyStorageKey);
  final initialShowCodeBlocks = prefs.getBool(showCodeBlocksKey) ?? true;
  // Load server list including their isActive status
  final initialServerList = _loadInitialServerList(prefs);
  // Removed: final initialActiveServerId = prefs.getString(activeMcpServerIdKey);

  runApp(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        apiKeyProvider.overrideWith((ref) => initialApiKey),
        showCodeBlocksProvider.overrideWith((ref) => initialShowCodeBlocks),
        // Provide the fully loaded server list (with isActive flags)
        mcpServerListProvider.overrideWith((ref) => initialServerList),
        // Removed: activeMcpServerIdProvider override
      ],
      child: const MyApp(),
    ),
  );
}

// Helper function to load initial server list (handles isActive)
List<McpServerConfig> _loadInitialServerList(SharedPreferences prefs) {
  try {
    final serverListJson = prefs.getString(mcpServerListKey);
    debugPrint("Loaded server list JSON from prefs: $serverListJson");
    if (serverListJson != null && serverListJson.isNotEmpty) {
      final decodedList = jsonDecode(serverListJson) as List;
      // Use the updated McpServerConfig.fromJson which handles 'isActive'
      final configList =
          decodedList
              .map(
                (item) =>
                    McpServerConfig.fromJson(item as Map<String, dynamic>),
              )
              .toList();
      debugPrint(
        "Successfully parsed ${configList.length} servers from storage.",
      );
      return configList;
    }
    return [];
  } catch (e) {
    debugPrint("Error loading/parsing initial server list in main: $e");
    return [];
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemini Chat Desktop (Multi-MCP)',
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
