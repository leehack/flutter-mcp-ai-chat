import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

// Import domain repository and entity
import '../domains/settings/repository/settings_repository.dart';
import '../domains/settings/entity/mcp_server_config.dart';

// Import providers for state management
import 'settings_providers.dart';
import '../domains/settings/data/settings_repository_impl.dart'; // Access repo provider

// UUID generator for creating unique server IDs
const _uuid = Uuid();

/// Application service layer for managing settings-related operations.
/// It interacts with the [SettingsRepository] for persistence and updates
/// the state providers ([apiKeyProvider], [mcpServerListProvider])
/// to reflect changes in the application state.
class SettingsService {
  final Ref _ref;

  SettingsService(this._ref);

  // Helper getter for the settings repository instance
  SettingsRepository get _repo => _ref.read(settingsRepositoryProvider);

  /// Saves the API key to the repository and updates the state provider.
  Future<void> saveApiKey(String apiKey) async {
    try {
      await _repo.saveApiKey(apiKey);
      // Update the application state
      _ref.read(apiKeyProvider.notifier).state = apiKey;
      debugPrint("SettingsService: API Key saved.");
    } catch (e) {
      debugPrint("SettingsService: Error saving API key: $e");
      rethrow; // Allow UI layer to handle error display
    }
  }

  /// Clears the API key from the repository and updates the state provider.
  Future<void> clearApiKey() async {
    try {
      await _repo.clearApiKey();
      // Update the application state
      _ref.read(apiKeyProvider.notifier).state = null;
      debugPrint("SettingsService: API Key cleared.");
    } catch (e) {
      debugPrint("SettingsService: Error clearing API key: $e");
      rethrow;
    }
  }

  /// Saves the current list of MCP servers (from the state provider) to the repository.
  /// This is called internally after any modification to the server list.
  Future<void> _saveCurrentMcpListState() async {
    // Read the current list from the state provider
    final currentList = _ref.read(mcpServerListProvider);
    try {
      // Persist the list using the repository
      await _repo.saveMcpServerList(currentList);
      debugPrint(
        "SettingsService: MCP Server list saved to repository. Count: ${currentList.length}",
      );
    } catch (e) {
      debugPrint("SettingsService: Error saving MCP server list: $e");
      rethrow;
    }
  }

  /// Adds a new MCP server configuration to the state provider list and persists the change.
  Future<void> addMcpServer(
    String name,
    String command,
    String args,
    Map<String, String> customEnv,
  ) async {
    // Create a new server config with a unique ID
    final newServer = McpServerConfig(
      id: _uuid.v4(), // Generate unique ID
      name: name,
      command: command,
      args: args,
      isActive: false, // New servers default to inactive
      customEnvironment: customEnv,
    );
    final currentList = _ref.read(mcpServerListProvider);
    // Update the state provider with the new list
    _ref.read(mcpServerListProvider.notifier).state = [
      ...currentList,
      newServer,
    ];
    // Persist the updated list
    await _saveCurrentMcpListState();
    debugPrint("SettingsService: Added MCP Server '${newServer.name}'.");
  }

  /// Updates an existing MCP server configuration in the state provider list and persists.
  Future<void> updateMcpServer(McpServerConfig updatedServer) async {
    final currentList = _ref.read(mcpServerListProvider);
    // Find the index of the server to update
    final index = currentList.indexWhere((s) => s.id == updatedServer.id);
    if (index != -1) {
      // Create a mutable copy, update the item, and update the state
      final newList = List<McpServerConfig>.from(currentList);
      newList[index] = updatedServer;
      _ref.read(mcpServerListProvider.notifier).state = newList;
      // Persist the updated list
      await _saveCurrentMcpListState();
      debugPrint(
        "SettingsService: Updated MCP Server '${updatedServer.name}'.",
      );
    } else {
      // Log an error if the server ID wasn't found (shouldn't normally happen)
      debugPrint(
        "SettingsService: Error - Tried to update non-existent server ID '${updatedServer.id}'.",
      );
    }
  }

  /// Deletes an MCP server configuration from the state provider list and persists.
  Future<void> deleteMcpServer(String serverId) async {
    final currentList = _ref.read(mcpServerListProvider);
    final serverName =
        currentList
            .firstWhere(
              (s) => s.id == serverId,
              orElse:
                  () => McpServerConfig(
                    id: serverId,
                    name: 'Unknown',
                    command: '',
                    args: '',
                  ),
            )
            .name;
    // Create a new list excluding the server with the matching ID
    final newList = currentList.where((s) => s.id != serverId).toList();
    // Check if the list actually changed (i.e., the server was found and removed)
    if (newList.length < currentList.length) {
      _ref.read(mcpServerListProvider.notifier).state = newList;
      // Persist the updated list
      await _saveCurrentMcpListState();
      debugPrint(
        "SettingsService: Deleted MCP Server '$serverName' ($serverId).",
      );
    } else {
      // Log an error if the server ID wasn't found
      debugPrint(
        "SettingsService: Error - Tried to delete non-existent server ID '$serverId'.",
      );
    }
  }

  /// Toggles the `isActive` flag for a specific MCP server in the state provider list and persists.
  /// This change will be picked up by the `McpClientNotifier` to initiate connection/disconnection.
  Future<void> toggleMcpServerActive(String serverId, bool isActive) async {
    final currentList = _ref.read(mcpServerListProvider);
    final index = currentList.indexWhere((s) => s.id == serverId);
    if (index != -1) {
      // Create a mutable copy, update the isActive flag, and update the state
      final newList = List<McpServerConfig>.from(currentList);
      final serverName = newList[index].name;
      newList[index] = newList[index].copyWith(
        isActive: isActive,
      ); // Use copyWith
      _ref.read(mcpServerListProvider.notifier).state = newList;
      // Persist the updated list
      await _saveCurrentMcpListState();
      debugPrint(
        "SettingsService: Toggled server '$serverName' ($serverId) isActive to: $isActive",
      );
      // Note: McpClientNotifier will automatically react to this state change
    } else {
      debugPrint(
        "SettingsService: Error - Tried to toggle non-existent server ID '$serverId'.",
      );
    }
  }
}

/// Provider for the SettingsService instance.
final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService(ref);
});
