import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/settings_providers.dart'; // To get API Key
import '../entity/ai_entities.dart'; // Import domain entities
import '../repository/ai_repository.dart';
import 'client/ai_client.dart';
import 'client/google_generative_ai_client.dart';

/// Implementation of AiRepository using a decoupled AI client.
/// Delegates actual AI interactions to the client implementation.
class AiRepositoryImpl implements AiRepository {
  final AiClient _client;

  AiRepositoryImpl(String apiKey) : _client = GoogleGenerativeAiClient(apiKey);

  @override
  bool get isInitialized => _client.isInitialized;

  @override
  Stream<AiStreamChunk> sendMessageStream(
    String prompt,
    List<AiContent> history, // Use domain entity
  ) {
    if (!isInitialized) {
      return Stream.error(
        Exception(
          "Error: AI service not initialized. ${_client.initializationError}",
        ),
      );
    }

    try {
      // Create the complete content including history and new prompt
      final userContent = AiContent.user(prompt);
      final contentForAi = [...history, userContent];

      // Delegate to the client
      return _client.getResponseStream(contentForAi);
    } catch (e) {
      debugPrint("Error initiating AI stream in AiRepositoryImpl: $e");
      return Stream.error(
        Exception("Error initiating stream with AI service: ${e.toString()}"),
      );
    }
  }

  @override
  Future<AiResponse> generateContent(
    // Use domain entity
    List<AiContent> historyWithPrompt, { // Use domain entity
    List<AiTool>? tools, // Use domain entity
  }) async {
    if (!isInitialized) {
      throw Exception(
        "Error: AI service not initialized. ${_client.initializationError}",
      );
    }

    try {
      // Delegate to the client
      return await _client.getResponse(historyWithPrompt, tools: tools);
    } catch (e) {
      debugPrint("Error calling generateContent in AiRepositoryImpl: $e");
      throw Exception(
        "Error generating content via AI service: ${e.toString()}",
      );
    }
  }
}

// --- Provider ---

/// Provider for the AI Repository.
/// It depends on the API key from the settings providers.
final aiRepositoryProvider = Provider<AiRepository?>((ref) {
  final apiKey = ref.watch(apiKeyProvider);
  if (apiKey != null && apiKey.isNotEmpty) {
    // Create and return the repository implementation
    // This instance will be cached by Riverpod
    return AiRepositoryImpl(apiKey);
  }
  // Return null if API key is not available
  return null;
});
