// lib/mcp_client.dart (Auto-Connect Active Servers on Startup)
import 'dart:async';
// For jsonEncode
import 'dart:io'; // Needed for Platform.environment
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp_dart;
// Removed: import 'package:process_run/shell.dart'; // No longer needed

import 'gemini_service.dart';
import 'settings_service.dart';
import 'mcp_server_config.dart';

// --- Helper Extension (Schema parsing - unchanged) ---
extension SchemaExtension on Schema {
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

// --- Result Type (unchanged) ---
@immutable
class McpProcessResult {
  final Content? modelCallContent;
  final Content? toolResponseContent;
  final Content finalModelContent;
  final String? toolName;
  final Map<String, dynamic>? toolArgs;
  final String? toolResult;
  final String? sourceServerId;

  const McpProcessResult({
    required this.finalModelContent,
    this.modelCallContent,
    this.toolResponseContent,
    this.toolName,
    this.toolArgs,
    this.toolResult,
    this.sourceServerId,
  });
}

// --- Single MCP Client Logic ---
class GoogleMcpClient {
  final String serverId;
  final mcp_dart.Client mcp;
  final GenerativeModel model;
  mcp_dart.StdioClientTransport? _transport;
  List<Tool> _tools = [];
  bool _isConnected = false;
  Function(String serverId, String errorMsg)? _onError;
  Function(String serverId)? _onClose;

  bool get isConnected => _isConnected;
  List<Tool> get availableTools => List.unmodifiable(_tools);

  GoogleMcpClient(this.serverId, this.model)
    : mcp = mcp_dart.Client(
        mcp_dart.Implementation(name: "gemini-client", version: "1.0.0"),
      );

  void setupCallbacks({
    Function(String serverId, String errorMsg)? onError,
    Function(String serverId)? onClose,
  }) {
    _onError = onError;
    _onClose = onClose;
  }

  Future<void> connectToServer(
    String command,
    List<String> args,
    Map<String, String> environment,
  ) async {
    if (_isConnected) return;
    if (command.trim().isEmpty) throw Exception("MCP command cannot be empty.");
    debugPrint(
      "GoogleMcpClient [$serverId]: Attempting connection: $command ${args.join(' ')}",
    );
    // Avoid logging entire environment for security/verbosity
    // debugPrint("GoogleMcpClient [$serverId]: With Environment Keys: ${environment.keys.join(', ')}");
    try {
      _transport = mcp_dart.StdioClientTransport(
        mcp_dart.StdioServerParameters(
          command: command,
          args: args,
          environment: environment,
          stderrMode: ProcessStartMode.normal,
        ),
      );
      _transport!.onerror = (error) {
        final errorMsg = "MCP Transport error [$serverId]: $error";
        debugPrint(errorMsg);
        _isConnected = false;
        _onError?.call(serverId, errorMsg);
        cleanup();
      };
      _transport!.onclose = () {
        debugPrint("MCP Transport closed [$serverId].");
        _isConnected = false;
        _onClose?.call(serverId);
        _transport = null;
        _tools = [];
      };
      await mcp.connect(_transport!);
      _isConnected = true;
      debugPrint("GoogleMcpClient [$serverId]: Connected successfully.");
      await _fetchTools();
    } catch (e) {
      debugPrint("GoogleMcpClient [$serverId]: Failed to connect: $e");
      _isConnected = false;
      await cleanup();
      rethrow;
    }
  }

  Future<void> _fetchTools() async {
    if (!_isConnected) {
      _tools = [];
      return;
    }
    debugPrint("GoogleMcpClient [$serverId]: Fetching tools...");
    try {
      final toolsResult = await mcp.listTools();
      List<Tool> fetchedTools = [];
      for (var toolDef in toolsResult.tools) {
        // debugPrint("GoogleMcpClient [$serverId]: Processing tool: ${toolDef.name}"); // Can be verbose
        try {
          final schemaJson = toolDef.inputSchema.toJson();
          final schema = SchemaExtension.fromJson(schemaJson);
          if (schema != null ||
              (schemaJson['type'] == 'object' &&
                  (schemaJson['properties'] == null ||
                      (schemaJson['properties'] as Map).isEmpty))) {
            fetchedTools.add(
              Tool(
                functionDeclarations: [
                  FunctionDeclaration(
                    toolDef.name,
                    toolDef.description ?? 'No description provided.',
                    schema,
                  ),
                ],
              ),
            );
          } else {
            debugPrint(
              "Warning [$serverId]: Skipping tool '${toolDef.name}' due to unexpected null schema.",
            );
          }
        } catch (e) {
          debugPrint(
            "Error processing schema for tool '${toolDef.name}' [$serverId]: $e. Skipping tool.",
          );
        }
      }
      _tools = fetchedTools;
      debugPrint(
        "GoogleMcpClient [$serverId]: Successfully processed ${_tools.length} tools.",
      );
    } catch (e) {
      debugPrint("GoogleMcpClient [$serverId]: Failed to fetch MCP tools: $e");
      _tools = [];
    }
  }

