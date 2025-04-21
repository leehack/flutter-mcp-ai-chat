import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../gemini_service.dart';
import 'mcp_client.dart';
import 'mcp_models.dart';
import 'mcp_server_config.dart';

/// Manages connections to MCP servers
/// Responsible for establishing connections, handling connection errors, and cleanup
class McpConnectionManager {
  /// Reference to Riverpod providers
  final Ref _ref;

  /// Callback for updating server status
  final Function(String, McpConnectionStatus, {String? errorMsg})
  onStatusUpdate;

  /// Callback for adding a client to state
  final Function(String, McpClient) onClientAdded;

  /// Callback for removing a client from state
  final Function(String) onClientRemoved;

  /// Creates a new MCP connection manager
  McpConnectionManager(
    this._ref, {
    required this.onStatusUpdate,
    required this.onClientAdded,
    required this.onClientRemoved,
  });

  /// Connect to an MCP server using the provided configuration
  /// Updates status through callback
  Future<void> connectServer(McpServerConfig serverConfig) async {
    final serverId = serverConfig.id;

    final geminiService = _ref.read(geminiServiceProvider);
    if (geminiService == null ||
        !geminiService.isInitialized ||
        geminiService.model == null) {
      onStatusUpdate(
        serverId,
        McpConnectionStatus.error,
        errorMsg: "Gemini service not ready.",
      );
      return;
    }

    if (serverConfig.command.trim().isEmpty) {
      onStatusUpdate(
        serverId,
        McpConnectionStatus.error,
        errorMsg: "Server command is empty.",
      );
      return;
    }

    onStatusUpdate(serverId, McpConnectionStatus.connecting);
    McpClient? newClientInstance;

    try {
      // Prepare Environment
      final Map<String, String> combinedEnvironment = Map.from(
        Platform.environment,
      );
      combinedEnvironment.addAll(serverConfig.customEnvironment);

      // Use original command and args
      final command = serverConfig.command;
      final argsList =
          serverConfig.args.split(' ').where((s) => s.isNotEmpty).toList();

      newClientInstance = McpClient(serverId, geminiService.model!);
      newClientInstance.setupCallbacks(
        onError: handleClientError,
        onClose: handleClientClose,
      );

      await newClientInstance.connectToServer(
        command,
        argsList,
        combinedEnvironment,
      );

      if (newClientInstance.isConnected) {
        onClientAdded(serverId, newClientInstance);
        onStatusUpdate(serverId, McpConnectionStatus.connected);
        debugPrint(
          "MCP [$serverId]: Connected successfully to ${serverConfig.name}.",
        );
      } else {
        onStatusUpdate(
          serverId,
          McpConnectionStatus.error,
          errorMsg: "Connection failed post-attempt.",
        );
        await newClientInstance.cleanup();
      }
    } catch (e) {
      debugPrint("MCP [$serverId]: Connection failed: $e");
      onStatusUpdate(
        serverId,
        McpConnectionStatus.error,
        errorMsg: "Connection failed: $e",
      );
      await newClientInstance?.cleanup();
    }
  }

  /// Disconnect from an MCP server by its ID
  Future<void> disconnectServer(
    String serverId,
    McpClient? clientToDisconnect,
  ) async {
    if (clientToDisconnect == null) {
      onStatusUpdate(serverId, McpConnectionStatus.disconnected);
      return;
    }

    debugPrint("MCP [$serverId]: Disconnecting...");
    onStatusUpdate(serverId, McpConnectionStatus.disconnected);
    await clientToDisconnect.cleanup();

    onClientRemoved(serverId);
    debugPrint("MCP [$serverId]: Disconnect process complete.");
  }

  /// Handle client error callback
  void handleClientError(String serverId, String errorMsg) {
    debugPrint("MCP [$serverId]: Received error callback: $errorMsg");
    onStatusUpdate(serverId, McpConnectionStatus.error, errorMsg: errorMsg);
  }

  /// Handle client close callback
  void handleClientClose(String serverId) {
    debugPrint("MCP [$serverId]: Received close callback.");
    onStatusUpdate(serverId, McpConnectionStatus.disconnected);
    onClientRemoved(serverId);
  }
}
