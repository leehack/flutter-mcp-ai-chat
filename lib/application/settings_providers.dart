import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domains/settings/entity/mcp_server_config.dart';

/// Holds the current API Key string (nullable).
final apiKeyProvider = StateProvider<String?>((ref) => null);

// REMOVED: showCodeBlocksProvider is no longer needed.
/*
/// Holds the boolean value for showing code blocks.
final showCodeBlocksProvider = StateProvider<bool>((ref) => true);
*/

/// Holds the list of configured MCP servers. This is the source of truth for UI and MCP connection sync.
final mcpServerListProvider = StateProvider<List<McpServerConfig>>((ref) => []);
