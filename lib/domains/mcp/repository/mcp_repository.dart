import '../entity/mcp_models.dart'; // Local domain entities ONLY

/// Abstract repository for managing MCP connections and interactions.
/// This layer knows *nothing* about the AI model or Settings Config objects.
abstract class McpRepository {
  /// Connects to a specific MCP server using provided parameters.
  /// Handles discovery of tools provided by the server.
  Future<void> connectServer({
    required String serverId,
    required String command,
    required String args,
    required Map<String, String> environment,
  });

  /// Disconnects from a specific MCP server by its ID.
  Future<void> disconnectServer(String serverId);

  /// Disconnects all currently connected MCP servers.
  Future<void> disconnectAllServers();

  /// Executes a specific tool on a specific server.
  ///
  /// - `toolName`: The exact name of the tool declared by the MCP server.
  /// - `arguments`: The arguments for the tool call, matching the tool's input schema.
  /// - `serverId`: The ID of the server that provides the tool.
  ///
  /// Returns a list of structured [McpContent] parts representing the tool's result.
  /// Throws an exception if the server/tool is not found, not connected, or execution fails.
  Future<List<McpContent>> executeTool({
    // Changed return type
    required String serverId,
    required String toolName,
    required Map<String, dynamic> arguments,
  });

  /// Provides a stream of the current MCP client state (statuses, discovered tools, errors).
  Stream<McpClientState> get mcpStateStream;

  /// Gets the current MCP state snapshot.
  McpClientState get currentMcpState;
}
