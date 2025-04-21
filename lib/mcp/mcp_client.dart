import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp_dart;

import 'schema_extension.dart';

/// Handles communication with a single MCP server instance
/// Each instance manages its own connection, tool discovery, and execution
class McpClient {
  /// Unique identifier for this server instance
  final String serverId;

  /// The MCP client from the mcp_dart package
  final mcp_dart.Client mcp;

  /// Gemini model used for generating content
  final GenerativeModel model;

  /// Transport layer for communicating with the MCP server
  mcp_dart.StdioClientTransport? _transport;

  /// List of available tools discovered from the server
  List<Tool> _tools = [];

  /// Whether the client is currently connected to the server
  bool _isConnected = false;

  /// Callback for handling errors from the server
  Function(String serverId, String errorMsg)? _onError;

  /// Callback for handling server disconnection
  Function(String serverId)? _onClose;

  /// Whether the client is currently connected to the server
  bool get isConnected => _isConnected;

  /// Unmodifiable list of tools available from this server
  List<Tool> get availableTools => List.unmodifiable(_tools);

  /// Create a new GoogleMcpClient for a specific server
  McpClient(this.serverId, this.model)
    : mcp = mcp_dart.Client(
        mcp_dart.Implementation(name: "gemini-client", version: "1.0.0"),
      );

  /// Set up error and close callbacks for this client
  void setupCallbacks({
    Function(String serverId, String errorMsg)? onError,
    Function(String serverId)? onClose,
  }) {
    _onError = onError;
    _onClose = onClose;
  }

  /// Connect to the MCP server using the given command, arguments and environment
  Future<void> connectToServer(
    String command,
    List<String> args,
    Map<String, String> environment,
  ) async {
    if (_isConnected) return;
    if (command.trim().isEmpty) throw Exception("MCP command cannot be empty.");
    debugPrint(
      "GoogleMcpClient [$serverId]: Attempting connection: $command ${args.join(' ')}",
    );
    // Avoid logging entire environment for security/verbosity
    // debugPrint("GoogleMcpClient [$serverId]: With Environment Keys: ${environment.keys.join(', ')}");
    try {
      _transport = mcp_dart.StdioClientTransport(
        mcp_dart.StdioServerParameters(
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
        _onError?.call(serverId, errorMsg);
        cleanup();
      };
      _transport!.onclose = () {
        debugPrint("MCP Transport closed [$serverId].");
        _isConnected = false;
        _onClose?.call(serverId);
        _transport = null;
        _tools = [];
      };
      await mcp.connect(_transport!);
      _isConnected = true;
      debugPrint("GoogleMcpClient [$serverId]: Connected successfully.");
      await _fetchTools();
    } catch (e) {
      debugPrint("GoogleMcpClient [$serverId]: Failed to connect: $e");
      _isConnected = false;
      await cleanup();
      rethrow;
    }
  }

  /// Fetch available tools from the connected server
  Future<void> _fetchTools() async {
    if (!_isConnected) {
      _tools = [];
      return;
    }
    debugPrint("GoogleMcpClient [$serverId]: Fetching tools...");
    try {
      final toolsResult = await mcp.listTools();
      List<Tool> fetchedTools = [];
      for (var toolDef in toolsResult.tools) {
        try {
          final schemaJson = toolDef.inputSchema.toJson();
          final schema = SchemaExtension.fromJson(schemaJson);
          if (schema != null ||
              (schemaJson['type'] == 'object' &&
                  (schemaJson['properties'] == null ||
                      (schemaJson['properties'] as Map).isEmpty))) {
            fetchedTools.add(
              Tool(
                functionDeclarations: [
                  FunctionDeclaration(
                    toolDef.name,
                    toolDef.description ?? 'No description provided.',
                    schema,
                  ),
                ],
              ),
            );
          } else {
            debugPrint(
              "Warning [$serverId]: Skipping tool '${toolDef.name}' due to unexpected null schema.",
            );
          }
        } catch (e) {
          debugPrint(
            "Error processing schema for tool '${toolDef.name}' [$serverId]: $e. Skipping tool.",
          );
        }
      }
      _tools = fetchedTools;
      debugPrint(
        "GoogleMcpClient [$serverId]: Successfully processed ${_tools.length} tools.",
      );
    } catch (e) {
      debugPrint("GoogleMcpClient [$serverId]: Failed to fetch MCP tools: $e");
      _tools = [];
    }
  }

  /// Call a tool on the connected server
  Future<mcp_dart.CallToolResult> callTool(
    mcp_dart.CallToolRequestParams params,
  ) async {
    if (!_isConnected) {
      throw Exception("Client [$serverId] is not connected.");
    }
    debugPrint(
      "GoogleMcpClient [$serverId]: Executing tool '${params.name}'...",
    );
    return await mcp.callTool(params);
  }

  /// Clean up resources and disconnect from the server
  Future<void> cleanup() async {
    if (_transport != null) {
      debugPrint("GoogleMcpClient [$serverId]: Cleaning up transport...");
      try {
        await _transport!.close();
      } catch (e) {
        debugPrint("GoogleMcpClient [$serverId]: Error closing transport: $e");
      }
      _transport = null;
    }
    _isConnected = false;
    _tools = [];
    debugPrint("GoogleMcpClient [$serverId]: Cleanup complete.");
  }
}
