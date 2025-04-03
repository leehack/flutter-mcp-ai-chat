// lib/settings_service.dart (Simplified for Pre-loaded Prefs & Multi-Active)
import 'dart:convert'; // For JSON encoding/decoding
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'mcp_server_config.dart'; // Import the updated config class

// --- Storage Keys ---
const String apiKeyStorageKey = 'geminiApiKey';
const String showCodeBlocksKey = 'showCodeBlocks';
const String mcpServerListKey =
    'mcpServerList'; // Key for the list (now includes active status)
// Removed: const String activeMcpServerIdKey = 'activeMcpServerId';

const _uuid = Uuid(); // For generating unique server IDs

// --- Simple Provider for the SharedPreferences instance ---
final prefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    "SharedPreferences instance must be provided via ProviderScope overrides in main.dart",
  );
});

// --- State Providers (Values loaded via overrides in main.dart) ---
final apiKeyProvider = StateProvider<String?>((ref) => null);
final showCodeBlocksProvider = StateProvider<bool>((ref) => true);
// This provider holds the single source of truth for server configurations,
// including which ones the user *wants* to be active.
final mcpServerListProvider = StateProvider<List<McpServerConfig>>((ref) => []);
// Removed: final activeMcpServerIdProvider = StateProvider<String?>((ref) => null);

// --- Service class to interact with settings (Saving Logic) ---
class SettingsService {
  final Ref _ref;

  SettingsService(this._ref);

  SharedPreferences get _prefs => _ref.read(prefsProvider);

  // --- API Key Methods ---
  Future<void> saveApiKey(String apiKey) async {
    try {
      await _prefs.setString(apiKeyStorageKey, apiKey);
      _ref.read(apiKeyProvider.notifier).state = apiKey;
      debugPrint("API Key saved.");
    } catch (e) {
      debugPrint("Error saving API key: $e");
    }
  }

  Future<void> clearApiKey() async {
    try {
      await _prefs.remove(apiKeyStorageKey);
      _ref.read(apiKeyProvider.notifier).state = null;
      debugPrint("API Key cleared.");
    } catch (e) {
      debugPrint("Error clearing API key: $e");
    }
  }

  // --- Show Code Blocks Methods ---
  Future<void> saveShowCodeBlocks(bool showCodeBlocks) async {
    try {
      await _prefs.setBool(showCodeBlocksKey, showCodeBlocks);
      _ref.read(showCodeBlocksProvider.notifier).state = showCodeBlocks;
      debugPrint("Show Code Blocks setting saved: $showCodeBlocks");
    } catch (e) {
      debugPrint("Error saving Show Code Blocks setting: $e");
    }
  }

  // --- MCP List Methods ---
  // Saves the entire list (including isActive states) to storage and updates the provider.
  Future<void> saveMcpServerList(List<McpServerConfig> servers) async {
    try {
      final serverListJson = jsonEncode(
        servers.map((s) => s.toJson()).toList(),
      );
      await _prefs.setString(mcpServerListKey, serverListJson);
      // Update the central provider, which triggers listeners (like McpClientNotifier)
      _ref.read(mcpServerListProvider.notifier).state = servers;
      debugPrint("MCP Server list saved. Count: ${servers.length}");
    } catch (e) {
      debugPrint("Error saving MCP server list: $e");
    }
  }

  // Method to toggle the isActive status of a specific server
  Future<void> toggleMcpServerActive(String serverId, bool isActive) async {
    final currentList = List<McpServerConfig>.from(
      _ref.read(mcpServerListProvider),
    ); // Create mutable copy
    final index = currentList.indexWhere((s) => s.id == serverId);
    if (index != -1) {
      // Update the isActive status of the specific server config
      currentList[index] = currentList[index].copyWith(isActive: isActive);
      // Save the entire updated list
      await saveMcpServerList(currentList);
      debugPrint("Toggled server '$serverId' isActive to: $isActive");
    } else {
      debugPrint("Error: Tried to toggle non-existent server ID '$serverId'.");
    }
  }

  // --- Convenience methods for managing the list ---
  Future<void> addMcpServer(String name, String command, String args) async {
    final newServer = McpServerConfig(
      id: _uuid.v4(),
      name: name,
      command: command,
      args: args,
      isActive: false, // New servers start inactive
    );
    final currentList = _ref.read(mcpServerListProvider);
    await saveMcpServerList([...currentList, newServer]);
  }

  Future<void> updateMcpServer(McpServerConfig updatedServer) async {
    final currentList = _ref.read(mcpServerListProvider);
    final index = currentList.indexWhere((s) => s.id == updatedServer.id);
    if (index != -1) {
      // Preserve the existing isActive status unless explicitly changed in updatedServer
      final newList = List<McpServerConfig>.from(currentList);
      newList[index] = updatedServer.copyWith(
        isActive: updatedServer.isActive, // Keep the incoming active status
      );
      await saveMcpServerList(newList);
    } else {
      debugPrint(
        "Error: Tried to update non-existent server ID '${updatedServer.id}'.",
      );
    }
  }

  Future<void> deleteMcpServer(String serverId) async {
    final currentList = _ref.read(mcpServerListProvider);
    final newList = currentList.where((s) => s.id != serverId).toList();
    // Save the modified list. The McpClientNotifier will handle disconnecting
    // if the deleted server was active when it reacts to the list change.
    await saveMcpServerList(newList);
  }
}

// Provider for the SettingsService instance
final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService(ref);
});
