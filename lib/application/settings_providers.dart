import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domains/settings/entity/mcp_server_config.dart';

/// Holds the current API Key string (nullable).
final apiKeyProvider = StateProvider<String?>((ref) => null);

/// Holds the list of configured MCP servers. This is the source of truth for UI and MCP connection sync.
final mcpServerListProvider = StateProvider<List<McpServerConfig>>((ref) => []);
