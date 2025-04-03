// gemini_service.dart (Handles API calls with streaming - Using debugPrint)
import 'dart:async'; // Import for Stream

import 'package:flutter/foundation.dart'; // Import for debugPrint
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'settings_service.dart'; // Import for apiKeyProvider

class GeminiService {
  final String _apiKey;
  GenerativeModel? _model;
  // ChatSession is removed as generateContentStream handles history per call
  bool _isInitialized = false;
  String? _initializationError;

  // Expose the model for MCP client usage
  GenerativeModel? get model => _model;

  GeminiService(this._apiKey) {
    _initialize();
  }

  void _initialize() {
    if (_apiKey.isEmpty) {
      _initializationError = "API Key is empty.";
      debugPrint("Warning: GeminiService initialized with an empty API Key.");
      return;
    }
    try {
      _model = GenerativeModel(
        model:
            'gemini-2.0-flash', // Ensure model supports generateContentStream
        apiKey: _apiKey,
        // safetySettings: [ ... ] // Optional
      );
      _isInitialized = true;
      _initializationError = null;
      debugPrint("GeminiService initialized successfully for streaming.");
    } catch (e) {
      debugPrint("Error initializing GenerativeModel: $e");
      _model = null;
      _isInitialized = false;
      _initializationError =
          "Failed to initialize Gemini Model: ${e.toString()}";
    }
  }

  bool get isInitialized => _isInitialized;
  String? get initializationError => _initializationError;

  // Method to send message and get a stream of responses
  // Takes the latest prompt and the history *before* this prompt
  Stream<GenerateContentResponse> sendMessageStream(
    String prompt,
    List<Content> history,
  ) {
    if (!_isInitialized || _model == null) {
      // Return a stream that immediately emits an error
      return Stream.error(
        Exception(
          "Error: Gemini service not initialized. $_initializationError",
        ),
      );
    }

    try {
      // Construct the full history including the new user prompt
      final userContent = Content.text(prompt);
      final contentForApi = [
        ...history, // History before this turn
        Content('user', userContent.parts), // Current user prompt
      ];

      // Generate content using the stream method
      final stream = _model!.generateContentStream(contentForApi);
      return stream;
    } catch (e) {
      if (kDebugMode) {
        // Use kDebugMode for conditional printing if preferred
        debugPrint("Error initiating Gemini stream: $e");
      }
      // Return a stream that immediately emits the error
      return Stream.error(
        Exception("Error initiating stream with AI service: ${e.toString()}"),
      );
    }
  }

  // clearChatSession is removed as it's not needed with generateContentStream
}

// Provider for GeminiService remains the same
final geminiServiceProvider = Provider<GeminiService?>((ref) {
  final apiKey = ref.watch(apiKeyProvider);
  if (apiKey != null && apiKey.isNotEmpty) {
    return GeminiService(apiKey);
  }
  return null;
});
