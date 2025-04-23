import 'package:flutter/foundation.dart'; // For @immutable
import 'package:collection/collection.dart'; // For listEquals

// --- Schema Entities ---

/// Base class for schema definitions used in function declarations.
@immutable
sealed class AiSchema {
  final String? description;
  const AiSchema({this.description});
}

/// Represents an object schema with properties.
class AiObjectSchema extends AiSchema {
  final Map<String, AiSchema> properties;
  final List<String>? requiredProperties;

  const AiObjectSchema({
    required this.properties,
    this.requiredProperties,
    super.description,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiObjectSchema &&
          runtimeType == other.runtimeType &&
          const MapEquality().equals(properties, other.properties) &&
          const ListEquality().equals(
            requiredProperties,
            other.requiredProperties,
          ) &&
          description == other.description;
  @override
  int get hashCode =>
      const MapEquality().hash(properties) ^
      const ListEquality().hash(requiredProperties) ^
      description.hashCode;
}

/// Represents a string schema, potentially with enum values.
class AiStringSchema extends AiSchema {
  final List<String>? enumValues;

  const AiStringSchema({this.enumValues, super.description});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiStringSchema &&
          runtimeType == other.runtimeType &&
          const ListEquality().equals(enumValues, other.enumValues) &&
          description == other.description;
  @override
  int get hashCode =>
      const ListEquality().hash(enumValues) ^ description.hashCode;
}

/// Represents a number schema (integer or double).
class AiNumberSchema extends AiSchema {
  const AiNumberSchema({super.description});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiNumberSchema &&
          runtimeType == other.runtimeType &&
          description == other.description;
  @override
  int get hashCode => description.hashCode;
}

/// Represents a boolean schema.
class AiBooleanSchema extends AiSchema {
  const AiBooleanSchema({super.description});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiBooleanSchema &&
          runtimeType == other.runtimeType &&
          description == other.description;
  @override
  int get hashCode => description.hashCode;
}

/// Represents an array schema.
class AiArraySchema extends AiSchema {
  final AiSchema items;

  const AiArraySchema({required this.items, super.description});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiArraySchema &&
          runtimeType == other.runtimeType &&
          items == other.items &&
          description == other.description;
  @override
  int get hashCode => items.hashCode ^ description.hashCode;
}

// --- Tool Entities ---

/// Represents a function declaration for the AI model.
@immutable
class AiFunctionDeclaration {
  final String name;
  final String description;
  final AiSchema? parameters; // Schema for arguments

  const AiFunctionDeclaration({
    required this.name,
    required this.description,
    this.parameters,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiFunctionDeclaration &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          description == other.description &&
          parameters == other.parameters;
  @override
  int get hashCode =>
      name.hashCode ^ description.hashCode ^ parameters.hashCode;
}

/// Represents a tool (a collection of functions) available to the AI model.
@immutable
class AiTool {
  final List<AiFunctionDeclaration> functionDeclarations;

  const AiTool({required this.functionDeclarations});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiTool &&
          runtimeType == other.runtimeType &&
          const ListEquality().equals(
            functionDeclarations,
            other.functionDeclarations,
          );
  @override
  int get hashCode => const ListEquality().hash(functionDeclarations);
}

// --- Content & Part Entities ---

/// Base class for parts within AI content.
@immutable
sealed class AiPart {
  const AiPart();
}

/// Represents a text part.
class AiTextPart extends AiPart {
  final String text;
  const AiTextPart(this.text);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiTextPart &&
          runtimeType == other.runtimeType &&
          text == other.text;
  @override
  int get hashCode => text.hashCode;
}

/// Represents a function call requested by the model.
class AiFunctionCallPart extends AiPart {
  final String name;
  final Map<String, dynamic> args;
  const AiFunctionCallPart({required this.name, required this.args});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiFunctionCallPart &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          const MapEquality().equals(args, other.args);
  @override
  int get hashCode => name.hashCode ^ const MapEquality().hash(args);
}

/// Represents the response from a function call execution.
class AiFunctionResponsePart extends AiPart {
  final String name;
  final Map<String, dynamic> response; // The result data from the function
  const AiFunctionResponsePart({required this.name, required this.response});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiFunctionResponsePart &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          const MapEquality().equals(response, other.response);
  @override
  int get hashCode => name.hashCode ^ const MapEquality().hash(response);
}

// Add other part types like AiBlobPart if needed

/// Represents a piece of content in the AI conversation history or response.
@immutable
class AiContent {
  final String role; // 'user', 'model', 'tool'
  final List<AiPart> parts;

  const AiContent({required this.role, required this.parts});

  /// Convenience constructor for simple text content from user.
  factory AiContent.user(String text) =>
      AiContent(role: 'user', parts: [AiTextPart(text)]);

  /// Convenience constructor for simple text content from model.
  factory AiContent.model(String text) =>
      AiContent(role: 'model', parts: [AiTextPart(text)]);

  /// Convenience constructor for a tool response.
  factory AiContent.toolResponse(
    String toolName,
    Map<String, dynamic> responseData,
  ) => AiContent(
    role: 'tool',
    parts: [AiFunctionResponsePart(name: toolName, response: responseData)],
  );

  /// Extracts the text from all TextParts, joined together.
  String get text {
    return parts.whereType<AiTextPart>().map((p) => p.text).join();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiContent &&
          runtimeType == other.runtimeType &&
          role == other.role &&
          const ListEquality().equals(parts, other.parts);
  @override
  int get hashCode => role.hashCode ^ const ListEquality().hash(parts);
}

// --- Response Entities ---

/// Represents a potential response candidate from the AI.
@immutable
class AiCandidate {
  final AiContent content;
  // Add other candidate properties if needed (e.g., finishReason, safetyRatings)
  // final String? finishReason;
  // final List<AiSafetyRating>? safetyRatings;

  const AiCandidate({required this.content});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiCandidate &&
          runtimeType == other.runtimeType &&
          content == other.content;
  @override
  int get hashCode => content.hashCode;
}

/// Represents the overall response from a non-streaming AI call.
@immutable
class AiResponse {
  final List<AiCandidate> candidates;
  // Add prompt feedback if needed
  // final AiPromptFeedback? promptFeedback;

  const AiResponse({required this.candidates});

  /// Gets the content from the first candidate, if available.
  AiContent? get firstCandidateContent => candidates.firstOrNull?.content;

  /// Gets the text from the first candidate's content, if available.
  String? get text => firstCandidateContent?.text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiResponse &&
          runtimeType == other.runtimeType &&
          const ListEquality().equals(candidates, other.candidates);
  @override
  int get hashCode => const ListEquality().hash(candidates);
}

/// Represents a chunk of data received from a streaming AI call.
/// Could be a text part or potentially other part types in the future.
@immutable
class AiStreamChunk {
  // For now, assume chunks primarily contain text delta
  final String textDelta;

  const AiStreamChunk({required this.textDelta});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiStreamChunk &&
          runtimeType == other.runtimeType &&
          textDelta == other.textDelta;
  @override
  int get hashCode => textDelta.hashCode;
}