  Future<mcp_dart.CallToolResult> callTool(
    mcp_dart.CallToolRequestParams params,
  ) async {
    if (!_isConnected) {
      throw Exception("Client [$serverId] is not connected.");
    }
    debugPrint(
      "GoogleMcpClient [$serverId]: Executing tool '${params.name}'...",
    );
    return await mcp.callTool(params);
  }

  Future<void> cleanup() async {
    if (_transport != null) {
      debugPrint("GoogleMcpClient [$serverId]: Cleaning up transport...");
      try {
        await _transport!.close();
      } catch (e) {
        debugPrint("GoogleMcpClient [$serverId]: Error closing transport: $e");
      }
      _transport = null;
    }
    _isConnected = false;
    _tools = [];
    debugPrint("GoogleMcpClient [$serverId]: Cleanup complete.");
  }
}

// --- Riverpod Provider State and Notifier ---

enum McpConnectionStatus { disconnected, connecting, connected, error }

@immutable
class McpClientState {
  final List<McpServerConfig> serverConfigs;
  final Map<String, McpConnectionStatus> serverStatuses;
  final Map<String, GoogleMcpClient> activeClients;
  final Map<String, String> serverErrorMessages;

  const McpClientState({
    this.serverConfigs = const [],
    this.serverStatuses = const {},
    this.activeClients = const {},
    this.serverErrorMessages = const {},
  });

  bool get hasActiveConnections =>
      serverStatuses.values.any((s) => s == McpConnectionStatus.connected);
  int get connectedServerCount =>
      serverStatuses.values
          .where((s) => s == McpConnectionStatus.connected)
          .length;

  McpClientState copyWith({
    List<McpServerConfig>? serverConfigs,
    Map<String, McpConnectionStatus>? serverStatuses,
    Map<String, GoogleMcpClient>? activeClients,
    Map<String, String>? serverErrorMessages,
    List<String>? removeClientIds,
    List<String>? removeStatusIds,
    List<String>? removeErrorIds,
  }) {
    final newStatuses = Map<String, McpConnectionStatus>.from(
      serverStatuses ?? this.serverStatuses,
    );
    final newClients = Map<String, GoogleMcpClient>.from(
      activeClients ?? this.activeClients,
    );
    final newErrors = Map<String, String>.from(
      serverErrorMessages ?? this.serverErrorMessages,
    );

    removeClientIds?.forEach(newClients.remove);
    removeStatusIds?.forEach(newStatuses.remove);
    removeErrorIds?.forEach(newErrors.remove);

    return McpClientState(
      serverConfigs: serverConfigs ?? this.serverConfigs,
      serverStatuses: newStatuses,
      activeClients: newClients,
      serverErrorMessages: newErrors,
    );
  }
}

// Manages the McpClientState, handling multiple connections
class McpClientNotifier extends StateNotifier<McpClientState> {
  final Ref _ref;
  Map<String, String> _toolToServerIdMap = {};

  McpClientNotifier(this._ref) : super(const McpClientState()) {
    // 1. Initialize state with server configs loaded in main.dart
    final initialConfigs = _ref.read(mcpServerListProvider);
    final initialStatuses = <String, McpConnectionStatus>{};
    for (var config in initialConfigs) {
      initialStatuses[config.id] = McpConnectionStatus.disconnected;
    }
    state = state.copyWith(
      serverConfigs: initialConfigs,
      serverStatuses: initialStatuses,
    );

    // 2. Listen for future changes in the server list from settings
    _ref.listen<List<McpServerConfig>>(mcpServerListProvider, (
      previousList,
      newList,
    ) {
      debugPrint(
        "McpClientNotifier: Server list updated in settings. Syncing connections...",
      );
      // Update internal list and sync connections based on isActive flags
      state = state.copyWith(serverConfigs: newList);
      syncConnections(); // Trigger connection/disconnection logic
    });

    // 3. *** Trigger initial connection sync after initialization ***
    // Use a microtask to ensure this runs after the constructor completes
    // but before the next frame, allowing initial state to settle.
    Future.microtask(() {
      debugPrint("McpClientNotifier: Triggering initial connection sync...");
      syncConnections();
    });
  }

