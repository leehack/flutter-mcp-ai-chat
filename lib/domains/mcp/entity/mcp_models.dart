import 'package:flutter/foundation.dart';
// No AI or Settings imports needed here.

// --- Tool Definition ---

/// Represents the definition of a tool discovered via MCP.
/// The schema is kept as a raw Map, as defined by the MCP server.
@immutable
class McpToolDefinition {
  final String name;
  final String? description;
  final Map<String, dynamic> inputSchema; // Raw JSON schema as Map

  const McpToolDefinition({
    required this.name,
    this.description,
    required this.inputSchema,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is McpToolDefinition &&
          runtimeType == other.runtimeType &&
          name == other.name; // Simple equality based on name for now

  @override
  int get hashCode => name.hashCode;
}

// --- Tool Result Content Structure (Based on user provided code) ---

/// Placeholder for ResourceContents if not defined elsewhere.
/// Replace with actual definition if available.
@immutable
class ResourceContents {
  final String placeholder; // Example field
  const ResourceContents({this.placeholder = "resource_placeholder"});
  factory ResourceContents.fromJson(Map<String, dynamic> json) {
    return ResourceContents(
      placeholder: json['placeholder'] ?? "resource_placeholder",
    );
  }
  Map<String, dynamic> toJson() => {'placeholder': placeholder};
}

/// Base class for structured content returned by MCP tools.
@immutable
sealed class McpContent {
  /// The type of the content part (e.g., 'text', 'image').
  final String type;

  /// Additional properties not part of the standard structure.
  final Map<String, dynamic> additionalProperties;

  const McpContent({required this.type, this.additionalProperties = const {}});

  /// Creates a specific McpContent instance from a JSON map.
  /// This factory determines the subtype based on the 'type' field.
  factory McpContent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    // Create a mutable copy to remove processed keys
    final Map<String, dynamic> remainingProperties = Map.from(json);
    remainingProperties.remove('type'); // Remove type after reading

    try {
      // Add try-catch for robustness during parsing
      switch (type) {
        case 'text':
          remainingProperties.remove('text'); // Remove known keys
          return McpTextContent(
            text: json['text'] as String,
            additionalProperties: remainingProperties,
          );
        case 'image':
          remainingProperties.remove('data');
          remainingProperties.remove('mimeType');
          return McpImageContent(
            data: json['data'] as String,
            mimeType: json['mimeType'] as String,
            additionalProperties: remainingProperties,
          );
        case 'resource':
          remainingProperties.remove('resource');
          return McpEmbeddedResource(
            resource: ResourceContents.fromJson(
              json['resource'] as Map<String, dynamic>,
            ),
            additionalProperties: remainingProperties,
          );
        default:
          // Keep all properties for unknown types
          return McpUnknownContent(
            type: type ?? 'unknown',
            additionalProperties: remainingProperties, // Pass the rest
          );
      }
    } catch (e, stackTrace) {
      debugPrint("Error parsing McpContent (type: $type): $e\n$stackTrace");
      // Fallback to UnknownContent on parsing error
      return McpUnknownContent(
        type: type ?? 'error',
        additionalProperties: {'error': e.toString(), ...remainingProperties},
      );
    }
  }

  /// Converts this McpContent instance back to a JSON map.
  Map<String, dynamic> toJson() => {
    'type': type,
    // Add type-specific properties
    ...switch (this) {
      McpTextContent c => {'text': c.text},
      McpImageContent c => {'data': c.data, 'mimeType': c.mimeType},
      McpEmbeddedResource c => {'resource': c.resource.toJson()},
      McpUnknownContent _ =>
        {}, // Unknown types only have additional props stored
    },
    // Add any additional properties
    ...additionalProperties,
  };
}

/// Text content.
class McpTextContent extends McpContent {
  /// The text string.
  final String text;

  const McpTextContent({required this.text, super.additionalProperties})
    : super(type: 'text');
}

/// Image content.
class McpImageContent extends McpContent {
  /// Base64 encoded image data.
  final String data;

  /// MIME type of the image (e.g., "image/png").
  final String mimeType;

  const McpImageContent({
    required this.data,
    required this.mimeType,
    super.additionalProperties,
  }) : super(type: 'image');
}

/// Content embedding a resource.
class McpEmbeddedResource extends McpContent {
  /// The embedded resource contents.
  final ResourceContents resource;

