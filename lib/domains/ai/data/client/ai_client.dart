// Client interface that abstracts interaction with AI models
import 'dart:async';
import '../../entity/ai_entities.dart';

/// Abstract client for AI service interactions.
/// This interface decouples the repository from specific AI client implementations.
abstract class AiClient {
  /// Whether this client is properly initialized and ready to use
  bool get isInitialized;

  /// Any error that occurred during initialization
  String? get initializationError;

  /// Initializes the client if not already initialized.
  /// Returns true if initialization was successful.
  bool initialize();

  /// Sends a list of content items to the AI model and streams back response chunks.
  Stream<AiStreamChunk> getResponseStream(List<AiContent> content);

  /// Sends a list of content items and optional tools to the AI model.
  /// Returns a complete response.
  Future<AiResponse> getResponse(
    List<AiContent> content, {
    List<AiTool>? tools,
  });
}