  // --- Connection Management ---

  Future<void> _connectServer(McpServerConfig serverConfig) async {
    final serverId = serverConfig.id;
    if (state.activeClients.containsKey(serverId) ||
        state.serverStatuses[serverId] == McpConnectionStatus.connecting) {
      // debugPrint("MCP [$serverId]: Already connected or connecting."); // Can be verbose
      return;
    }

    final geminiService = _ref.read(geminiServiceProvider);
    if (geminiService == null ||
        !geminiService.isInitialized ||
        geminiService.model == null) {
      _updateServerState(
        serverId,
        McpConnectionStatus.error,
        errorMsg: "Gemini service not ready.",
      );
      return;
    }
    if (serverConfig.command.trim().isEmpty) {
      _updateServerState(
        serverId,
        McpConnectionStatus.error,
        errorMsg: "Server command is empty.",
      );
      return;
    }

    _updateServerState(serverId, McpConnectionStatus.connecting);
    GoogleMcpClient? newClientInstance;

    try {
      // Prepare Environment
      final Map<String, String> combinedEnvironment = Map.from(
        Platform.environment,
      );
      combinedEnvironment.addAll(serverConfig.customEnvironment);

      // Use original command and args
      final command = serverConfig.command;
      final argsList =
          serverConfig.args.split(' ').where((s) => s.isNotEmpty).toList();

      newClientInstance = GoogleMcpClient(serverId, geminiService.model!);
      newClientInstance.setupCallbacks(
        onError: _handleClientError,
        onClose: _handleClientClose,
      );

      await newClientInstance.connectToServer(
        command,
        argsList,
        combinedEnvironment,
      );

      if (newClientInstance.isConnected) {
        final newClients = Map<String, GoogleMcpClient>.from(
          state.activeClients,
        );
        newClients[serverId] = newClientInstance;
        state = state.copyWith(
          activeClients: newClients,
          serverStatuses: {
            ...state.serverStatuses,
            serverId: McpConnectionStatus.connected,
          },
          serverErrorMessages: {...state.serverErrorMessages}..remove(serverId),
        );
        debugPrint(
          "MCP [$serverId]: Connected successfully to ${serverConfig.name}.",
        );
        _rebuildToolMap();
      } else {
        if (state.serverStatuses[serverId] != McpConnectionStatus.error) {
          _updateServerState(
            serverId,
            McpConnectionStatus.error,
            errorMsg: "Connection failed post-attempt.",
          );
        }
        await newClientInstance.cleanup();
      }
    } catch (e) {
      debugPrint("MCP [$serverId]: Connection failed: $e");
      if (state.serverStatuses[serverId] != McpConnectionStatus.error) {
        _updateServerState(
          serverId,
          McpConnectionStatus.error,
          errorMsg: "Connection failed: $e",
        );
      }
      await newClientInstance?.cleanup();
    }
  }

  Future<void> _disconnectServer(String serverId) async {
    final clientToDisconnect = state.activeClients[serverId];
    if (clientToDisconnect == null) {
      if (state.serverStatuses[serverId] != McpConnectionStatus.disconnected) {
        _updateServerState(serverId, McpConnectionStatus.disconnected);
      }
      return;
    }
    debugPrint("MCP [$serverId]: Disconnecting...");
    _updateServerState(serverId, McpConnectionStatus.disconnected);
    await clientToDisconnect.cleanup();

    final newClients = Map<String, GoogleMcpClient>.from(state.activeClients);
    if (newClients.remove(serverId) != null) {
      state = state.copyWith(activeClients: newClients);
      debugPrint("MCP [$serverId]: Disconnect process complete.");
      _rebuildToolMap();
    }
  }

