import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'mcp_server_config.dart';
import '../settings_service.dart';
import 'mcp_client.dart';
import 'mcp_models.dart';
import 'mcp_connection_manager.dart';
import 'mcp_query_processor.dart';
import 'mcp_tool_manager.dart';

/// State notifier responsible for managing MCP server connections and interactions
/// Handles connection management, tool aggregation, and query processing across servers
class McpClientNotifier extends StateNotifier<McpClientState> {
  /// Reference to Riverpod providers
  final Ref _ref;

  /// Connection manager for handling server connections
  late final McpConnectionManager _connectionManager;

  /// Tool manager for handling tool-related operations
  late final McpToolManager _toolManager;

  /// Query processor for handling user queries
  late final McpQueryProcessor _queryProcessor;

  /// Creates a new MCP client notifier with initial state and connections
  McpClientNotifier(this._ref) : super(const McpClientState()) {
    // Initialize managers
    _toolManager = McpToolManager();
    _connectionManager = McpConnectionManager(
      _ref,
      onStatusUpdate: _updateServerState,
      onClientAdded: _addClient,
      onClientRemoved: _removeClient,
    );
    _queryProcessor = McpQueryProcessor(_ref, _toolManager);

    // 1. Initialize state with server configs loaded in main.dart
    final initialConfigs = _ref.read(mcpServerListProvider);
    final initialStatuses = <String, McpConnectionStatus>{};
    for (var config in initialConfigs) {
      initialStatuses[config.id] = McpConnectionStatus.disconnected;
    }
    state = state.copyWith(
      serverConfigs: initialConfigs,
      serverStatuses: initialStatuses,
    );

    // 2. Listen for future changes in the server list from settings
    _ref.listen<List<McpServerConfig>>(mcpServerListProvider, (
      previousList,
      newList,
    ) {
      debugPrint(
        "McpClientNotifier: Server list updated in settings. Syncing connections...",
      );
      // Update internal list and sync connections based on isActive flags
      state = state.copyWith(serverConfigs: newList);
      syncConnections(); // Trigger connection/disconnection logic
    });

    // 3. Trigger initial connection sync after initialization
    // Use a microtask to ensure this runs after the constructor completes
    // but before the next frame, allowing initial state to settle.
    Future.microtask(() {
      debugPrint("McpClientNotifier: Triggering initial connection sync...");
      syncConnections();
    });
  }

  // --- Connection Management ---

  /// Synchronize server connections based on active flags in server configs
  /// - Connects to servers marked as active but not currently connected
  /// - Disconnects from servers no longer marked as active
  /// - Cleans up resources for deleted servers
  void syncConnections() {
    final serverConfigs = state.serverConfigs.cast<McpServerConfig>();
    final desiredActiveServers =
        serverConfigs.where((s) => s.isActive).map((s) => s.id).toSet();
    final currentlyConnectedServers = state.activeClients.keys.toSet();

    // Connect servers that are desired but not connected/connecting
    final serversToConnect =
        desiredActiveServers
            .where(
              (id) =>
                  !currentlyConnectedServers.contains(id) &&
                  state.serverStatuses[id] != McpConnectionStatus.connecting,
            )
            .toSet();

    // Disconnect servers that are connected but no longer desired
    final serversToDisconnect = currentlyConnectedServers.difference(
      desiredActiveServers,
    );
    // Disconnect servers whose config has been deleted entirely
    final knownServerIds = serverConfigs.map((s) => s.id).toSet();
    final serversToDelete = currentlyConnectedServers.difference(
      knownServerIds,
    );

    // Combine disconnect lists
    final allServersToDisconnect = serversToDisconnect.union(serversToDelete);

    if (serversToConnect.isNotEmpty || allServersToDisconnect.isNotEmpty) {
      debugPrint("Syncing MCP Connections:");
      if (serversToConnect.isNotEmpty) {
        debugPrint(" - To Connect: ${serversToConnect.join(', ')}");
      }
      if (allServersToDisconnect.isNotEmpty) {
        debugPrint(" - To Disconnect: ${allServersToDisconnect.join(', ')}");
      }
    }

    for (final serverId in serversToConnect) {
      final config = serverConfigs.firstWhereOrNull((s) => s.id == serverId);
      if (config != null) {
        _connectionManager.connectServer(
          config,
        ); // Don't await, let them connect concurrently
      } else {
        _updateServerState(
          serverId,
          McpConnectionStatus.error,
          errorMsg: "Config not found during sync.",
        );
      }
    }

    for (final serverId in allServersToDisconnect) {
      final client = state.activeClients[serverId];
      _connectionManager.disconnectServer(serverId, client); // Don't await
      // Clean up status/error if the config was actually deleted
      if (serversToDelete.contains(serverId)) {
        state = state.copyWith(
          removeStatusIds: [serverId],
          removeErrorIds: [serverId],
        );
      }
    }

    // Clean up statuses/errors for servers no longer in config list at all
    final currentStatusIds = state.serverStatuses.keys.toSet();
    final statusesToRemove = currentStatusIds.difference(knownServerIds);
    if (statusesToRemove.isNotEmpty) {
      debugPrint(
        "MCP: Removing stale statuses/errors for IDs: ${statusesToRemove.join(', ')}",
      );
      state = state.copyWith(
        removeStatusIds: statusesToRemove.toList(),
        removeErrorIds: statusesToRemove.toList(),
      );
    }
  }

