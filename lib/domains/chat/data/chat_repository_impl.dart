import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_desktop/domains/ai/data/ai_repository_impl.dart';
import 'package:flutter_chat_desktop/domains/mcp/data/mcp_repository_impl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Only for provider definition

import '../../ai/entity/ai_entities.dart';
import '../../ai/repository/ai_repository.dart';
import '../../mcp/entity/mcp_models.dart';
import '../../mcp/repository/mcp_repository.dart';
import '../repository/chat_repository.dart';

/// Implementation of ChatRepository.
/// Coordinates between AiRepository and McpRepository based on MCP connection state.
class ChatRepositoryImpl implements ChatRepository {
  final AiRepository? _aiRepo;
  final McpRepository _mcpRepo;

  // Constructor takes dependencies
  ChatRepositoryImpl({
    required AiRepository? aiRepository,
    required McpRepository mcpRepository,
  }) : _aiRepo = aiRepository,
       _mcpRepo = mcpRepository;

  @override
  Stream<dynamic> sendMessage(
    String text,
    List<AiContent> history, {
    required bool mcpToolsAvailable, // Caller indicates if MCP path is viable
  }) {
    final aiRepo = _aiRepo; // Use the injected instance

    if (aiRepo == null || !aiRepo.isInitialized) {
      return Stream.error(
        Exception("AI Service not available (check API Key)."),
      );
    }

    // Decide based on caller's input
    if (mcpToolsAvailable) {
      debugPrint(
        "ChatRepository: Processing query via MCP (tools available)...",
      );
      // Orchestration logic for tool calls happens here or in a dedicated service.
      // We pass the necessary repositories to the orchestrator.
      return Stream.fromFuture(
        _orchestrateMcpQuery(text, history, aiRepo, _mcpRepo),
      );
    } else {
      debugPrint(
        "ChatRepository: Processing query via Direct AI Stream (no MCP tools)...",
      );
      return _processDirectly(
        text,
        history,
        aiRepo,
      ); // Returns Stream<AiStreamChunk>
    }
  }

  /// Handles the complex orchestration of AI calls and MCP tool execution.
  /// This should ideally be moved to an Application Service.
  /// Now takes McpRepository as an argument instead of reading from Ref.
  Future<AiResponse> _orchestrateMcpQuery(
    String text,
    List<AiContent> history,
    AiRepository aiRepo,
    McpRepository mcpRepo, // Inject McpRepository
  ) async {
    debugPrint(
      "ChatRepository: _orchestrateMcpQuery called. Needs proper implementation in Application Layer.",
    );

    // Get current MCP state directly from the injected McpRepository
    final mcpState = mcpRepo.currentMcpState;
    final uniqueMcpTools = mcpState.uniqueToolDefinitions;
    if (uniqueMcpTools.isEmpty) {
      return AiResponse(
        candidates: [
          AiCandidate(
            content: AiContent.model(
              "Error: No unique tools found for MCP processing.",
            ),
          ),
        ],
      );
    }

    // TODO: Translate McpToolDefinition to AiTool[]
    List<AiTool> aiTools = _translateMcpToolsToAiTools(
      uniqueMcpTools.values.toList(),
    );

    final userMessage = AiContent.user(text);
    final historyWithPrompt = [...history, userMessage];
    AiResponse initialAiResponse;
    try {
      initialAiResponse = await aiRepo.generateContent(
        historyWithPrompt,
        tools: aiTools,
      );
    } catch (e) {
      debugPrint("ChatRepository: Error in initial AI call for MCP: $e");
      return AiResponse(
        candidates: [
          AiCandidate(
            content: AiContent.model("Error during initial AI call: $e"),
          ),
        ],
      );
    }

    final functionCall =
        initialAiResponse.firstCandidateContent?.parts
            .whereType<AiFunctionCallPart>()
            .firstOrNull;

    if (functionCall == null) {
      return initialAiResponse; // No tool call needed
    }

    final toolName = functionCall.name;
    // Use McpState obtained from the repository
    final serverId = mcpState.getServerIdForTool(toolName);
    if (serverId == null) {
      debugPrint(
        "ChatRepository: Could not find unique server for tool '$toolName'.",
      );
      // TODO: Handle error by informing the AI model
      return AiResponse(
        candidates: [
          AiCandidate(
            content: AiContent.model(
              "Error: Tool '$toolName' is unavailable or has duplicates.",
            ),
          ),
        ],
      );
    }

    List<McpContent> toolExecutionResult;
    try {
      // Use the injected McpRepository instance
      toolExecutionResult = await mcpRepo.executeTool(
        serverId: serverId,
        toolName: toolName,
        arguments: functionCall.args,
      );
    } catch (e) {
      debugPrint(
        "ChatRepository: Error executing tool '$toolName' on server '$serverId': $e",
      );
      // TODO: Handle error by informing the AI model
      return AiResponse(
        candidates: [
          AiCandidate(
            content: AiContent.model("Error executing tool '$toolName': $e"),
          ),
        ],
      );
    }

    // Translate McpContent result to AiFunctionResponsePart data
    final responseData = {
      'result': toolExecutionResult
          .whereType<McpTextContent>()
          .map((t) => t.text)
          .join('\n'),
    };
    final functionResponsePart = AiFunctionResponsePart(
      name: toolName,
      response: responseData,
    );
    final toolResponseContent = AiContent(
      role: 'tool',
      parts: [functionResponsePart],
    );

    final finalHistory = [
      ...historyWithPrompt,
      initialAiResponse.firstCandidateContent!, // model's function call request
      toolResponseContent, // tool's response
    ];

    try {
      final finalAiResponse = await aiRepo.generateContent(finalHistory);
      return finalAiResponse;
    } catch (e) {
      debugPrint(
        "ChatRepository: Error in final AI call after MCP tool execution: $e",
      );
      return AiResponse(
        candidates: [
          AiCandidate(
            content: AiContent.model("Error during final AI call: $e"),
          ),
        ],
      );
    }
  }

  // Placeholder for McpToolDefinition -> AiTool translation
  List<AiTool> _translateMcpToolsToAiTools(List<McpToolDefinition> mcpTools) {
    // TODO: Implement the complex translation logic here.
    debugPrint("Warning: _translateMcpToolsToAiTools needs implementation!");
    return []; // Return empty list for now
  }

  Stream<AiStreamChunk> _processDirectly(
    String text,
    List<AiContent> history,
    AiRepository aiRepo,
  ) {
    return aiRepo.sendMessageStream(text, history);
  }

  @override
  Future<void> clearChat() async {
    debugPrint("ChatRepository: clearChat called.");
    return Future.value();
  }
}

// --- Provider ---

/// Provider for the Chat Repository implementation.
/// Dependencies are now read here and passed to the constructor.
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  // Read dependencies using ref
  final aiRepository = ref.watch(aiRepositoryProvider); // Watch AI repo
  final mcpRepository = ref.watch(mcpRepositoryProvider); // Watch MCP repo

  // Inject dependencies into the implementation's constructor
  return ChatRepositoryImpl(
    aiRepository: aiRepository,
    mcpRepository: mcpRepository,
  );
});