  // Public method to sync connections based on current config
  void syncConnections() {
    final desiredActiveServers =
        state.serverConfigs.where((s) => s.isActive).map((s) => s.id).toSet();
    final currentlyConnectedServers = state.activeClients.keys.toSet();

    // Connect servers that are desired but not connected/connecting
    final serversToConnect =
        desiredActiveServers
            .where(
              (id) =>
                  !currentlyConnectedServers.contains(id) &&
                  state.serverStatuses[id] != McpConnectionStatus.connecting,
            )
            .toSet();

    // Disconnect servers that are connected but no longer desired
    final serversToDisconnect = currentlyConnectedServers.difference(
      desiredActiveServers,
    );
    // Disconnect servers whose config has been deleted entirely
    final knownServerIds = state.serverConfigs.map((s) => s.id).toSet();
    final serversToDelete = currentlyConnectedServers.difference(
      knownServerIds,
    );

    // Combine disconnect lists
    final allServersToDisconnect = serversToDisconnect.union(serversToDelete);

    if (serversToConnect.isNotEmpty || allServersToDisconnect.isNotEmpty) {
      debugPrint("Syncing MCP Connections:");
      if (serversToConnect.isNotEmpty) {
        debugPrint(" - To Connect: ${serversToConnect.join(', ')}");
      }
      if (allServersToDisconnect.isNotEmpty) {
        debugPrint(" - To Disconnect: ${allServersToDisconnect.join(', ')}");
      }
    } else {
      // debugPrint("Syncing MCP Connections: No changes needed."); // Can be verbose
    }

    for (final serverId in serversToConnect) {
      final config = state.serverConfigs.firstWhereOrNull(
        (s) => s.id == serverId,
      );
      if (config != null) {
        _connectServer(config); // Don't await, let them connect concurrently
      } else {
        _updateServerState(
          serverId,
          McpConnectionStatus.error,
          errorMsg: "Config not found during sync.",
        );
      }
    }

    for (final serverId in allServersToDisconnect) {
      _disconnectServer(serverId); // Don't await
      // Clean up status/error if the config was actually deleted
      if (serversToDelete.contains(serverId)) {
        state = state.copyWith(
          removeStatusIds: [serverId],
          removeErrorIds: [serverId],
        );
      }
    }

    // Clean up statuses/errors for servers no longer in config list at all
    final currentStatusIds = state.serverStatuses.keys.toSet();
    final statusesToRemove = currentStatusIds.difference(knownServerIds);
    if (statusesToRemove.isNotEmpty) {
      debugPrint(
        "MCP: Removing stale statuses/errors for IDs: ${statusesToRemove.join(', ')}",
      );
      state = state.copyWith(
        removeStatusIds: statusesToRemove.toList(),
        removeErrorIds: statusesToRemove.toList(),
      );
    }
  }

  // --- State Update Helpers ---
  void _updateServerState(
    String serverId,
    McpConnectionStatus status, {
    String? errorMsg,
  }) {
    // Prevent state updates if the notifier is disposed, though less critical now
    if (!mounted) return;

    final newStatuses = Map<String, McpConnectionStatus>.from(
      state.serverStatuses,
    );
    final newErrors = Map<String, String>.from(state.serverErrorMessages);

    newStatuses[serverId] = status;
    if (errorMsg != null) {
      newErrors[serverId] = errorMsg;
    } else {
      if (status != McpConnectionStatus.error) {
        newErrors.remove(serverId);
      }
    }

    final newClients = Map<String, GoogleMcpClient>.from(state.activeClients);
    bool clientRemoved = false;
    if (status != McpConnectionStatus.connected &&
        status != McpConnectionStatus.connecting) {
      if (newClients.remove(serverId) != null) {
        // debugPrint("MCP [$serverId]: Removing client reference due to status change to $status"); // Verbose
        clientRemoved = true;
      }
    }

    state = state.copyWith(
      serverStatuses: newStatuses,
      serverErrorMessages: newErrors,
      activeClients: newClients,
    );

    if (clientRemoved) {
      _rebuildToolMap();
    }
  }

  void _handleClientError(String serverId, String errorMsg) {
    debugPrint("MCP [$serverId]: Received error callback: $errorMsg");
    _updateServerState(serverId, McpConnectionStatus.error, errorMsg: errorMsg);
  }

