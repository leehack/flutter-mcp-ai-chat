import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_desktop/domains/ai/data/ai_repository_impl.dart';
import 'package:flutter_chat_desktop/domains/mcp/data/mcp_repository_impl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domains/ai/entity/ai_entities.dart';
import '../domains/ai/repository/ai_repository.dart';
// Domain Entities
import '../domains/chat/entity/chat_message.dart';
import '../domains/mcp/entity/mcp_models.dart';
import '../domains/mcp/repository/mcp_repository.dart';
import 'mcp_providers.dart';
// Application Providers
import 'settings_providers.dart';

// --- Chat State ---
@immutable
class ChatState {
  final List<ChatMessage> displayMessages; // Messages shown in UI
  final List<AiContent>
  chatHistory; // History sent to AI (structured using AI domain entities)
  final bool isLoading;
  final bool isApiKeySet;
  // REMOVED: final bool showCodeBlocks;

  const ChatState({
    this.displayMessages = const [],
    this.chatHistory = const [],
    this.isLoading = false,
    this.isApiKeySet = false,
    // REMOVED: this.showCodeBlocks = true,
  });

  ChatState copyWith({
    List<ChatMessage>? displayMessages,
    List<AiContent>? chatHistory, // Use AiContent
    bool? isLoading,
    bool? isApiKeySet,
    // REMOVED: bool? showCodeBlocks,
  }) {
    return ChatState(
      displayMessages: displayMessages ?? this.displayMessages,
      chatHistory: chatHistory ?? this.chatHistory,
      isLoading: isLoading ?? this.isLoading,
      isApiKeySet: isApiKeySet ?? this.isApiKeySet,
      // REMOVED: showCodeBlocks: showCodeBlocks ?? this.showCodeBlocks,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatState &&
          runtimeType == other.runtimeType &&
          const ListEquality().equals(displayMessages, other.displayMessages) &&
          const ListEquality().equals(
            chatHistory,
            other.chatHistory,
          ) && // Compare AiContent lists
          isLoading == other.isLoading &&
          isApiKeySet == other.isApiKeySet;
  // REMOVED: && showCodeBlocks == other.showCodeBlocks;

  @override
  int get hashCode =>
      const ListEquality().hash(displayMessages) ^
      const ListEquality().hash(chatHistory) ^ // Hash AiContent list
      isLoading.hashCode ^
      isApiKeySet.hashCode;
  // REMOVED: ^ showCodeBlocks.hashCode;
}

// --- Chat Notifier ---
class ChatNotifier extends StateNotifier<ChatState> {
  final Ref _ref;
  StreamSubscription<dynamic>? _messageSubscription;

  ChatNotifier(this._ref) : super(const ChatState()) {
    // Initialize state based on existing providers
    state = state.copyWith(
      isApiKeySet: _ref.read(apiKeyProvider) != null,
      // REMOVED: showCodeBlocks initialization
    );

    // Listen for API key changes
    _ref.listen<String?>(apiKeyProvider, (_, next) {
      if (mounted) {
        state = state.copyWith(isApiKeySet: next != null);
      }
    });

    // REMOVED: Listener for showCodeBlocksProvider
    /*
    _ref.listen<bool>(showCodeBlocksProvider, (_, next) {
       if (mounted) {
         state = state.copyWith(showCodeBlocks: next);
       }
    });
    */

    _ref.onDispose(() {
      _messageSubscription?.cancel();
      debugPrint("ChatNotifier disposed, stream cancelled.");
    });
  }

  // Access repositories via ref.read() when needed within methods
  AiRepository? get _aiRepo => _ref.read(aiRepositoryProvider);
  McpRepository get _mcpRepo => _ref.read(mcpRepositoryProvider);

  // --- State Update Helpers ---

  void _addDisplayMessage(ChatMessage message) {
    if (!mounted) return;
    state = state.copyWith(
      displayMessages: [...state.displayMessages, message],
    );
  }

  void _updateLastDisplayMessage(ChatMessage updatedMessage) {
    if (!mounted) return;
    final currentMessages = List<ChatMessage>.from(state.displayMessages);
    if (currentMessages.isNotEmpty && !currentMessages.last.isUser) {
      currentMessages[currentMessages.length - 1] = updatedMessage;
      state = state.copyWith(displayMessages: currentMessages);
    } else {
      debugPrint(
        "ChatNotifier: Attempted to update user message or empty list.",
      );
    }
  }

  void _addErrorMessage(String errorText, {bool setLoadingFalse = true}) {
    final errorMessage = ChatMessage(text: "Error: $errorText", isUser: false);
    if (!mounted) return;
    // Ensure we replace the placeholder if the error occurs immediately
    final currentMessages = List<ChatMessage>.from(state.displayMessages);
    if (currentMessages.isNotEmpty &&
        !currentMessages.last.isUser &&
        currentMessages.last.text.isEmpty) {
      currentMessages[currentMessages.length - 1] = errorMessage;
    } else {
      currentMessages.add(errorMessage);
    }

    state = state.copyWith(
      displayMessages: currentMessages,
      isLoading: setLoadingFalse ? false : state.isLoading,
    );
    if (kDebugMode && setLoadingFalse) {
      debugPrint(
        "ChatNotifier: Added error message, set isLoading=$setLoadingFalse",
      );
    }
  }

  void _setLoading(bool loading) {
    if (!mounted) return;
    if (state.isLoading != loading) {
      state = state.copyWith(isLoading: loading);
      debugPrint("ChatNotifier: Set isLoading=$loading");
    }
  }

  // --- Message Sending Logic ---
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || state.isLoading) {
      debugPrint(
        "ChatNotifier: sendMessage blocked (empty or loading: ${state.isLoading})",
      );
      return;
    }

    await _messageSubscription?.cancel();
    _messageSubscription = null;

    final aiRepo = _aiRepo;
    if (aiRepo == null || !aiRepo.isInitialized) {
      _addErrorMessage(
        "AI Service not available (check API Key).",
        setLoadingFalse:
            false, // Keep loading indicator if it was already there
      );
      return;
    }

    final userMessageText = text.trim();
    final userMessageForDisplay = ChatMessage(
      text: userMessageText,
      isUser: true,
    );
    // Create history using domain entities
    final userMessageForHistory = AiContent.user(userMessageText);
    final historyForApi = List<AiContent>.from(state.chatHistory);

    _addDisplayMessage(userMessageForDisplay);
    _setLoading(true);
    final aiPlaceholderMessage = const ChatMessage(text: "", isUser: false);
    _addDisplayMessage(aiPlaceholderMessage);

    // Decide path based on MCP state
    final mcpState = _ref.read(mcpClientProvider);
    final bool useMcp =
        mcpState.hasActiveConnections &&
        mcpState.uniqueAvailableToolNames.isNotEmpty;

    try {
      if (useMcp) {
        // --- MCP Orchestration Path ---
        debugPrint("ChatNotifier: Orchestrating query via MCP...");
        // Call the orchestration helper method
        final AiResponse finalAiResponse = await _orchestrateMcpQuery(
          userMessageText,
          historyForApi,
          aiRepo,
          _mcpRepo, // Pass repository instance
          mcpState, // Pass current MCP state
        );

        // Process the final response from orchestration
        final finalContent = finalAiResponse.firstCandidateContent;
        final historyUpdate = [
          ...historyForApi,
          userMessageForHistory,
          // TODO: Reconstruct full history including intermediate tool calls/responses
          // This requires the orchestrator to return more than just the final response.
          // For now, just add the final model response.
          if (finalContent != null) finalContent,
        ];

        if (mounted) {
          final finalMessage = ChatMessage(
            text: finalContent?.text ?? "(No response from orchestration)",
            isUser: false,
            // TODO: Add tool info back if the orchestrator provides it
          );
          _updateLastDisplayMessage(finalMessage);
          state = state.copyWith(chatHistory: historyUpdate);
          _setLoading(false);
        }
      } else {
        // --- Direct AI Streaming Path ---
        debugPrint("ChatNotifier: Processing query via Direct AI Stream...");
        final responseStream = aiRepo.sendMessageStream(
          userMessageText,
          historyForApi,
        );
        final fullResponseBuffer = StringBuffer();
        ChatMessage lastAiMessage = aiPlaceholderMessage;

        _messageSubscription = responseStream.listen(
          (AiStreamChunk chunk) {
            if (!mounted || !state.isLoading) {
              debugPrint(
                "ChatNotifier: Stream chunk received but state changed. Cancelling.",
              );
              _messageSubscription?.cancel();
              _messageSubscription = null;
              if (mounted && state.isLoading) _setLoading(false);
              return;
            }
            fullResponseBuffer.write(chunk.textDelta);
            lastAiMessage = lastAiMessage.copyWith(
              text: fullResponseBuffer.toString(),
            );
            _updateLastDisplayMessage(lastAiMessage);
          },
          onError: (error) {
            debugPrint(
              "ChatNotifier: Error receiving direct stream chunk: $error",
            );
            _addErrorMessage(error.toString());
            _setLoading(false);
            _messageSubscription = null;
          },
          onDone: () {
            debugPrint("ChatNotifier: Direct stream finished.");
            if (fullResponseBuffer.isNotEmpty && mounted) {
              final aiContentForHistory = AiContent.model(
                fullResponseBuffer.toString(),
              );
              state = state.copyWith(
                chatHistory: [
                  ...historyForApi,
                  userMessageForHistory,
                  aiContentForHistory,
                ],
              );
            }
            _setLoading(false);
            _messageSubscription = null;
          },
          cancelOnError: true,
        );
      }
    } catch (e) {
      debugPrint("ChatNotifier: Error in sendMessage: $e");
      _addErrorMessage(e.toString());
      _setLoading(false);
      _messageSubscription = null;
    }
  }

