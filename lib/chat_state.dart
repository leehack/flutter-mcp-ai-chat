// chat_state.dart (Add logging for isLoading state changes)
import 'dart:async';
import 'dart:convert'; // Import for jsonEncode
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'gemini_service.dart';
import 'mcp/mcp.dart';
import 'settings_service.dart';

// ChatMessage class remains the same as chat_state_v3
@immutable
class ChatMessage {
  final String text;
  final bool isUser;
  final String? toolName;
  final String? toolArgs;
  final String? toolResult;
  final String? sourceServerId;
  final String? sourceServerName;

  const ChatMessage({
    required this.text,
    required this.isUser,
    this.toolName,
    this.toolArgs,
    this.toolResult,
    this.sourceServerId,
    this.sourceServerName,
  });
  ChatMessage copyWith({
    String? text,
    bool? isUser,
    String? toolName,
    String? toolArgs,
    String? toolResult,
    String? sourceServerId,
    String? sourceServerName,
    bool clearToolInfo = false,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      toolName: clearToolInfo ? null : toolName ?? this.toolName,
      toolArgs: clearToolInfo ? null : toolArgs ?? this.toolArgs,
      toolResult: clearToolInfo ? null : toolResult ?? this.toolResult,
      sourceServerId:
          clearToolInfo ? null : sourceServerId ?? this.sourceServerId,
      sourceServerName:
          clearToolInfo ? null : sourceServerName ?? this.sourceServerName,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          isUser == other.isUser &&
          toolName == other.toolName &&
          toolArgs == other.toolArgs &&
          toolResult == other.toolResult &&
          sourceServerId == other.sourceServerId &&
          sourceServerName == other.sourceServerName;
  @override
  int get hashCode =>
      text.hashCode ^
      isUser.hashCode ^
      toolName.hashCode ^
      toolArgs.hashCode ^
      toolResult.hashCode ^
      sourceServerId.hashCode ^
      sourceServerName.hashCode;
}

// ChatState class remains the same as chat_state_v3
@immutable
class ChatState {
  final List<ChatMessage> displayMessages;
  final List<Content> chatHistory;
  final bool isLoading;
  final bool isApiKeySet;
  final bool showCodeBlocks;

  const ChatState({
    this.displayMessages = const [],
    this.chatHistory = const [],
    this.isLoading = false,
    this.isApiKeySet = false,
    this.showCodeBlocks = true,
  });
  ChatState copyWith({
    List<ChatMessage>? displayMessages,
    List<Content>? chatHistory,
    bool? isLoading,
    bool? isApiKeySet,
    bool? showCodeBlocks,
  }) {
    return ChatState(
      displayMessages: displayMessages ?? this.displayMessages,
      chatHistory: chatHistory ?? this.chatHistory,
      isLoading: isLoading ?? this.isLoading,
      isApiKeySet: isApiKeySet ?? this.isApiKeySet,
      showCodeBlocks: showCodeBlocks ?? this.showCodeBlocks,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatState &&
          runtimeType == other.runtimeType &&
          const ListEquality().equals(displayMessages, other.displayMessages) &&
          const ListEquality().equals(chatHistory, other.chatHistory) &&
          isLoading == other.isLoading &&
          isApiKeySet == other.isApiKeySet &&
          showCodeBlocks == other.showCodeBlocks;
  @override
  int get hashCode =>
      const ListEquality().hash(displayMessages) ^
      const ListEquality().hash(chatHistory) ^
      isLoading.hashCode ^
      isApiKeySet.hashCode ^
      showCodeBlocks.hashCode;
}

// The Notifier class that manages the ChatState
class ChatNotifier extends Notifier<ChatState> {
  StreamSubscription<GenerateContentResponse>? _directStreamSubscription;

  @override
  ChatState build() {
    final geminiService = ref.watch(geminiServiceProvider);
    final showCodeBlocksSetting = ref.watch(showCodeBlocksProvider);

    ref.onDispose(() {
      _directStreamSubscription?.cancel();
      debugPrint("ChatNotifier disposed, stream cancelled.");
    });

    return ChatState(
      isApiKeySet: geminiService != null && geminiService.isInitialized,
      showCodeBlocks: showCodeBlocksSetting,
    );
  }

  // --- Helpers (Unchanged) ---
  String _getTextFromDirectStreamChunk(GenerateContentResponse response) {
    /* ... */
    try {
      return response.text ?? "";
    } catch (e) {
      debugPrint("Error extracting text from direct stream chunk: $e");
      return "";
    }
  }

  String _getTextFromContent(Content? content) {
    /* ... */
    if (content == null) return "";
    try {
      return content.parts.whereType<TextPart>().map((p) => p.text).join(' ');
    } catch (e) {
      debugPrint("Error extracting text from Content object: $e");
      return "";
    }
  }

  void _addErrorMessage(String errorText, {bool setLoadingFalse = true}) {
    final errorMessage = ChatMessage(text: "Error: $errorText", isUser: false);
    // Ensure isLoading is set to false when adding an error message
    state = state.copyWith(
      displayMessages: [...state.displayMessages, errorMessage],
      // Conditionally set isLoading to false
      isLoading: setLoadingFalse ? false : state.isLoading,
    );
    if (kDebugMode && setLoadingFalse) {
      debugPrint("ChatNotifier: Added error message, set isLoading=false");
    }
  }

  // --- Message Sending Logic ---
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || state.isLoading) {
      if (kDebugMode) {
        debugPrint(
          "ChatNotifier: sendMessage blocked (empty or already loading: ${state.isLoading})",
        );
      }
      return;
    }

    await _directStreamSubscription?.cancel();
    _directStreamSubscription = null;

    final geminiService = ref.read(geminiServiceProvider);
    final McpClientState mcpState = ref.read(mcpClientProvider);

    if (geminiService == null || !geminiService.isInitialized) {
      _addErrorMessage(
        "Gemini API Key not set or invalid. Please check Settings.",
        setLoadingFalse:
            false, // Don't change loading state if it wasn't loading
      );
      return;
    }

    final userMessageText = text.trim();
    final userMessageForDisplay = ChatMessage(
      text: userMessageText,
      isUser: true,
    );
    final userMessageContent = Content.text(userMessageText);
    final userMessageForHistory = Content('user', userMessageContent.parts);
    final historyForApi = List<Content>.from(state.chatHistory);

    // Set loading to true
    if (kDebugMode) {
      debugPrint("ChatNotifier: Starting sendMessage, set isLoading=true");
    }
    state = state.copyWith(
      displayMessages: [...state.displayMessages, userMessageForDisplay],
      isLoading: true,
    );

    // Decide: Use MCP Client or Direct Gemini?
    if (mcpState.hasActiveConnections) {
      // --- Use MCP Client ---
      debugPrint("ChatNotifier: Processing query via MCP Client(s)...");
      try {
        final McpProcessResult mcpResult = await ref
            .read(mcpClientProvider.notifier)
            .processQuery(userMessageText, historyForApi);

        final String finalText = _getTextFromContent(
          mcpResult.finalModelContent,
        );
        String? sourceServerName;
        if (mcpResult.sourceServerId != null) {
          sourceServerName =
              mcpState.serverConfigs
                  .firstWhereOrNull((s) => s.id == mcpResult.sourceServerId)
                  ?.name;
        }
        final aiMessageForDisplay = ChatMessage(
          text: finalText.isEmpty ? "(No text content)" : finalText,
          isUser: false,
          toolName: mcpResult.toolName,
          toolArgs:
              mcpResult.toolArgs != null
                  ? jsonEncode(mcpResult.toolArgs)
                  : null,
          toolResult: mcpResult.toolResult,
          sourceServerId: mcpResult.sourceServerId,
          sourceServerName: sourceServerName,
        );
        final List<Content> newHistory = [
          ...historyForApi,
          userMessageForHistory,
          if (mcpResult.modelCallContent != null) mcpResult.modelCallContent!,
          if (mcpResult.toolResponseContent != null)
            mcpResult.toolResponseContent!,
          mcpResult.finalModelContent,
        ];

        // Update state and set isLoading false
        if (kDebugMode) {
          debugPrint("ChatNotifier: MCP query successful, set isLoading=false");
        }
        state = state.copyWith(
          displayMessages: [...state.displayMessages, aiMessageForDisplay],
          chatHistory: newHistory,
          isLoading: false, // Set loading false here
        );
      } catch (e) {
        debugPrint("ChatNotifier: Error processing query via MCP: $e");
        // Add error message, which also sets isLoading false
        _addErrorMessage("MCP Query Failed: $e");
        // No need to set isLoading false again, _addErrorMessage does it
      }
    } else {
      // --- Use Direct Gemini (Streaming) ---
      debugPrint("ChatNotifier: Processing query via Direct Gemini Stream...");
      final aiPlaceholderMessage = const ChatMessage(text: "", isUser: false);
      state = state.copyWith(
        displayMessages: [...state.displayMessages, aiPlaceholderMessage],
        // isLoading is already true
      );
      int lastMessageIndex = state.displayMessages.length - 1;
      final fullResponseBuffer = StringBuffer();

      final responseStream = geminiService.sendMessageStream(
        userMessageText,
        historyForApi,
      );
      _directStreamSubscription = responseStream.listen(
        (GenerateContentResponse chunk) {
          // Removed !mounted check
          if (!state.isLoading) {
            debugPrint(
              "ChatNotifier: Stream chunk received but state changed. Cancelling.",
            );
            _directStreamSubscription?.cancel();
            _directStreamSubscription = null;
            return;
          }
          final deltaText = _getTextFromDirectStreamChunk(chunk);
          if (deltaText.isNotEmpty) {
            fullResponseBuffer.write(deltaText);
            final currentMessages = List<ChatMessage>.from(
              state.displayMessages,
            );
            if (lastMessageIndex >= 0 &&
                lastMessageIndex < currentMessages.length &&
                !currentMessages[lastMessageIndex].isUser) {
              final lastMessage = currentMessages[lastMessageIndex];
              currentMessages[lastMessageIndex] = lastMessage.copyWith(
                text: lastMessage.text + deltaText,
              );
              state = state.copyWith(displayMessages: currentMessages);
            } else {
              debugPrint(
                "ChatNotifier: Stream listener - Invalid index/message type. Index: $lastMessageIndex, Length: ${currentMessages.length}. Adding new message.",
              );
              final newMessage = ChatMessage(text: deltaText, isUser: false);
              state = state.copyWith(
                displayMessages: [...currentMessages, newMessage],
              );
              lastMessageIndex = state.displayMessages.length - 1;
            }
          }
        },
        onError: (error) {
          debugPrint(
            "ChatNotifier: Error receiving direct stream chunk: $error",
          );
          final errorMessage = ChatMessage(
            text: "Stream Error: $error",
            isUser: false,
          );
          final currentMessages = List<ChatMessage>.from(state.displayMessages);
          if (lastMessageIndex >= 0 &&
              lastMessageIndex < currentMessages.length &&
              !currentMessages[lastMessageIndex].isUser) {
            currentMessages[lastMessageIndex] = errorMessage;
          } else {
            currentMessages.add(errorMessage);
          }
          // Set loading false on error
          if (kDebugMode) {
            debugPrint(
              "ChatNotifier: Direct stream error, set isLoading=false",
            );
          }
          state = state.copyWith(
            displayMessages: currentMessages,
            isLoading: false,
          );
          _directStreamSubscription = null;
        },
        onDone: () {
          debugPrint("ChatNotifier: Direct stream finished.");
          final aiContentForHistory = Content('model', [
            TextPart(fullResponseBuffer.toString()),
          ]);
          // Set loading false on completion
          if (kDebugMode) {
            debugPrint(
              "ChatNotifier: Direct stream finished, set isLoading=false",
            );
          }
          state = state.copyWith(
            isLoading: false, // Set loading false here
            chatHistory: [
              ...historyForApi,
              userMessageForHistory,
              aiContentForHistory,
            ],
          );
          _directStreamSubscription = null;
        },
        cancelOnError: true,
      );
    }
  }

  // Method to clear chat history and display messages
  void clearChat() {
    _directStreamSubscription?.cancel();
    _directStreamSubscription = null;
    // Ensure loading is false when clearing
    if (kDebugMode) {
      debugPrint("ChatNotifier: Clearing chat, set isLoading=false");
    }
    state = state.copyWith(
      displayMessages: [],
      chatHistory: [],
      isLoading: false,
    );
    debugPrint("ChatNotifier: Chat cleared.");
  }
}

// The global provider instance (Unchanged)
final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);