  void _handleClientClose(String serverId) {
    debugPrint("MCP [$serverId]: Received close callback.");
    bool clientWasRemoved = false;
    final newClients = Map<String, GoogleMcpClient>.from(state.activeClients);
    if (newClients.remove(serverId) != null) {
      clientWasRemoved = true;
    }

    if (state.serverStatuses[serverId] != McpConnectionStatus.error) {
      _updateServerState(serverId, McpConnectionStatus.disconnected);
    }

    if (clientWasRemoved) {
      state = state.copyWith(activeClients: newClients);
      _rebuildToolMap();
    }
  }

  // --- Tool Management ---
  void _rebuildToolMap() {
    final newToolMap = <String, String>{};
    final Set<String> uniqueToolNames = {};
    final List<String> duplicateToolNames = [];
    final currentClientIds = List<String>.from(state.activeClients.keys);

    for (final serverId in currentClientIds) {
      final client = state.activeClients[serverId];
      if (client != null && client.isConnected) {
        for (final tool in client.availableTools) {
          for (final funcDec in tool.functionDeclarations ?? []) {
            if (newToolMap.containsKey(funcDec.name)) {
              if (!duplicateToolNames.contains(funcDec.name)) {
                duplicateToolNames.add(funcDec.name);
              }
              // debugPrint("MCP Warning: Duplicate tool name: '${funcDec.name}' on $serverId (exists on ${newToolMap[funcDec.name]})."); // Verbose
            } else {
              newToolMap[funcDec.name] = serverId;
              uniqueToolNames.add(funcDec.name);
            }
          }
        }
      }
    }
    _toolToServerIdMap = newToolMap;
    if (duplicateToolNames.isNotEmpty) {
      debugPrint(
        "MCP: Rebuilt tool map. ${uniqueToolNames.length} unique tools. Duplicates found: ${duplicateToolNames.join(', ')}",
      );
    } else {
      // debugPrint("MCP: Rebuilt tool map. ${uniqueToolNames.length} unique tools."); // Verbose
    }
  }

  List<Tool> _getAggregatedTools() {
    final aggregatedTools = <Tool>[];
    final handledToolNames = <String>{};
    final currentClientIds = List<String>.from(state.activeClients.keys);

    for (final serverId in currentClientIds) {
      final client = state.activeClients[serverId];
      if (client != null && client.isConnected) {
        for (final tool in client.availableTools) {
          final uniqueDeclarations =
              tool.functionDeclarations
                  ?.where(
                    (fd) =>
                        _toolToServerIdMap[fd.name] == serverId &&
                        !handledToolNames.contains(fd.name),
                  )
                  .toList();

          if (uniqueDeclarations != null && uniqueDeclarations.isNotEmpty) {
            aggregatedTools.add(Tool(functionDeclarations: uniqueDeclarations));
            handledToolNames.addAll(uniqueDeclarations.map((fd) => fd.name));
          }
        }
      }
    }
    // debugPrint("MCP: Aggregated ${handledToolNames.length} unique function declarations for Gemini."); // Verbose
    return aggregatedTools;
  }

