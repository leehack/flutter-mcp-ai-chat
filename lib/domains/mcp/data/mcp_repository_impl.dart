import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mcp_dart/mcp_dart.dart';

import '../entity/mcp_models.dart';
import '../repository/mcp_repository.dart';
import 'mcp_client.dart'; // The data-layer client

/// Implementation of McpRepository.
/// Manages McpClient instances and connection lifecycle.
/// Translates mcp_dart results into domain entities.
class McpRepositoryImpl implements McpRepository {
  // Internal state managed by this repository implementation
  final Map<String, McpClient> _activeClients = {};
  final Map<String, McpConnectionStatus> _serverStatuses = {};
  final Map<String, List<McpToolDefinition>> _discoveredTools = {};
  final Map<String, String> _serverErrorMessages = {};

  // Stream controller to broadcast state changes
  final StreamController<McpClientState> _stateController =
      StreamController.broadcast();

  // Constructor no longer needs Ref
  McpRepositoryImpl() {
    // Initial state emission
    _emitState();
  }

  // --- State Management ---

  void _emitState() {
    if (!_stateController.isClosed) {
      // Create the state object with current internal maps
      final state = McpClientState(
        serverStatuses: Map.unmodifiable(_serverStatuses),
        discoveredTools: Map.unmodifiable(_discoveredTools),
        serverErrorMessages: Map.unmodifiable(_serverErrorMessages),
      );
      _stateController.add(state);
    }
  }

  @override
  Stream<McpClientState> get mcpStateStream => _stateController.stream;

  @override
  McpClientState get currentMcpState => McpClientState(
    serverStatuses: Map.unmodifiable(_serverStatuses),
    discoveredTools: Map.unmodifiable(_discoveredTools),
    serverErrorMessages: Map.unmodifiable(_serverErrorMessages),
  );

  void _updateStatus(
    String serverId,
    McpConnectionStatus status, {
    String? errorMsg,
  }) {
    final currentStatus = _serverStatuses[serverId];
    // Avoid redundant updates if status hasn't changed
    if (currentStatus == status &&
        (errorMsg == null || _serverErrorMessages[serverId] == errorMsg)) {
      return;
    }

    _serverStatuses[serverId] = status;
    if (errorMsg != null) {
      _serverErrorMessages[serverId] = errorMsg;
    } else {
      // Clear error message only if status is not error
      if (status != McpConnectionStatus.error) {
        _serverErrorMessages.remove(serverId);
      }
    }

    // If disconnected or errored, ensure client and tools are removed
    if (status == McpConnectionStatus.disconnected ||
        status == McpConnectionStatus.error) {
      // Client removal might have already happened via cleanup/onClose,
      // but ensure tools are cleared from state.
      _activeClients.remove(serverId);
      _discoveredTools.remove(serverId);
    }
    _emitState(); // Broadcast the updated state
  }

  void _handleClientConnectSuccess(
    String serverId,
    List<McpToolDefinition> tools,
  ) {
    _discoveredTools[serverId] = tools;
    // Status should already be 'connecting', update to 'connected'
    _updateStatus(serverId, McpConnectionStatus.connected);
    // Note: _addClient is implicitly handled by connectServer creating the instance
  }

  void _handleClientClose(String serverId) {
    // Called by McpClient when its transport closes
    _updateStatus(serverId, McpConnectionStatus.disconnected);
  }

  void _handleClientError(String serverId, String errorMsg) {
    // Called by McpClient on transport error or other internal issues
    _updateStatus(serverId, McpConnectionStatus.error, errorMsg: errorMsg);
  }

  // --- Connection Management ---

