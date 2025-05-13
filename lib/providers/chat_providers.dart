import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_desktop/domains/ai/entity/ai_entities.dart';
import 'package:flutter_chat_desktop/domains/ai/repository/ai_repository.dart';
import 'package:flutter_chat_desktop/domains/chat/entity/chat_message.dart';
import 'package:flutter_chat_desktop/domains/chat/entity/chat_state.dart';
import 'package:flutter_chat_desktop/domains/mcp/entity/mcp_models.dart';
import 'package:flutter_chat_desktop/domains/mcp/repository/mcp_repository.dart';
import 'package:flutter_chat_desktop/providers/ai_providers.dart';
import 'package:flutter_chat_desktop/providers/mcp_providers.dart';
import 'package:flutter_chat_desktop/providers/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatNotifier extends StateNotifier<ChatState> {
  final Ref _ref;
  StreamSubscription<dynamic>? _messageSubscription;

  ChatNotifier(this._ref) : super(const ChatState()) {
    state = state.copyWith(isApiKeySet: _ref.read(apiKeyProvider) != null);

    _ref.listen<String?>(apiKeyProvider, (_, next) {
      if (mounted) {
        state = state.copyWith(isApiKeySet: next != null);
      }
    });

    _ref.onDispose(() {
      _messageSubscription?.cancel();
      debugPrint("ChatNotifier disposed, stream cancelled.");
    });
  }

  AiRepository? get _aiRepo => _ref.read(aiRepositoryProvider);
  McpRepository get _mcpRepo => _ref.read(mcpRepositoryProvider);

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
        setLoadingFalse: false,
      );
      return;
    }

    final userMessageText = text.trim();
    final userMessageForDisplay = ChatMessage(
      text: userMessageText,
      isUser: true,
    );
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
        final AiResponse finalAiResponse = await _orchestrateMcpQuery(
          userMessageText,
          historyForApi,
          aiRepo,
          _mcpRepo,
          mcpState,
        );

        final finalContent = finalAiResponse.firstCandidateContent;
        final historyUpdate = [
          ...historyForApi,
          userMessageForHistory,
          if (finalContent != null) finalContent,
        ];

        if (mounted) {
          final finalMessage = ChatMessage(
            text: finalContent?.text ?? "(No response from orchestration)",
            isUser: false,
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

  /// Orchestrates AI and MCP interactions with agentic behavior for multi-step reasoning.
  Future<AiResponse> _orchestrateMcpQuery(
    String text,
    List<AiContent> history,
    AiRepository aiRepo,
    McpRepository mcpRepo,
    McpClientState mcpState,
  ) async {
    debugPrint("ChatNotifier: Orchestrating agentic MCP query...");

    // Configure agent behavior
    const int maxIterations = 15; // Prevent infinite loops

    final aiTool = AiTool(
      functionDeclarations: [
        for (var tools in mcpState.discoveredTools.entries)
          for (var mcpTool in tools.value)
            AiFunctionDeclaration(
              name: mcpTool.name,
              description: mcpTool.description ?? "",
              parameters: AiSchema.fromSchemaMap(mcpTool.inputSchema),
            ),
      ],
    );

    if (aiTool.functionDeclarations.isEmpty) {
      debugPrint(
        "ChatNotifier: No tools translated, proceeding without tools.",
      );
      return await aiRepo.generateContent([...history, AiContent.user(text)]);
    }

    // Prepare history with agentic system prompt
    final userMessage = AiContent.user(text);
    final historyWithAgentPrompt = [...history, userMessage];

    // Agent state tracking
    List<AiContent> agentConversation = [...historyWithAgentPrompt];
    int iterationCount = 0;
    bool agentThinking = true;

    _updateLastDisplayMessage(
      ChatMessage(
        text: "Planning approach to answer your question...",
        isUser: false,
      ),
    );

    try {
      // Agent loop - continue until agent decides to answer directly or max iterations reached
      while (agentThinking && iterationCount < maxIterations) {
        iterationCount++;
        debugPrint("ChatNotifier: Agent iteration $iterationCount");

        // Get AI response with tools
        final aiResponse = await aiRepo.generateContent(
          agentConversation,
          tools: [aiTool],
        );

        final aiContent = aiResponse.firstCandidateContent;
        if (aiContent == null) {
          throw Exception("Empty response from AI");
        }

        // Add AI response to conversation history
        agentConversation = [...agentConversation, aiContent];

        // Extract function calls from response
        final functionCalls =
            aiContent.parts.whereType<AiFunctionCallPart>().toList();

        // If no function calls, agent is done thinking and ready to respond directly
        if (functionCalls.isEmpty) {
          agentThinking = false;
          debugPrint("ChatNotifier: Agent completed with direct answer");
          continue; // Break the loop with final response
        }

        // Execute each tool call and add results to conversation
        final List<AiFunctionResponsePart> functionResponses = [];

        for (final functionCall in functionCalls) {
          final toolName = functionCall.name;
          final serverId = mcpState.getServerIdForTool(toolName);

          if (serverId == null) {
            debugPrint(
              "ChatNotifier: Could not find unique server for tool '$toolName'.",
            );

            functionResponses.add(
              AiFunctionResponsePart(
                name: toolName,
                response: {
                  'error': "Tool '$toolName' not found or has duplicates.",
                },
              ),
            );
            continue;
          }

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
                text:
                    "Thinking... (Step $iterationCount: Using $toolName on $serverName)",
                isUser: false,
                toolName: toolName,
                sourceServerId: serverId,
                sourceServerName: serverName,
              ),
            );

            // Execute tool and get result
            final toolResult = await mcpRepo.executeTool(
              serverId: serverId,
              toolName: toolName,
              arguments: functionCall.args,
            );

            // Add successful response
            functionResponses.add(
              AiFunctionResponsePart(
                name: toolName,
                response: {
                  'result': toolResult
                      .whereType<McpTextContent>()
                      .map((t) => t.text)
                      .join('\n'),
                },
              ),
            );
          } catch (e) {
            debugPrint("ChatNotifier: Error executing tool '$toolName': $e");

            // Add error response
            functionResponses.add(
              AiFunctionResponsePart(
                name: toolName,
                response: {'error': "Execution failed: $e"},
              ),
            );
          }
        }

        // Create tool response content and add to agent conversation
        if (functionResponses.isNotEmpty) {
          final toolResponseContent = AiContent(
            role: 'tool',
            parts: functionResponses,
          );

          agentConversation = [...agentConversation, toolResponseContent];
        }
      }

      // Generate final response based on all agent interactions
      _updateLastDisplayMessage(
        ChatMessage(text: "Preparing answer...", isUser: false),
      );

      // If we reached max iterations without an answer, force a final response
      if (agentThinking) {
        debugPrint(
          "ChatNotifier: Hit max iterations ($maxIterations), forcing final answer",
        );

        // Add a system message instructing to provide final answer
        agentConversation = [
          ...agentConversation,
          AiContent(
            role: 'tool',
            parts: [
              AiTextPart(
                "You've gathered enough information. Please provide your final answer to the user's question now.",
              ),
            ],
          ),
        ];

        // Final call without tools to get conclusion
        final finalResponse = await aiRepo.generateContent(agentConversation);
        return finalResponse;
      } else {
        // The last response in agentConversation is already the final answer
        return AiResponse(
          candidates: [AiCandidate(content: agentConversation.last)],
        );
      }
    } catch (e) {
      debugPrint("ChatNotifier: Error in agentic orchestration: $e");
      return AiResponse(
        candidates: [
          AiCandidate(content: AiContent.model("Error during processing: $e")),
        ],
      );
    }
  }

  // Method to clear chat history and display messages
  void clearChat() {
    _messageSubscription?.cancel();
    _messageSubscription = null;
    if (!mounted) return;
    state = state.copyWith(
      displayMessages: [],
      chatHistory: [],
      isLoading: false,
    );
    debugPrint("ChatNotifier: Chat cleared.");
  }
}

// --- Provider ---
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier(ref);
});
