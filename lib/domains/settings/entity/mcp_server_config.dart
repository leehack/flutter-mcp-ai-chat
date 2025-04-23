import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart'; // For MapEquality

/// Configuration for a single MCP server.
@immutable
class McpServerConfig {
  final String id; // Unique ID
  final String name;
  final String command;
  final String args;
  final bool isActive; // User's desired state (connect on apply)
  final Map<String, String> customEnvironment;

  const McpServerConfig({
    required this.id,
    required this.name,
    required this.command,
    required this.args,
    this.isActive = false,
    this.customEnvironment = const {},
  });

  McpServerConfig copyWith({
    String? id,
    String? name,
    String? command,
    String? args,
    bool? isActive,
    Map<String, String>? customEnvironment,
  }) {
    return McpServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      command: command ?? this.command,
      args: args ?? this.args,
      isActive: isActive ?? this.isActive,
      customEnvironment: customEnvironment ?? this.customEnvironment,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'command': command,
    'args': args,
    'isActive': isActive,
    'customEnvironment': customEnvironment,
  };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    Map<String, String> environment = {};
    if (json['customEnvironment'] is Map) {
      try {
        environment = Map<String, String>.from(
          (json['customEnvironment'] as Map).map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ),
        );
      } catch (e) {
        debugPrint(
          "Error parsing customEnvironment for server ${json['id']}: $e",
        );
      }
    }

    return McpServerConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      command: json['command'] as String,
      args: json['args'] as String,
      isActive: json['isActive'] as bool? ?? false,
      customEnvironment: environment,
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
      const MapEquality().hash(customEnvironment);
}
