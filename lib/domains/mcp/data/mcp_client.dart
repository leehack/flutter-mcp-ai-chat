import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mcp_dart/mcp_dart.dart';

import '../entity/mcp_models.dart';

class McpClient {
  final String serverId;
  final Client mcp;
  StdioClientTransport? _transport;
  List<McpToolDefinition> _tools = []; // Store raw tool definitions
  bool _isConnected = false;

  // Callbacks managed by McpRepositoryImpl
  Function(String serverId, String errorMsg)? _onError;
  Function(String serverId, List<McpToolDefinition> tools)?
  _onConnectSuccess; // Notify repo of discovered tools
  Function(String serverId)? _onClose; // Callback to notify repo of closure

  bool get isConnected => _isConnected;
  List<McpToolDefinition> get availableTools => List.unmodifiable(_tools);

  McpClient(this.serverId) // No longer needs AI model
    : mcp = Client(
        Implementation(
          name: "mcp-client",
          version: "1.0.0",
        ), // Generic client name
      );

  void setupCallbacks({
    Function(String serverId, String errorMsg)? onError,
    Function(String serverId, List<McpToolDefinition> tools)? onConnectSuccess,
    Function(String serverId)? onClose,
  }) {
    _onError = onError;
    _onConnectSuccess = onConnectSuccess;
    _onClose = onClose;
  }

  Future<void> connectToServer(
    String command,
    List<String> args,
    Map<String, String> environment,
  ) async {
    if (_isConnected) return;
    if (command.trim().isEmpty) {
      throw ArgumentError("MCP command cannot be empty.");
    }
    debugPrint("McpClient [$serverId]: Connecting: $command ${args.join(' ')}");

    // Store the onClose callback locally *before* assigning it to the transport
    // This ensures we have a reference even if the transport is cleaned up later.
    final Function(String serverId)? localOnCloseCallback = _onClose;

    try {
      _transport = StdioClientTransport(
        StdioServerParameters(
          command: command,
          args: args,
          environment: environment,
          stderrMode: ProcessStartMode.normal,
        ),
      );
      _transport!.onerror = (error) {
        final errorMsg = "MCP Transport error [$serverId]: $error";
        debugPrint(errorMsg);
        _isConnected = false;
        _onError?.call(serverId, errorMsg); // Notify manager
        // Don't call cleanup here, let the repository handle it if needed
        // cleanup(); // Clean up self - REMOVED
      };
      _transport!.onclose = () {
        // This handler is primarily for *unexpected* closures
        debugPrint("MCP Transport closed unexpectedly [$serverId].");
        _isConnected = false;
        // Use the locally stored callback reference
        localOnCloseCallback?.call(serverId); // Notify manager
        _transport = null;
        _tools = []; // Clear tools on close
      };
      await mcp.connect(_transport!);
      _isConnected = true;
      debugPrint(
        "McpClient [$serverId]: Connected successfully. Fetching tools...",
      );
      await _fetchTools(); // Fetch tools immediately after connect
      _onConnectSuccess?.call(
        serverId,
        _tools,
      ); // Notify repo of discovered tools
    } catch (e) {
      debugPrint("McpClient [$serverId]: Failed to connect: $e");
      _isConnected = false;
      // Don't call cleanup here, connection failed, repository should handle status
      // await cleanup(); // Ensure cleanup on connect error - REMOVED
      rethrow; // Rethrow the error to be caught by McpRepositoryImpl
    }
  }

  /// Fetches tool definitions from the MCP server.
  Future<void> _fetchTools() async {
    if (!_isConnected) {
      _tools = [];
      return;
    }
    debugPrint("McpClient [$serverId]: Fetching tools...");
    try {
      final toolsResult = await mcp.listTools();
      List<McpToolDefinition> fetchedTools = [];
      for (var toolDef in toolsResult.tools) {
        // Directly use the schema Map provided by mcp_dart
        final schemaMap = toolDef.inputSchema.toJson();

        // Basic validation: Ensure schema is a Map
        fetchedTools.add(
          McpToolDefinition(
            name: toolDef.name,
            description: toolDef.description,
            inputSchema: schemaMap, // Store the raw Map
          ),
        );
      }
      _tools = fetchedTools;
      debugPrint("McpClient [$serverId]: Discovered ${_tools.length} tools.");
    } catch (e) {
      debugPrint("McpClient [$serverId]: Failed to fetch MCP tools: $e");
      _tools = []; // Clear tools on error
      // Optionally notify via onError callback? Or let connect fail?
      // _onError?.call(serverId, "Failed to fetch tools: $e");
      rethrow; // Rethrow fetch error to potentially fail the connection process
    }
  }

  /// Executes a tool call on the MCP server. Returns the raw mcp_dart result.
  Future<CallToolResult> callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    // Changed return type
    if (!_isConnected) {
      throw StateError("Client [$serverId] is not connected.");
    }
    final toolExists = _tools.any((t) => t.name == toolName);
    if (!toolExists) {
      throw ArgumentError("Tool '$toolName' not found on server [$serverId].");
    }

    debugPrint(
      "McpClient [$serverId]: Executing tool '$toolName' with args: $arguments",
    );
    try {
      // Return the direct result from mcp_dart
      final CallToolResult result = await mcp.callTool(
        CallToolRequestParams(name: toolName, arguments: arguments),
      );
      return result;
    } catch (e) {
      debugPrint("McpClient [$serverId]: Error calling tool '$toolName': $e");
      rethrow; // Rethrow to be handled by McpRepositoryImpl
    }
  }

  /// Cleans up the client resources, closes the transport, and ensures
  /// the onClose callback is invoked to notify the repository.
  Future<void> cleanup() async {
    // Store the callback reference *before* potentially nullifying it or the transport
    final Function(String serverId)? localOnCloseCallback = _onClose;
    bool wasConnected =
        _isConnected; // Check if we were connected before cleanup

    if (_transport != null) {
      debugPrint("McpClient [$serverId]: Cleaning up transport...");
      // Prevent transport's own onclose from firing during manual cleanup
      _transport!.onclose = null;
      _transport!.onerror = null; // Also prevent error callback during cleanup

      try {
        // Don't wait indefinitely if close hangs
        await _transport!.close().timeout(const Duration(seconds: 2));
        debugPrint("McpClient [$serverId]: Transport closed successfully.");
      } catch (e) {
        debugPrint(
          "McpClient [$serverId]: Error/Timeout closing transport: $e",
        );
        // Continue cleanup even if closing transport fails
      } finally {
        _transport = null; // Ensure transport is nullified
      }
    }

    // Update internal state *after* transport handling
    _isConnected = false;
    _tools = [];

    // Clear internal callback references *after* storing the one we need
    _onError = null;
    _onConnectSuccess = null;
    _onClose = null; // Clear the class member

    // --- Explicitly call the onClose callback ---
    // Ensure the repository is notified that this client is now closed,
    // regardless of whether the transport's onclose fired or if it was ever connected.
    if (localOnCloseCallback != null) {
      debugPrint(
        "McpClient [$serverId]: Explicitly calling onClose callback after cleanup.",
      );
      // Use the locally stored reference
      localOnCloseCallback(serverId);
    } else {
      debugPrint(
        "McpClient [$serverId]: No onClose callback was set to call after cleanup.",
      );
    }

    debugPrint(
      "McpClient [$serverId]: Cleanup complete (wasConnected: $wasConnected).",
    );
  }
}
