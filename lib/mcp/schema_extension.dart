import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// Helper Extension to convert JSON schema definitions to GenerativeAI Schema objects
/// Used for parsing MCP tool schemas
extension SchemaExtension on Schema {
  /// Converts a JSON object to a Schema object for use with GenerativeAI
  /// Returns null if conversion fails or schema is invalid
  static Schema? fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    final description = json['description'] as String?;

    switch (type) {
      case 'object':
        final properties = json['properties'] as Map<String, dynamic>?;
        if (properties == null || properties.isEmpty) {
          return null;
        }
        try {
          return Schema.object(
            properties: properties.map(
              (key, value) => MapEntry(
                key,
                SchemaExtension.fromJson(value as Map<String, dynamic>)!,
              ),
            ),
            requiredProperties: properties.keys.toList(),
            description: description,
          );
        } catch (e) {
          debugPrint(
            "Error parsing object properties for schema: $json. Error: $e",
          );
          throw FormatException(
            "Invalid properties definition in object schema",
            json,
          );
        }
      case 'string':
        final enumValues = (json['enum'] as List<dynamic>?)?.cast<String>();
        return enumValues != null
            ? Schema.enumString(
              enumValues: enumValues,
              description: description,
            )
            : Schema.string(description: description);
      case 'number':
      case 'integer':
        return Schema.number(description: description);
      case 'boolean':
        return Schema.boolean(description: description);
      case 'array':
        final items = json['items'] as Map<String, dynamic>?;
        if (items == null) {
          throw FormatException(
            "Array schema must have an 'items' definition.",
            json,
          );
        }
        try {
          return Schema.array(
            items: SchemaExtension.fromJson(items)!,
            description: description,
          );
        } catch (e) {
          debugPrint("Error parsing array items for schema: $json. Error: $e");
          throw FormatException(
            "Invalid 'items' definition in array schema",
            json,
          );
        }
      default:
        debugPrint("Unsupported schema type encountered: $type");
        throw UnsupportedError("Unsupported schema type: $type");
    }
  }
}