  /// Orchestrates AI and MCP interactions when tools are involved.
  Future<AiResponse> _orchestrateMcpQuery(
    String text,
    List<AiContent> history,
    AiRepository aiRepo,
    McpRepository mcpRepo,
    McpClientState mcpState, // Pass current state
  ) async {
    debugPrint("ChatNotifier: Orchestrating MCP query...");

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

    List<AiTool> aiTools = _translateMcpToolsToAiTools(
      uniqueMcpTools.values.toList(),
    );
    if (aiTools.isEmpty) {
      debugPrint(
        "ChatNotifier: No tools translated, proceeding without tools.",
      );
      // Fallback to direct call if translation fails or yields no tools
      // This might indicate an issue with the translation logic or tool definitions
      return await aiRepo.generateContent([...history, AiContent.user(text)]);
    }

    final userMessage = AiContent.user(text);
    final historyWithPrompt = [...history, userMessage];
    AiResponse initialAiResponse;
    try {
      initialAiResponse = await aiRepo.generateContent(
        historyWithPrompt,
        tools: aiTools,
      );
    } catch (e) {
      debugPrint("ChatNotifier: Error in initial AI call for MCP: $e");
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

    // --- Tool Call Required ---
    final toolName = functionCall.name;
    final serverId = mcpState.getServerIdForTool(
      toolName,
    ); // Use helper from McpState
    if (serverId == null) {
      debugPrint(
        "ChatNotifier: Could not find unique server for tool '$toolName'.",
      );
      final errorResponseContent = AiContent.toolResponse(toolName, {
        'error': "Tool '$toolName' not found or has duplicates.",
      });
      // Call AI again informing it of the error
      return await aiRepo.generateContent([
        ...historyWithPrompt,
        initialAiResponse.firstCandidateContent!,
        errorResponseContent,
      ]);
    }

    List<McpContent> toolExecutionResult;
    try {
      // Display message indicating tool call
      final serverName =
          _ref
              .read(mcpServerListProvider)
              .firstWhereOrNull((s) => s.id == serverId)
              ?.name ??
          serverId;
      _updateLastDisplayMessage(
        ChatMessage(
          text: "Calling tool: $toolName on $serverName...",
          isUser: false,
          toolName: toolName,
          sourceServerId: serverId,
          sourceServerName: serverName,
        ),
      );

      toolExecutionResult = await mcpRepo.executeTool(
        serverId: serverId,
        toolName: toolName,
        arguments: functionCall.args,
      );
    } catch (e) {
      debugPrint(
        "ChatNotifier: Error executing tool '$toolName' on server '$serverId': $e",
      );
      final errorResponseContent = AiContent.toolResponse(toolName, {
        'error': "Execution failed: $e",
      });
      // Call AI again informing it of the error
      return await aiRepo.generateContent([
        ...historyWithPrompt,
        initialAiResponse.firstCandidateContent!,
        errorResponseContent,
      ]);
    }

    // Translate McpContent list to a Map suitable for AiFunctionResponsePart
    // TODO: Improve translation for non-text/structured data
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
      // Final call to AI with the tool response included
      final finalAiResponse = await aiRepo.generateContent(finalHistory);
      // TODO: The orchestrator should ideally return the full history and tool info
      // for the notifier to update the state correctly.
      return finalAiResponse;
    } catch (e) {
      debugPrint(
        "ChatNotifier: Error in final AI call after MCP tool execution: $e",
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
    // This involves recursively converting the Map schema from McpToolDefinition
    // into the AiSchema sealed class hierarchy defined in ai_entities.dart.
    // For now, returning an empty list to allow fallback to non-tool calls.
    debugPrint(
      "Warning: _translateMcpToolsToAiTools needs full implementation!",
    );

    List<AiTool> translatedTools = [];
    for (var mcpTool in mcpTools) {
      try {
        // Attempt to translate schema
        final aiSchema = _translateSchema(mcpTool.inputSchema);
        translatedTools.add(
          AiTool(
            functionDeclarations: [
              AiFunctionDeclaration(
                name: mcpTool.name,
                description: mcpTool.description ?? "",
                parameters: aiSchema,
              ),
            ],
          ),
        );
      } catch (e) {
        debugPrint("Failed to translate schema for tool '${mcpTool.name}': $e");
        // Skip tool if schema translation fails
      }
    }
    return translatedTools;
  }

  // Recursive helper for schema translation (basic implementation)
  AiSchema? _translateSchema(Map<String, dynamic>? schemaMap) {
    if (schemaMap == null) return null;

    final type = schemaMap['type'] as String?;
    final description = schemaMap['description'] as String?;

    try {
      switch (type) {
        case 'object':
          final properties =
              schemaMap['properties'] as Map<String, dynamic>? ?? {};
          final requiredList =
              (schemaMap['required'] as List<dynamic>?)?.cast<String>();
          final aiProperties = properties.map((key, value) {
            if (value is Map<String, dynamic>) {
              return MapEntry(
                key,
                _translateSchema(value)!,
              ); // Assume non-null for valid properties
            } else {
              throw FormatException(
                "Invalid property value type for key '$key'",
              );
            }
          }); // Remove entries where translation failed

          return AiObjectSchema(
            properties: aiProperties,
            requiredProperties: requiredList,
            description: description,
          );
        case 'string':
          final enumValues =
              (schemaMap['enum'] as List<dynamic>?)?.cast<String>();
          return AiStringSchema(
            enumValues: enumValues,
            description: description,
          );
        case 'number':
        case 'integer':
          return AiNumberSchema(description: description);
        case 'boolean':
          return AiBooleanSchema(description: description);
        case 'array':
          final items = schemaMap['items'] as Map<String, dynamic>?;
          if (items == null) {
            throw FormatException("Array schema missing 'items'.");
          }
          final aiItems = _translateSchema(items);
          if (aiItems == null) {
            throw FormatException("Failed to translate array 'items'.");
          }
          return AiArraySchema(items: aiItems, description: description);
        default:
          debugPrint(
            "Unsupported schema type encountered during translation: $type",
          );
          return null; // Or throw an error
      }
    } catch (e) {
      debugPrint("Error translating schema fragment (type: $type): $e");
      return null; // Return null on error during translation
    }
  }

  // Method to clear chat history and display messages
  void clearChat() {
    _messageSubscription?.cancel();
    _messageSubscription = null;
    if (!mounted) return;
    state = state.copyWith(
      displayMessages: [],
      chatHistory: [], // Clear AiContent history
      isLoading: false,
    );
    debugPrint("ChatNotifier: Chat cleared.");
  }
}

// --- Provider ---
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier(ref);
});