  const McpEmbeddedResource({
    required this.resource,
    super.additionalProperties,
  }) : super(type: 'resource');
}

/// Represents unknown or passthrough content types.
class McpUnknownContent extends McpContent {
  const McpUnknownContent({required super.type, super.additionalProperties});
}

// --- Tool Result ---

/// Represents the structured result of an MCP tool execution.
@immutable
class McpToolResult {
  /// A list of content parts returned by the tool.
  final List<McpContent> content;

  const McpToolResult({required this.content});

  /// Convenience getter for the first text content part, if any.
  String? get firstText {
    final textContent = content.whereType<McpTextContent>().firstOrNull;
    return textContent?.text;
  }

  /// Convenience getter for the first image content part, if any.
  McpImageContent? get firstImage {
    return content.whereType<McpImageContent>().firstOrNull;
  }

  /// Convenience getter for the first embedded resource part, if any.
  McpEmbeddedResource? get firstResource {
    return content.whereType<McpEmbeddedResource>().firstOrNull;
  }

  /// Checks if the result contains any content parts.
  bool get isEmpty => content.isEmpty;

  /// Checks if the result contains only a single text part.
  bool get isSingleText =>
      content.length == 1 && content.first is McpTextContent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is McpToolResult &&
          runtimeType == other.runtimeType &&
          listEquals(content, other.content); // Compare lists

  @override
  int get hashCode => Object.hashAll(content); // Hash based on list content
}

// --- Connection & State ---

/// Connection status for an MCP server.
enum McpConnectionStatus { disconnected, connecting, connected, error }

/// Immutable state representing the overall MCP client system.
/// Managed by the McpRepository implementation and broadcasted.
@immutable
class McpClientState {
  /// Map of server IDs to their connection status.
  final Map<String, McpConnectionStatus> serverStatuses;

  /// Map of server IDs to the list of tools they provide.
  final Map<String, List<McpToolDefinition>> discoveredTools;

  /// Map of server IDs to error messages (if in error state).
  final Map<String, String> serverErrorMessages;

  const McpClientState({
    this.serverStatuses = const {},
    this.discoveredTools = const {},
    this.serverErrorMessages = const {},
  });

  /// Checks if any server is currently connected.
  bool get hasActiveConnections =>
      serverStatuses.values.any((s) => s == McpConnectionStatus.connected);

  /// Gets the count of currently connected servers.
  int get connectedServerCount =>
      serverStatuses.values
          .where((s) => s == McpConnectionStatus.connected)
          .length;

  /// Gets a flattened list of all unique tool names available across connected servers.
  /// Handles potential name collisions by excluding duplicates.
  List<String> get uniqueAvailableToolNames {
    final uniqueNames = <String>{};
    final duplicateNames = <String>{};
    discoveredTools.values.expand((tools) => tools).forEach((tool) {
      if (!uniqueNames.add(tool.name)) {
        duplicateNames.add(tool.name);
      }
    });
    // Remove duplicates from the unique set
    uniqueNames.removeAll(duplicateNames);
    return uniqueNames.toList();
  }

  /// Finds the server ID for a uniquely named tool.
  /// Returns null if the tool name is not found or has duplicates.
  String? getServerIdForTool(String toolName) {
    String? foundServerId;
    int foundCount = 0;
    for (var entry in discoveredTools.entries) {
      if (entry.value.any((tool) => tool.name == toolName)) {
        foundServerId = entry.key;
        foundCount++;
      }
      if (foundCount > 1) return null; // Duplicate found
    }
    return foundCount == 1 ? foundServerId : null;
  }

  McpClientState copyWith({
    Map<String, McpConnectionStatus>? serverStatuses,
    Map<String, List<McpToolDefinition>>? discoveredTools,
    Map<String, String>? serverErrorMessages,
    // Helpers for removing entries safely during updates
    List<String>? removeStatusIds,
    List<String>? removeToolsIds,
    List<String>? removeErrorIds,
  }) {
    final newStatuses = Map<String, McpConnectionStatus>.from(
      serverStatuses ?? this.serverStatuses,
    );
    final newTools = Map<String, List<McpToolDefinition>>.from(
      discoveredTools ?? this.discoveredTools,
    );
    final newErrors = Map<String, String>.from(
      serverErrorMessages ?? this.serverErrorMessages,
    );

    // Apply removals
    removeStatusIds?.forEach(newStatuses.remove);
    removeToolsIds?.forEach(newTools.remove);
    removeErrorIds?.forEach(newErrors.remove);

    return McpClientState(
      serverStatuses: newStatuses,
      discoveredTools: newTools,
      serverErrorMessages: newErrors,
    );
  }
}
