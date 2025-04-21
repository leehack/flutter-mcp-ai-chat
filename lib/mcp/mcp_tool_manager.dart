import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'mcp_client.dart';

/// Manages tool-related operations across MCP servers
/// Responsible for building tool maps, aggregating tools from servers, and tracking tool ownership
class McpToolManager {
  /// Maps tool names to their respective server IDs for routing tool calls
  Map<String, String> _toolToServerIdMap = {};

  /// Get the server ID for a given tool name
  String? getServerIdForTool(String toolName) => _toolToServerIdMap[toolName];

  /// Rebuild the tool map based on active clients
  /// Returns a map of tool names to server IDs
  void rebuildToolMap(Map<String, McpClient> activeClients) {
    final newToolMap = <String, String>{};
    final Set<String> uniqueToolNames = {};
    final List<String> duplicateToolNames = [];
    final currentClientIds = List<String>.from(activeClients.keys);

    for (final serverId in currentClientIds) {
      final client = activeClients[serverId];
      if (client != null && client.isConnected) {
        for (final tool in client.availableTools) {
          for (final funcDec in tool.functionDeclarations ?? []) {
            if (newToolMap.containsKey(funcDec.name)) {
              if (!duplicateToolNames.contains(funcDec.name)) {
                duplicateToolNames.add(funcDec.name);
              }
            } else {
              newToolMap[funcDec.name] = serverId;
              uniqueToolNames.add(funcDec.name);
            }
          }
        }
      }
    }
    _toolToServerIdMap = newToolMap;
    if (duplicateToolNames.isNotEmpty) {
      debugPrint(
        "MCP: Rebuilt tool map. ${uniqueToolNames.length} unique tools. Duplicates found: ${duplicateToolNames.join(', ')}",
      );
    }
  }

  /// Get aggregated tools from all active clients for use with Gemini API
  List<Tool> getAggregatedTools(Map<String, McpClient> activeClients) {
    final aggregatedTools = <Tool>[];
    final handledToolNames = <String>{};
    final currentClientIds = List<String>.from(activeClients.keys);

    for (final serverId in currentClientIds) {
      final client = activeClients[serverId];
      if (client != null && client.isConnected) {
        for (final tool in client.availableTools) {
          final uniqueDeclarations =
              tool.functionDeclarations
                  ?.where(
                    (fd) =>
                        _toolToServerIdMap[fd.name] == serverId &&
                        !handledToolNames.contains(fd.name),
                  )
                  .toList();

          if (uniqueDeclarations != null && uniqueDeclarations.isNotEmpty) {
            aggregatedTools.add(Tool(functionDeclarations: uniqueDeclarations));
            handledToolNames.addAll(uniqueDeclarations.map((fd) => fd.name));
          }
        }
      }
    }
    return aggregatedTools;
  }
}
