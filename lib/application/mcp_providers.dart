import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domains/mcp/entity/mcp_models.dart'; // For McpClientState
import 'mcp_notifier.dart'; // The notifier itself

/// The main provider for accessing the MCP client state and notifier.
/// The state reflects the connection statuses managed by the McpRepository.
final mcpClientProvider =
    StateNotifierProvider<McpClientNotifier, McpClientState>((ref) {
      return McpClientNotifier(ref);
    });