  @override
  Future<void> connectServer({
    // Updated signature
    required String serverId,
    required String command,
    required String args,
    required Map<String, String> environment,
  }) async {
    // Prevent multiple connection attempts for the same server
    if (_activeClients.containsKey(serverId) ||
        _serverStatuses[serverId] == McpConnectionStatus.connecting) {
      debugPrint(
        "MCP Repo [$serverId]: Connection attempt ignored, already connected or connecting.",
      );
      return;
    }

    // Removed AI Repo check

    if (command.trim().isEmpty) {
      _updateStatus(
        serverId,
        McpConnectionStatus.error,
        errorMsg: "Server command is empty.",
      );
      return;
    }

    _updateStatus(serverId, McpConnectionStatus.connecting);
    McpClient? newClientInstance;

    try {
      // Use provided arguments directly
      final argsList = args.split(' ').where((s) => s.isNotEmpty).toList();

      // Create client instance (no AI model passed)
      newClientInstance = McpClient(serverId);
      // Add client instance immediately *before* connecting,
      // so disconnect can find it if connect fails mid-way.
      _activeClients[serverId] = newClientInstance;

      newClientInstance.setupCallbacks(
        onError: _handleClientError, // Use internal handlers
        onConnectSuccess: _handleClientConnectSuccess,
        onClose: _handleClientClose,
      );

      // connectToServer now fetches tools and calls onConnectSuccess/onError
      await newClientInstance.connectToServer(command, argsList, environment);

      // Status is updated via callbacks (_handleClientConnectSuccess or _handleClientError)
    } catch (e) {
      debugPrint(
        "MCP Repo [$serverId]: Connection failed during setup/initiation: $e",
      );
      // Ensure client is removed if connectToServer throws before establishing callbacks fully
      _activeClients.remove(serverId);
      // Update status AFTER removing client, as _updateStatus might remove it again if status is error/disconnected
      _updateStatus(
        serverId,
        McpConnectionStatus.error,
        errorMsg: "Connection failed: $e",
      );
      // No need to call cleanup here, as the client instance might not be fully formed or transport might not exist
    }
  }

  @override
  Future<void> disconnectServer(String serverId) async {
    final client = _activeClients[serverId];
    if (client == null) {
      // If no client, ensure status is disconnected
      if (_serverStatuses[serverId] != McpConnectionStatus.disconnected) {
        _updateStatus(serverId, McpConnectionStatus.disconnected);
      }
      return;
    }
    debugPrint("MCP Repo [$serverId]: Disconnecting...");
    // Let the client's cleanup trigger the onClose callback, which updates the status
    await client.cleanup();
    // Status update and client/tool removal happens in _handleClientClose/_updateStatus
    debugPrint(
      "MCP Repo [$serverId]: Disconnect process initiated for $serverId.",
    );
  }

  @override
  Future<void> disconnectAllServers() async {
    debugPrint("MCP Repo: Disconnecting all servers...");
    final serverIds = List<String>.from(_activeClients.keys);
    // Disconnect concurrently
    final futures = serverIds.map((id) => disconnectServer(id)).toList();
    try {
      await Future.wait(futures);
    } catch (e) {
      debugPrint("MCP Repo: Error during disconnectAll: $e");
    }
    debugPrint("MCP Repo: Disconnect all process complete.");
  }

  // --- Tool Execution ---

  @override
  Future<List<McpContent>> executeTool({
    // Changed return type
    required String serverId,
    required String toolName,
    required Map<String, dynamic> arguments,
  }) async {
    final client = _activeClients[serverId];
    if (client == null || !client.isConnected) {
      throw StateError("MCP Server [$serverId] is not connected or not found.");
    }

    // Delegate execution to the specific McpClient instance
    try {
      // McpClient.callTool now returns the raw mcp_dart result
      final CallToolResult mcpDartResult = await client.callTool(
        toolName,
        arguments,
      );

      // --- Translation logic using toJson/fromJson ---
      final List<McpContent> parsedContent = [];
      for (final mcpDartContent in mcpDartResult.content) {
        try {
          // Convert mcp_dart content to JSON map, then parse into McpContent
          final jsonMap = mcpDartContent.toJson();
          parsedContent.add(McpContent.fromJson(jsonMap));
        } catch (e, stackTrace) {
          debugPrint(
            "Error translating content part for tool '$toolName' [$serverId]: $e\n$stackTrace\nRaw Content Part: $mcpDartContent",
          );
          parsedContent.add(
            McpUnknownContent(
              type: 'content_translate_error',
              additionalProperties: {
                'error': e.toString(),
                'raw_content': mcpDartContent.toJson(),
              },
            ),
          );
        }
      }
      // Construct and return the domain entity list
      return parsedContent;
      // --- End Translation Logic ---
    } catch (e) {
      debugPrint("MCP Repo [$serverId]: Error executing tool '$toolName': $e");
      // Update status for this server? Maybe not, tool execution failure != connection failure.
      // _updateStatus(serverId, McpConnectionStatus.error, errorMsg: "Tool execution failed: $e");
      rethrow; // Rethrow the specific execution error
    }
  }

  // Dispose method to clean up resources
  void dispose() {
    debugPrint("MCP Repo: Disposing...");
    disconnectAllServers(); // Ensure all clients are cleaned up
    _stateController.close(); // Close the stream controller
    _activeClients.clear(); // Clear internal maps
    _serverStatuses.clear();
    _discoveredTools.clear();
    _serverErrorMessages.clear();
    debugPrint("MCP Repo: Disposed.");
  }
}
