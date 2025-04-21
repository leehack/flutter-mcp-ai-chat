/// MCP (Model Context Protocol) client implementation for Flutter
///
/// This library provides tools for connecting to and interacting with MCP servers.
/// It handles server management, tool discovery, and query processing through Gemini.
library;

// Re-export all components from their respective files
export 'mcp_client.dart';
export 'mcp_client_notifier.dart';
export 'mcp_connection_manager.dart';
export 'mcp_models.dart';
export 'mcp_query_processor.dart';
export 'mcp_server_config.dart';
export 'mcp_tool_manager.dart';
export 'schema_extension.dart';

// Define the main provider
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'mcp_client_notifier.dart';
import 'mcp_models.dart';

/// The main provider for accessing the MCP client state and notifier
final mcpClientProvider =
    StateNotifierProvider<McpClientNotifier, McpClientState>((ref) {
      return McpClientNotifier(ref);
    });
