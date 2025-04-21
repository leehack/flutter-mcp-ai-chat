import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp_dart;

import '../gemini_service.dart';
import 'mcp_client.dart';
import 'mcp_models.dart';
import 'mcp_tool_manager.dart';

/// Processes queries to MCP servers
/// Handles sending queries to Gemini API, executing tool calls, and processing responses
class McpQueryProcessor {
  /// Reference to Riverpod providers
  final Ref _ref;

  /// Tool manager for handling tool-related operations
  final McpToolManager _toolManager;

  /// Creates a new MCP query processor
  McpQueryProcessor(this._ref, this._toolManager);

  /// Process a user query and generate a response, potentially using tools from connected MCP servers
  /// - Aggregates available tools from all connected servers
  /// - Sends query to Gemini API with tools
  /// - If a tool is called, routes the call to the appropriate server
  /// - Returns the final response with all relevant content
  Future<McpProcessResult> processQuery(
    String query,
    List<Content> history,
    Map<String, McpClient> activeClients,
  ) async {
    if (activeClients.isEmpty) {
      return McpProcessResult(
        finalModelContent: Content('model', [
          TextPart("Error: No MCP servers connected."),
        ]),
      );
    }

    final geminiService = _ref.read(geminiServiceProvider);
    if (geminiService == null ||
        !geminiService.isInitialized ||
        geminiService.model == null) {
      return McpProcessResult(
        finalModelContent: Content('model', [
          TextPart("Error: Gemini service not ready."),
        ]),
      );
    }

    final currentMessages = [
      ...history,
      Content('user', [TextPart(query)]),
    ];
    final aggregatedTools = _toolManager.getAggregatedTools(activeClients);
    debugPrint(
      "MCP: Sending query to Gemini with ${aggregatedTools.length} aggregated tools available.",
    );

    try {
      final response = await geminiService.model!.generateContent(
        currentMessages,
        tools: aggregatedTools.isNotEmpty ? aggregatedTools : null,
      );

      final candidate = response.candidates.firstOrNull;
      if (candidate == null) {
        final blockReason = response.promptFeedback?.blockReason;
        return McpProcessResult(
          finalModelContent: Content('model', [
            TextPart("Response blocked: ${blockReason ?? 'Unknown reason'}"),
          ]),
        );
      }

      final firstModelContent = candidate.content;
      final functionCalls =
          firstModelContent.parts.whereType<FunctionCall>().toList();
      if (functionCalls.isEmpty) {
        return McpProcessResult(finalModelContent: firstModelContent);
      }

      return await _callFunctions(
        functionCalls,
        firstModelContent,
        currentMessages,
        activeClients,
        geminiService,
      );
    } catch (e) {
      final errorMsg = "Error during Gemini API call: $e";
      debugPrint("MCP: $errorMsg");
      return McpProcessResult(
        finalModelContent: Content('model', [TextPart(errorMsg)]),
      );
    }
  }

  /// Execute a tool call on the appropriate server and handle the response
  /// - Routes tool calls to the server that declared the tool
  /// - Sends tool response back to Gemini for final response
  /// - Handles error cases and returns appropriate results
  Future<McpProcessResult> _callFunctions(
    List<FunctionCall> functionCalls,
    Content firstModelContent,
    List<Content> currentMessages,
    Map<String, McpClient> activeClients,
    GeminiService geminiService,
  ) async {
    final call = functionCalls.first;
    final toolName = call.name;
    final targetServerId = _toolManager.getServerIdForTool(toolName);

    if (targetServerId == null) {
      final errorMsg =
          "Error: AI requested tool '$toolName' which is not available or has conflicting names across servers.";
      debugPrint("MCP: $errorMsg");
      return McpProcessResult(
        modelCallContent: firstModelContent,
        finalModelContent: Content('model', [TextPart(errorMsg)]),
        toolName: toolName,
        toolArgs: call.args,
      );
    }

    final targetClient = activeClients[targetServerId];
    if (targetClient == null || !targetClient.isConnected) {
      final errorMsg =
          "Error: Client for tool '$toolName' (Server $targetServerId) is not connected or became disconnected.";
      debugPrint("MCP: $errorMsg");
      return McpProcessResult(
        modelCallContent: firstModelContent,
        finalModelContent: Content('model', [TextPart(errorMsg)]),
        toolName: toolName,
        toolArgs: call.args,
        sourceServerId: targetServerId,
      );
    }

    debugPrint("MCP: Routing tool call '$toolName' to server $targetServerId");
    try {
      final result = await targetClient.callTool(
        mcp_dart.CallToolRequestParams(name: toolName, arguments: call.args),
      );
      final toolResponseText = result.content
          .whereType<mcp_dart.TextContent>()
          .map((c) => c.text)
          .join('\n');

      debugPrint("MCP: Tool '$toolName' executed on server $targetServerId.");
      final functionResponsePart = FunctionResponse(toolName, {
        'result': toolResponseText,
      });
      final toolResponseContent = Content('tool', [functionResponsePart]);
      final messagesForFinalResponse = [
        ...currentMessages,
        firstModelContent,
        toolResponseContent,
      ];

      debugPrint("MCP: Sending tool response back to Gemini...");
      final finalRes = await geminiService.model!.generateContent(
        messagesForFinalResponse,
      );

      final finalCandidate = finalRes.candidates.firstOrNull;
      Content finalModelContent;
      if (finalCandidate == null) {
        final finalBlockReason = finalRes.promptFeedback?.blockReason;
        finalModelContent = Content('model', [
          TextPart(
            "Response blocked after tool call: ${finalBlockReason ?? 'Unknown reason'}",
          ),
        ]);
      } else {
        finalModelContent = finalCandidate.content;
      }

      return McpProcessResult(
        modelCallContent: firstModelContent,
        toolResponseContent: toolResponseContent,
        finalModelContent: finalModelContent,
        toolName: toolName,
        toolArgs: call.args,
        toolResult: toolResponseText,
        sourceServerId: targetServerId,
      );
    } catch (e) {
      final errorMsg =
          "Error executing tool '$toolName' on server $targetServerId: $e";
      debugPrint("MCP: $errorMsg");
      return McpProcessResult(
        modelCallContent: firstModelContent,
        finalModelContent: Content('model', [TextPart(errorMsg)]),
        toolName: toolName,
        toolArgs: call.args,
        sourceServerId: targetServerId,
      );
    }
  }
}
