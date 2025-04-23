import '../../ai/entity/ai_entities.dart'; // Import AI domain entities

/// Abstract repository for handling chat operations.
/// This layer decides whether to use direct AI or MCP based on system state.
abstract class ChatRepository {
  /// Sends a user message, considering MCP availability.
  /// Returns a stream that yields results. The type of result depends
  /// on whether direct AI or MCP was used.
  /// - Direct AI: Yields [AiStreamChunk]
  /// - MCP: Yields [AiResponse] (the final result after potential tool execution)
  /// The decision to use MCP might depend on state provided by the caller (e.g., Notifier).
  Stream<dynamic> sendMessage(
    String text,
    List<AiContent> history, {
    required bool
    mcpToolsAvailable, // Indicate if MCP path should be considered
  });

  /// Clears the chat history (implementation specific).
  Future<void> clearChat();
}
