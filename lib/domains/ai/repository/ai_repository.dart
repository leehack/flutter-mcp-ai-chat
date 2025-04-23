import '../entity/ai_entities.dart'; // Import local domain entities

/// Abstract repository for interacting with the AI model.
/// Uses domain-specific entities, no direct dependency on google_generative_ai types.
abstract class AiRepository {
  /// Checks if the AI service is initialized and ready.
  bool get isInitialized;

  // Removed: GenerativeModel? get generativeModel; - Implementation detail

  /// Sends a prompt and history to the AI model and returns a stream of response chunks.
  Stream<AiStreamChunk> sendMessageStream(
    String prompt,
    List<AiContent> history, // Use domain entity
  );

  /// Sends content (history + prompt) and optional tools to the AI model for a single response.
  Future<AiResponse> generateContent(
    // Use domain entity
    List<AiContent> historyWithPrompt, { // Use domain entity
    List<AiTool>? tools, // Use domain entity
  });
}