  // --- Query Processing ---
  Future<McpProcessResult> processQuery(
    String query,
    List<Content> history,
  ) async {
    // ... (processQuery logic remains the same) ...
    if (state.activeClients.isEmpty) {
      return McpProcessResult(
        finalModelContent: Content('model', [
          TextPart("Error: No MCP servers connected."),
        ]),
      );
    }
    final geminiService = _ref.read(geminiServiceProvider);
    if (geminiService == null ||
        !geminiService.isInitialized ||
        geminiService.model == null) {
      return McpProcessResult(
        finalModelContent: Content('model', [
          TextPart("Error: Gemini service not ready."),
        ]),
      );
    }
    final currentMessages = [
      ...history,
      Content('user', [TextPart(query)]),
    ];
    final aggregatedTools = _getAggregatedTools();
    debugPrint(
      "MCP: Sending query to Gemini with ${aggregatedTools.length} aggregated tools available.",
    );
    try {
      final response = await geminiService.model!.generateContent(
        currentMessages,
        tools: aggregatedTools.isNotEmpty ? aggregatedTools : null,
      );
      final candidate = response.candidates.firstOrNull;
      if (candidate == null) {
        final blockReason = response.promptFeedback?.blockReason;
        return McpProcessResult(
          finalModelContent: Content('model', [
            TextPart("Response blocked: ${blockReason ?? 'Unknown reason'}"),
          ]),
        );
      }
      final firstModelContent = candidate.content;
      final functionCalls =
          firstModelContent.parts.whereType<FunctionCall>().toList();
      if (functionCalls.isNotEmpty) {
        final call = functionCalls.first;
        final toolName = call.name;
        final targetServerId = _toolToServerIdMap[toolName];
        if (targetServerId == null) {
          final errorMsg =
              "Error: AI requested tool '$toolName' which is not available or has conflicting names across servers.";
          debugPrint("MCP: $errorMsg");
          return McpProcessResult(
            modelCallContent: firstModelContent,
            finalModelContent: Content('model', [TextPart(errorMsg)]),
            toolName: toolName,
            toolArgs: call.args,
          );
        }
        final targetClient = state.activeClients[targetServerId];
        if (targetClient == null || !targetClient.isConnected) {
          final errorMsg =
              "Error: Client for tool '$toolName' (Server $targetServerId) is not connected or became disconnected.";
          debugPrint("MCP: $errorMsg");
          return McpProcessResult(
            modelCallContent: firstModelContent,
            finalModelContent: Content('model', [TextPart(errorMsg)]),
            toolName: toolName,
            toolArgs: call.args,
            sourceServerId: targetServerId,
          );
        }
        debugPrint(
          "MCP: Routing tool call '$toolName' to server $targetServerId",
        );
        try {
          final result = await targetClient.callTool(
            mcp_dart.CallToolRequestParams(
              name: toolName,
              arguments: call.args,
            ),
          );
          final toolResponseText = result.content
              .whereType<mcp_dart.TextContent>()
              .map((c) => c.text)
              .join('\n');
          debugPrint(
            "MCP: Tool '$toolName' executed on server $targetServerId.",
          );
          final functionResponsePart = FunctionResponse(toolName, {
            'result': toolResponseText,
          });
          final toolResponseContent = Content('tool', [functionResponsePart]);
          final messagesForFinalResponse = [
            ...currentMessages,
            firstModelContent,
            toolResponseContent,
          ];
          debugPrint("MCP: Sending tool response back to Gemini...");
          final finalRes = await geminiService.model!.generateContent(
            messagesForFinalResponse,
          );
          final finalCandidate = finalRes.candidates.firstOrNull;
          Content finalModelContent;
          if (finalCandidate == null) {
            final finalBlockReason = finalRes.promptFeedback?.blockReason;
            finalModelContent = Content('model', [
              TextPart(
                "Response blocked after tool call: ${finalBlockReason ?? 'Unknown reason'}",
              ),
            ]);
          } else {
            finalModelContent = finalCandidate.content;
          }
          return McpProcessResult(
            modelCallContent: firstModelContent,
            toolResponseContent: toolResponseContent,
            finalModelContent: finalModelContent,
            toolName: toolName,
            toolArgs: call.args,
            toolResult: toolResponseText,
            sourceServerId: targetServerId,
          );
        } catch (e) {
          final errorMsg =
              "Error executing tool '$toolName' on server $targetServerId: $e";
          debugPrint("MCP: $errorMsg");
          _updateServerState(
            targetServerId,
            McpConnectionStatus.error,
            errorMsg: "Tool execution failed: $e",
          );
          return McpProcessResult(
            modelCallContent: firstModelContent,
            finalModelContent: Content('model', [TextPart(errorMsg)]),
            toolName: toolName,
            toolArgs: call.args,
            sourceServerId: targetServerId,
          );
        }
      } else {
        return McpProcessResult(finalModelContent: firstModelContent);
      }
    } catch (e) {
      final errorMsg = "Error during Gemini API call: $e";
      debugPrint("MCP: $errorMsg");
      return McpProcessResult(
        finalModelContent: Content('model', [TextPart(errorMsg)]),
      );
    }
  }

  // --- Cleanup ---
  @override
  void dispose() {
    debugPrint("Disposing McpClientNotifier, cleaning up all clients...");
    final clientIds = List<String>.from(state.activeClients.keys);
    for (final serverId in clientIds) {
      state.activeClients[serverId]?.cleanup();
    }
    super.dispose();
  }
}

// The main provider for accessing the MCP client state and notifier
final mcpClientProvider =
    StateNotifierProvider<McpClientNotifier, McpClientState>((ref) {
      return McpClientNotifier(ref);
    });
