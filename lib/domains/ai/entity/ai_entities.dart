import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// Base class for schema definitions used in function declarations.
@immutable
sealed class AiSchema {
  final String? description;
  const AiSchema({this.description});

  /// Converts the domain schema to a Google Generative AI SDK schema
  Schema toGoogleGenAi();

  /// Converts a JSON Schema map to an AiSchema instance
  static AiSchema? fromSchemaMap(Map<String, dynamic>? schemaMap) {
    if (schemaMap == null) return null;

    final type = schemaMap['type'] as String?;
    final description = schemaMap['description'] as String?;

    try {
      switch (type) {
        case 'object':
          final properties =
              schemaMap['properties'] as Map<String, dynamic>? ?? {};
          final requiredList =
              (schemaMap['required'] as List<dynamic>?)?.cast<String>();
          final aiProperties = properties.map((key, value) {
            if (value is Map<String, dynamic>) {
              return MapEntry(key, fromSchemaMap(value)!);
            } else {
              throw FormatException(
                "Invalid property value type for key '$key'",
              );
            }
          });

          return AiObjectSchema(
            properties: aiProperties,
            requiredProperties: requiredList,
            description: description,
          );
        case 'string':
          final enumValues =
              (schemaMap['enum'] as List<dynamic>?)?.cast<String>();
          return AiStringSchema(
            enumValues: enumValues,
            description: description,
          );
        case 'number':
        case 'integer':
          return AiNumberSchema(description: description);
        case 'boolean':
          return AiBooleanSchema(description: description);
        case 'array':
          final items = schemaMap['items'] as Map<String, dynamic>?;
          if (items == null) {
            throw FormatException("Array schema missing 'items'.");
          }
          final aiItems = fromSchemaMap(items);
          if (aiItems == null) {
            throw FormatException("Failed to translate array 'items'.");
          }
          return AiArraySchema(items: aiItems, description: description);
        default:
          debugPrint(
            "Unsupported schema type encountered during translation: $type",
          );
          return null;
      }
    } catch (e) {
      debugPrint("Error translating schema fragment (type: $type): $e");
      return null;
    }
  }
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
  Schema toGoogleGenAi() {
    return Schema.object(
      properties: properties.map((k, v) => MapEntry(k, v.toGoogleGenAi())),
      requiredProperties: requiredProperties,
      description: description,
    );
  }

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
  Schema toGoogleGenAi() {
    return (enumValues != null && enumValues!.isNotEmpty)
        ? Schema.enumString(enumValues: enumValues!, description: description)
        : Schema.string(description: description);
  }

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
  Schema toGoogleGenAi() => Schema.number(description: description);

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
  Schema toGoogleGenAi() => Schema.boolean(description: description);

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
  Schema toGoogleGenAi() =>
      Schema.array(items: items.toGoogleGenAi(), description: description);

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

/// Represents a function declaration for the AI model.
@immutable
class AiFunctionDeclaration {
  final String name;
  final String description;
  final AiSchema? parameters;

  const AiFunctionDeclaration({
    required this.name,
    required this.description,
    this.parameters,
  });

  /// Converts to Google Generative AI SDK function declaration
  FunctionDeclaration toGoogleGenAi() =>
      FunctionDeclaration(name, description, parameters?.toGoogleGenAi());

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

  /// Converts to Google Generative AI SDK tool
  Tool toGoogleGenAi() {
    final declarations =
        functionDeclarations.map((decl) => decl.toGoogleGenAi()).toList();
    return Tool(functionDeclarations: declarations);
  }

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

/// Base class for parts within AI content.
@immutable
sealed class AiPart {
  const AiPart();

  /// Converts to Google Generative AI SDK part
  Part toGoogleGenAi();

  /// Creates from Google Generative AI SDK part
  static AiPart fromGoogleGenAi(Part part) {
    return switch (part) {
      TextPart p => AiTextPart(p.text),
      FunctionCall p => AiFunctionCallPart(name: p.name, args: p.args),
      FunctionResponse p => AiFunctionResponsePart(
        name: p.name,
        response: p.response ?? {},
      ),
      _ => AiTextPart("[Unsupported Part Type: ${part.runtimeType}]"),
    };
  }
}

/// Represents a text part.
class AiTextPart extends AiPart {
  final String text;
  const AiTextPart(this.text);

  @override
  Part toGoogleGenAi() => TextPart(text);

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
  Part toGoogleGenAi() => FunctionCall(name, args);

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
  final Map<String, dynamic> response;
  const AiFunctionResponsePart({required this.name, required this.response});

  @override
  Part toGoogleGenAi() => FunctionResponse(name, response);

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

/// Represents a piece of content in the AI conversation history or response.
@immutable
class AiContent {
  final String role;
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

  /// Converts to Google Generative AI SDK content
  Content toGoogleGenAi() {
    final sdkParts = parts.map((part) => part.toGoogleGenAi()).toList();
    return Content(role, sdkParts);
  }

  /// Creates from Google Generative AI SDK content
  static AiContent fromGoogleGenAi(Content content) {
    final domainParts = content.parts.map(AiPart.fromGoogleGenAi).toList();
    return AiContent(role: content.role ?? 'unknown', parts: domainParts);
  }

  /// Extracts the text from all TextParts, joined together.
  String get text => parts.whereType<AiTextPart>().map((p) => p.text).join();

  /// Checks if this content has a function call part and returns the first one if it exists
  AiFunctionCallPart? get functionCall =>
      parts.whereType<AiFunctionCallPart>().firstOrNull;

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

/// Represents a potential response candidate from the AI.
@immutable
class AiCandidate {
  final AiContent content;

  const AiCandidate({required this.content});

  /// Creates from Google Generative AI SDK candidate
  static AiCandidate fromGoogleGenAi(Candidate candidate) =>
      AiCandidate(content: AiContent.fromGoogleGenAi(candidate.content));

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

  const AiResponse({required this.candidates});

  /// Creates from Google Generative AI SDK response
  static AiResponse fromGoogleGenAi(GenerateContentResponse response) {
    final domainCandidates =
        response.candidates.map(AiCandidate.fromGoogleGenAi).toList();
    return AiResponse(candidates: domainCandidates);
  }

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
@immutable
class AiStreamChunk {
  final String textDelta;

  const AiStreamChunk({required this.textDelta});

  /// Creates from Google Generative AI SDK chunk
  static AiStreamChunk fromGoogleGenAi(GenerateContentResponse chunk) =>
      AiStreamChunk(textDelta: chunk.text ?? "");

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiStreamChunk &&
          runtimeType == other.runtimeType &&
          textDelta == other.textDelta;

  @override
  int get hashCode => textDelta.hashCode;
}