  // --- State Update Helpers ---

  /// Update the state for a server with the given status and error message
  void _updateServerState(
    String serverId,
    McpConnectionStatus status, {
    String? errorMsg,
  }) {
    // Prevent state updates if the notifier is disposed
    if (!mounted) return;

    final newStatuses = Map<String, McpConnectionStatus>.from(
      state.serverStatuses,
    );
    final newErrors = Map<String, String>.from(state.serverErrorMessages);

    newStatuses[serverId] = status;
    if (errorMsg != null) {
      newErrors[serverId] = errorMsg;
    } else {
      if (status != McpConnectionStatus.error) {
        newErrors.remove(serverId);
      }
    }

    final newClients = Map<String, McpClient>.from(
      state.activeClients.cast<String, McpClient>(),
    );
    bool clientRemoved = false;
    if (status != McpConnectionStatus.connected &&
        status != McpConnectionStatus.connecting) {
      if (newClients.remove(serverId) != null) {
        clientRemoved = true;
      }
    }

    state = state.copyWith(
      serverStatuses: newStatuses,
      serverErrorMessages: newErrors,
      activeClients: newClients,
    );

    if (clientRemoved) {
      _toolManager.rebuildToolMap(state.activeClients);
    }
  }

  /// Add a client to state and rebuild tool map
  void _addClient(String serverId, McpClient client) {
    if (!mounted) return;

    final newClients = Map<String, McpClient>.from(
      state.activeClients.cast<String, McpClient>(),
    );
    newClients[serverId] = client;

    state = state.copyWith(activeClients: newClients);
    _toolManager.rebuildToolMap(state.activeClients);
  }

  /// Remove a client from state and rebuild tool map
  void _removeClient(String serverId) {
    if (!mounted) return;

    final newClients = Map<String, McpClient>.from(
      state.activeClients.cast<String, McpClient>(),
    );
    final clientWasRemoved = newClients.remove(serverId) != null;

    if (clientWasRemoved) {
      state = state.copyWith(activeClients: newClients);
      _toolManager.rebuildToolMap(state.activeClients);
    }
  }

  // --- Query Processing ---

  /// Process a user query and generate a response, potentially using tools from connected MCP servers
  Future<McpProcessResult> processQuery(
    String query,
    List<Content> history,
  ) async {
    return await _queryProcessor.processQuery(
      query,
      history,
      state.activeClients,
    );
  }

  // --- Cleanup ---
  @override
  void dispose() {
    debugPrint("Disposing McpClientNotifier, cleaning up all clients...");
    final clientIds = List<String>.from(state.activeClients.keys);
    for (final serverId in clientIds) {
      final client = state.activeClients[serverId];
      client?.cleanup();
    }
    super.dispose();
  }
}
