import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_chat_desktop/domains/mcp/data/mcp_repository_impl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domains/mcp/entity/mcp_models.dart';
// Removed: import 'package:google_generative_ai/google_generative_ai.dart';

import '../domains/mcp/repository/mcp_repository.dart';
import '../domains/settings/entity/mcp_server_config.dart';
import 'settings_providers.dart';

/// State notifier responsible for managing the MCP client state based on settings
/// and repository updates. It orchestrates connections/disconnections.
class McpClientNotifier extends StateNotifier<McpClientState> {
  final Ref _ref;
  StreamSubscription<McpClientState>? _repoStateSubscription;
  List<McpServerConfig> _currentServerConfigs = [];

  McpClientNotifier(this._ref) : super(const McpClientState()) {
    state = _ref.read(mcpRepositoryProvider).currentMcpState;

    _repoStateSubscription = _ref
        .read(mcpRepositoryProvider)
        .mcpStateStream
        .listen(
          (repoState) {
            if (mounted) {
              state = repoState;
            }
          },
          onError: (error) {
            debugPrint(
              "McpClientNotifier: Error listening to repo state stream: $error",
            );
          },
        );

    _ref.listen<List<McpServerConfig>>(mcpServerListProvider, (
      previousList,
      newList,
    ) {
      debugPrint(
        "McpClientNotifier: Server list updated in settings. Syncing connections...",
      );
      _currentServerConfigs = newList;
      _syncConnections();
    }, fireImmediately: true);

    _ref.onDispose(() {
      debugPrint(
        "Disposing McpClientNotifier, cancelling repo subscription...",
      );
      _repoStateSubscription?.cancel();
      // _ref.read(mcpRepositoryProvider).disconnectAllServers(); // Optional: Disconnect on dispose
    });
  }

  McpRepository get _mcpRepo => _ref.read(mcpRepositoryProvider);

  /// Public method to trigger a manual sync.
  void syncConnections() {
    _syncConnections();
  }

  /// Synchronize server connections based on active flags in the latest server configs.
  void _syncConnections() {
    final desiredActiveServers =
        _currentServerConfigs.where((s) => s.isActive).toList();
    final desiredActiveIds = desiredActiveServers.map((s) => s.id).toSet();
    final currentStatuses = state.serverStatuses;
    final currentlyConnectedOrConnectingIds =
        currentStatuses.entries
            .where(
              (e) =>
                  e.value == McpConnectionStatus.connected ||
                  e.value == McpConnectionStatus.connecting,
            )
            .map((e) => e.key)
            .toSet();

    final serversToConnect =
        desiredActiveServers
            .where(
              (config) =>
                  !currentlyConnectedOrConnectingIds.contains(config.id),
            )
            .toList();

    final knownServerIds = _currentServerConfigs.map((s) => s.id).toSet();
    final serversToDisconnect =
        currentlyConnectedOrConnectingIds
            .where(
              (id) =>
                  !desiredActiveIds.contains(id) ||
                  !knownServerIds.contains(id),
            )
            .toSet();

    if (serversToConnect.isNotEmpty || serversToDisconnect.isNotEmpty) {
      debugPrint("McpClientNotifier: Syncing MCP Connections:");
      if (serversToConnect.isNotEmpty) {
        debugPrint(
          " - To Connect: ${serversToConnect.map((s) => s.name).join(', ')}",
        );
      }
      if (serversToDisconnect.isNotEmpty) {
        debugPrint(" - To Disconnect: ${serversToDisconnect.join(', ')}");
      }
    }

    for (final config in serversToConnect) {
      // Call repository with individual parameters
      _mcpRepo
          .connectServer(
            serverId: config.id,
            command: config.command,
            args: config.args,
            environment: config.customEnvironment,
          )
          .catchError((e) {
            debugPrint(
              "McpClientNotifier: Error initiating connect for ${config.id}: $e",
            );
          });
    }

    for (final serverId in serversToDisconnect) {
      _mcpRepo.disconnectServer(serverId).catchError((e) {
        debugPrint(
          "McpClientNotifier: Error initiating disconnect for $serverId: $e",
        );
      });
    }

    // Clean up stale statuses (handled by repo state stream listener)
    // final currentStatusIds = currentStatuses.keys.toSet();
    // final statusesToRemove = currentStatusIds.difference(knownServerIds);
    // if (statusesToRemove.isNotEmpty) { ... }
  }
}
