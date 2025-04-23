import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Keep: Implementation needs the actual package
import 'package:google_generative_ai/google_generative_ai.dart'; // Removed 'as gen_ai' alias

import '../../../application/settings_providers.dart'; // To get API Key
import '../entity/ai_entities.dart'; // Import domain entities
import '../repository/ai_repository.dart';

/// Implementation of AiRepository using the google_generative_ai package.
/// Handles translation between domain entities and google_generative_ai types.
class AiRepositoryImpl implements AiRepository {
  final String _apiKey;
  GenerativeModel? _model; // Internal instance of the package's model
  bool _isInitialized = false;
  String? _initializationError;

  // Removed: @override GenerativeModel? get generativeModel => _model;

  AiRepositoryImpl(this._apiKey) {
    _initialize();
  }

  void _initialize() {
    if (_apiKey.isEmpty) {
      _initializationError = "API Key is empty.";
      debugPrint(
        "Warning: AiRepositoryImpl initialized with an empty API Key.",
      );
      return;
    }
    try {
      // Consider making the model name configurable
      _model = GenerativeModel(
        model: 'gemini-2.0-flash', // Or another appropriate model
        apiKey: _apiKey,
        // safetySettings: [ ... ] // Optional
      );
      _isInitialized = true;
      _initializationError = null;
      debugPrint("AiRepositoryImpl initialized successfully.");
    } catch (e) {
      debugPrint("Error initializing GenerativeModel in AiRepositoryImpl: $e");
      _model = null;
      _isInitialized = false;
      _initializationError =
          "Failed to initialize Gemini Model: ${e.toString()}";
    }
  }

  @override
  bool get isInitialized => _isInitialized;

  // --- Translation Helpers ---

  Content _domainContentToApiContent(AiContent domainContent) {
    final apiParts = domainContent.parts.map(_domainPartToApiPart).toList();
    return Content(domainContent.role, apiParts);
  }

  Part _domainPartToApiPart(AiPart domainPart) {
    return switch (domainPart) {
      AiTextPart p => TextPart(p.text),
      AiFunctionCallPart p => FunctionCall(p.name, p.args),
      AiFunctionResponsePart p => FunctionResponse(p.name, p.response),
      // Add other types like BlobPart if needed
    };
  }

  Tool _domainToolToApiTool(AiTool domainTool) {
    final declarations =
        domainTool.functionDeclarations
            .map(_domainFunctionDeclarationToApi)
            .toList();
    return Tool(functionDeclarations: declarations);
  }

  FunctionDeclaration _domainFunctionDeclarationToApi(
    AiFunctionDeclaration domainDecl,
  ) {
    return FunctionDeclaration(
      domainDecl.name,
      domainDecl.description,
      _domainSchemaToApiSchema(domainDecl.parameters),
    );
  }

  Schema? _domainSchemaToApiSchema(AiSchema? domainSchema) {
    if (domainSchema == null) return null;
    return switch (domainSchema) {
      AiObjectSchema s => Schema.object(
        properties: s.properties.map(
          (k, v) => MapEntry(k, _domainSchemaToApiSchema(v)!),
        ), // Assume non-null for properties
        requiredProperties: s.requiredProperties,
        description: s.description,
      ),
      AiStringSchema s =>
        (s.enumValues != null && s.enumValues!.isNotEmpty)
            ? Schema.enumString(
              // Use enumString if enumValues are present
              enumValues: s.enumValues!,
              description: s.description,
            )
            : Schema.string(
              // Otherwise, use plain string
              description: s.description,
            ),
      AiNumberSchema s => Schema.number(description: s.description),
      AiBooleanSchema s => Schema.boolean(description: s.description),
      AiArraySchema s => Schema.array(
        items: _domainSchemaToApiSchema(s.items)!, // Assume non-null for items
        description: s.description,
      ),
    };
  }

  AiContent _apiContentToDomainContent(Content apiContent) {
    final domainParts = apiContent.parts.map(_apiPartToDomainPart).toList();
    return AiContent(role: apiContent.role ?? 'unknown', parts: domainParts);
  }

  AiPart _apiPartToDomainPart(Part apiPart) {
    return switch (apiPart) {
      TextPart p => AiTextPart(p.text),
      FunctionCall p => AiFunctionCallPart(name: p.name, args: p.args),
      FunctionResponse p => AiFunctionResponsePart(
        name: p.name,
        response: p.response ?? {},
      ),
      // Add other part types like BlobPart if needed
      _ => AiTextPart(
        "[Unsupported Part Type: ${apiPart.runtimeType}]",
      ), // Fallback for unknown parts
    };
  }

  AiResponse _apiResponseToDomainResponse(GenerateContentResponse apiResponse) {
    final domainCandidates =
        apiResponse.candidates.map((apiCandidate) {
          // Translate content and potentially other fields like safety ratings later
          return AiCandidate(
            content: _apiContentToDomainContent(apiCandidate.content),
          );
        }).toList();
    return AiResponse(candidates: domainCandidates);
  }

  AiStreamChunk _apiStreamChunkToDomainStreamChunk(
    GenerateContentResponse apiChunk,
  ) {
    // Extract text delta from the chunk. This might need refinement based on
    // how the google_generative_ai package structures streaming chunks.
    // Assuming `apiChunk.text` provides the delta for now.
    final textDelta = apiChunk.text ?? "";
    return AiStreamChunk(textDelta: textDelta);
  }

  // --- Repository Method Implementations ---

  @override
  Stream<AiStreamChunk> sendMessageStream(
    String prompt,
    List<AiContent> history, // Use domain entity
  ) {
    if (!_isInitialized || _model == null) {
      return Stream.error(
        Exception("Error: AI service not initialized. $_initializationError"),
      );
    }

    try {
      // Translate domain history and prompt to API types
      final apiHistory = history.map(_domainContentToApiContent).toList();
      final userContent = AiContent.user(prompt); // Create domain user content
      final apiUserContent = _domainContentToApiContent(
        userContent,
      ); // Translate it

      final contentForApi = [...apiHistory, apiUserContent];

      // Call the package's stream method
      final apiStream = _model!.generateContentStream(contentForApi);

      // Translate the stream of API responses to domain stream chunks
      return apiStream.map(_apiStreamChunkToDomainStreamChunk);
    } catch (e) {
      debugPrint("Error initiating Gemini stream in AiRepositoryImpl: $e");
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
    if (!_isInitialized || _model == null) {
      throw Exception(
        "Error: AI service not initialized. $_initializationError",
      );
    }
    try {
      // Translate domain inputs to API types
      final apiContent =
          historyWithPrompt.map(_domainContentToApiContent).toList();
      final apiTools = tools?.map(_domainToolToApiTool).toList();

      // Call the package method
      final GenerateContentResponse apiResponse = await _model!.generateContent(
        apiContent,
        tools: apiTools,
      );

      // Translate API response back to domain response
      return _apiResponseToDomainResponse(apiResponse);
    } catch (e) {
      debugPrint("Error calling generateContent in AiRepositoryImpl: $e");
      // Consider wrapping the error in a domain-specific exception
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
