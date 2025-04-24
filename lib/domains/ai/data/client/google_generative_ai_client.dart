import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../../entity/ai_entities.dart';
import 'ai_client.dart';

/// Implementation of AiClient using Google's Generative AI SDK.
class GoogleGenerativeAiClient implements AiClient {
  final String _apiKey;
  final String _modelName;
  GenerativeModel? _model;
  bool _isInitialized = false;
  String? _initializationError;

  GoogleGenerativeAiClient(
    this._apiKey, {
    String modelName = 'gemini-2.5-flash-preview-04-17',
  }) : _modelName = modelName {
    initialize();
  }

  @override
  bool get isInitialized => _isInitialized;

  @override
  String? get initializationError => _initializationError;

  @override
  bool initialize() {
    if (_isInitialized) return true;

    if (_apiKey.isEmpty) {
      _initializationError = "API Key is empty.";
      debugPrint(
        "Warning: GoogleGenerativeAiClient initialized with an empty API Key.",
      );
      return false;
    }

    try {
      _model = GenerativeModel(
        model: _modelName,
        apiKey: _apiKey,
        generationConfig: GenerationConfig(temperature: 1, topP: 0.95),
        systemInstruction: Content.system(
          "You're an agent that can call external tools to help solve user questions. "
          "ALWAYS follow this process: 1) Think about what tools could help answer this question, "
          "2) Call appropriate tools to gather information, 3) If you need more information, "
          "call additional tools, 4) Once you have all needed information, respond directly to "
          "the user's question without mentioning your thought process. "
          "Only call tools that are necessary and relevant to the user's question.",
        ),
      );
      _isInitialized = true;
      _initializationError = null;
      debugPrint("GoogleGenerativeAiClient initialized successfully.");
      return true;
    } catch (e) {
      debugPrint(
        "Error initializing GenerativeModel in GoogleGenerativeAiClient: $e",
      );
      _model = null;
      _isInitialized = false;
      _initializationError =
          "Failed to initialize Gemini Model: ${e.toString()}";
      return false;
    }
  }

  @override
  Stream<AiStreamChunk> getResponseStream(List<AiContent> content) {
    if (!_isInitialized || _model == null) {
      return Stream.error(
        Exception("Error: AI service not initialized. $_initializationError"),
      );
    }

    try {
      final apiContent = content.map((c) => c.toGoogleGenAi()).toList();
      final apiStream = _model!.generateContentStream(apiContent);
      return apiStream.map(AiStreamChunk.fromGoogleGenAi);
    } catch (e) {
      debugPrint(
        "Error initiating Gemini stream in GoogleGenerativeAiClient: $e",
      );
      return Stream.error(
        Exception("Error initiating stream with AI service: ${e.toString()}"),
      );
    }
  }

  @override
  Future<AiResponse> getResponse(
    List<AiContent> content, {
    List<AiTool>? tools,
  }) async {
    if (!_isInitialized || _model == null) {
      throw Exception(
        "Error: AI service not initialized. $_initializationError",
      );
    }

    try {
      final apiContent = content.map((c) => c.toGoogleGenAi()).toList();
      final apiTools = tools?.map((t) => t.toGoogleGenAi()).toList();

      final GenerateContentResponse apiResponse = await _model!.generateContent(
        apiContent,
        tools: apiTools,
      );

      return AiResponse.fromGoogleGenAi(apiResponse);
    } catch (e) {
      debugPrint(
        "Error calling generateContent in GoogleGenerativeAiClient: $e",
      );
      throw Exception(
        "Error generating content via AI service: ${e.toString()}",
      );
    }
  }
}
