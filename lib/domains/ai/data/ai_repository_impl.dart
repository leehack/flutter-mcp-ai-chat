import 'dart:async';

import 'package:flutter/foundation.dart';

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
