// lib/mcp_server_config.dart
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart'; // For MapEquality

@immutable
class McpServerConfig {
  final String id; // Unique ID
  final String name;
  final String command;
  final String args;
  final bool isActive;
  // New: Custom environment variables for this server
  final Map<String, String> customEnvironment;

  const McpServerConfig({
    required this.id,
    required this.name,
    required this.command,
    required this.args,
    this.isActive = false,
    this.customEnvironment = const {}, // Default to empty map
  });

  // Method to create a copy with updated values
  McpServerConfig copyWith({
    String? id,
    String? name,
    String? command,
    String? args,
    bool? isActive,
    Map<String, String>? customEnvironment, // Allow updating environment
  }) {
    return McpServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      command: command ?? this.command,
      args: args ?? this.args,
      isActive: isActive ?? this.isActive,
      customEnvironment:
          customEnvironment ?? this.customEnvironment, // Update env
    );
  }

  // For saving/loading from SharedPreferences via JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'command': command,
    'args': args,
    'isActive': isActive,
    'customEnvironment': customEnvironment, // Include custom env
  };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    // Safely parse the custom environment map
    Map<String, String> environment = {};
    if (json['customEnvironment'] is Map) {
      try {
        // Ensure keys and values are strings
        environment = Map<String, String>.from(
          (json['customEnvironment'] as Map).map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ),
        );
      } catch (e) {
        debugPrint(
          "Error parsing customEnvironment for server ${json['id']}: $e",
        );
        // Keep environment as empty map on error
      }
    }

    return McpServerConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      command: json['command'] as String,
      args: json['args'] as String,
      isActive: json['isActive'] as bool? ?? false,
      customEnvironment: environment, // Use parsed map
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is McpServerConfig &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          command == other.command &&
          args == other.args &&
          isActive == other.isActive &&
          // Compare environment maps
          const MapEquality().equals(
            customEnvironment,
            other.customEnvironment,
          );

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      command.hashCode ^
      args.hashCode ^
      isActive.hashCode ^
      // Include environment map hash
      const MapEquality().hash(customEnvironment);
}
