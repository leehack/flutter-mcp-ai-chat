import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Only for provider definition

import '../entity/mcp_server_config.dart';
import '../repository/settings_repository.dart';
import 'settings_keys.dart';

/// Implementation of SettingsRepository using SharedPreferences.
class SettingsRepositoryImpl implements SettingsRepository {
  final SharedPreferences _prefs;

  SettingsRepositoryImpl(this._prefs);

  // --- API Key ---
  @override
  Future<String?> getApiKey() async {
    return _prefs.getString(apiKeyStorageKey);
  }

  @override
  Future<void> saveApiKey(String apiKey) async {
    try {
      await _prefs.setString(apiKeyStorageKey, apiKey);
    } catch (e) {
      debugPrint("Error saving API key in repository: $e");
      rethrow; // Rethrow to allow service layer to handle UI feedback
    }
  }

  @override
  Future<void> clearApiKey() async {
    try {
      await _prefs.remove(apiKeyStorageKey);
    } catch (e) {
      debugPrint("Error clearing API key in repository: $e");
      rethrow;
    }
  }

  // REMOVED: Display Settings (Show Code Blocks)
  /*
  @override
  Future<bool> getShowCodeBlocks() async {
    // Always return true now, or remove entirely if not needed elsewhere
    return _prefs.getBool(showCodeBlocksKey) ?? true; // Default to true
  }

  @override
  Future<void> saveShowCodeBlocks(bool showCodeBlocks) async {
    // This method is no longer needed, but kept commented for reference
    // try {
    //   await _prefs.setBool(showCodeBlocksKey, showCodeBlocks);
    // } catch (e) {
    //   debugPrint("Error saving Show Code Blocks setting in repository: $e");
    //   rethrow;
    // }
    return Future.value(); // Or remove entirely
  }
  */

  // --- MCP Server List ---
  @override
  Future<List<McpServerConfig>> getMcpServerList() async {
    try {
      final serverListJson = _prefs.getString(mcpServerListKey);
      if (serverListJson != null && serverListJson.isNotEmpty) {
        final decodedList = jsonDecode(serverListJson) as List;
        final configList =
            decodedList
                .map(
                  (item) =>
                      McpServerConfig.fromJson(item as Map<String, dynamic>),
                )
                .toList();
        return configList;
      }
      return [];
    } catch (e) {
      debugPrint("Error loading/parsing server list in repository: $e");
      return []; // Return empty list on error
    }
  }

  @override
  Future<void> saveMcpServerList(List<McpServerConfig> servers) async {
    try {
      final serverListJson = jsonEncode(
        servers.map((s) => s.toJson()).toList(),
      );
      await _prefs.setString(mcpServerListKey, serverListJson);
    } catch (e) {
      debugPrint("Error saving MCP server list in repository: $e");
      rethrow;
    }
  }
}

// --- Providers ---

/// Provider for the SharedPreferences instance.
/// Needs to be overridden in main.dart.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    "SharedPreferences instance must be provided via ProviderScope overrides in main.dart",
  );
});

/// Provider for the Settings Repository implementation.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsRepositoryImpl(prefs);
});
