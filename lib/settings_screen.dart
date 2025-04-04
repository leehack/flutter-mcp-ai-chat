// lib/settings_screen.dart (Simplify environment variable layout)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'mcp_client.dart';
import 'settings_service.dart';
import 'mcp_server_config.dart';

const _uuid = Uuid();

// Helper class for managing Key-Value pairs in the dialog state
class _EnvVarPair {
  final String id; // Unique ID for list management
  final TextEditingController keyController;
  final TextEditingController valueController;

  _EnvVarPair()
    : id = _uuid.v4(),
      keyController = TextEditingController(),
      valueController = TextEditingController();
  _EnvVarPair.fromMapEntry(MapEntry<String, String> entry)
    : id = _uuid.v4(),
      keyController = TextEditingController(text: entry.key),
      valueController = TextEditingController(text: entry.value);

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _apiKeyController;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: ref.read(apiKeyProvider));
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  // --- Snackbar Helper ---
  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  // --- API Key Methods (Unchanged) ---
  void _saveApiKey() {
    final newApiKey = _apiKeyController.text.trim();
    if (newApiKey.isNotEmpty) {
      ref
          .read(settingsServiceProvider)
          .saveApiKey(newApiKey)
          .then((_) {
            _showSnackbar('API Key Saved!');
          })
          .catchError((e) {
            _showSnackbar('Error saving API Key: $e');
          });
    } else {
      _showSnackbar('API Key cannot be empty.');
    }
    FocusScope.of(context).unfocus();
  }

  void _clearApiKey() {
    ref
        .read(settingsServiceProvider)
        .clearApiKey()
        .then((_) {
          _apiKeyController.clear();
          _showSnackbar('API Key Cleared!');
        })
        .catchError((e) {
          _showSnackbar('Error clearing API Key: $e');
        });
    FocusScope.of(context).unfocus();
  }

  // --- MCP Action Methods (Unchanged) ---
  void _toggleServerActive(String serverId, bool isActive) {
    ref
        .read(settingsServiceProvider)
        .toggleMcpServerActive(serverId, isActive)
        .then((_) {})
        .catchError((e) {
          _showSnackbar('Error updating server active state: $e');
        });
  }

  void _applyMcpChanges() {
    _showSnackbar('Applying MCP connection changes...');
    ref.read(mcpClientProvider.notifier).syncConnections();
  }

  void _deleteServer(McpServerConfig server) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Server?'),
          content: Text(
            'Are you sure you want to delete the server "${server.name}"? This cannot be undone.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                ref
                    .read(settingsServiceProvider)
                    .deleteMcpServer(server.id)
                    .then((_) {
                      _showSnackbar('Server "${server.name}" deleted.');
                    })
                    .catchError((e) {
                      _showSnackbar('Error deleting server: $e');
                    });
              },
            ),
          ],
        );
      },
    );
  }

  // --- MCP Add/Edit Dialog (Flattened Env Var Layout) ---
  Future<void> _showServerDialog({McpServerConfig? serverToEdit}) async {
    final isEditing = serverToEdit != null;
    final nameController = TextEditingController(
      text: serverToEdit?.name ?? '',
    );
    final commandController = TextEditingController(
      text: serverToEdit?.command ?? '',
    );
    final argsController = TextEditingController(
      text: serverToEdit?.args ?? '',
    );
    bool isActive = serverToEdit?.isActive ?? false;
    List<_EnvVarPair> envVars =
        serverToEdit?.customEnvironment.entries
            .map((e) => _EnvVarPair.fromMapEntry(e))
            .toList() ??
        [];
    final formKey = GlobalKey<FormState>();

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void addEnvVar() {
              setDialogState(() {
                envVars.add(_EnvVarPair());
              });
            }

            void removeEnvVar(String id) {
              setDialogState(() {
                final pairIndex = envVars.indexWhere((p) => p.id == id);
                if (pairIndex != -1) {
                  envVars[pairIndex].dispose();
                  envVars.removeAt(pairIndex);
                }
              });
            }

            return AlertDialog(
              title: Text(isEditing ? 'Edit Server' : 'Add New Server'),
              contentPadding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 0.0),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // --- Standard Fields ---
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Server Name*',
                        ),
                        validator:
                            (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Name cannot be empty'
                                    : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: commandController,
                        decoration: const InputDecoration(
                          labelText: 'Server Command*',
                          hintText: r'/path/to/server or server.exe',
                        ),
                        validator:
                            (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Command cannot be empty'
                                    : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: argsController,
                        decoration: const InputDecoration(
                          labelText: 'Server Arguments',
                          hintText: r'--port 1234 --verbose',
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('Connect on Apply'),
                        value: isActive,
                        onChanged:
                            (bool value) =>
                                setDialogState(() => isActive = value),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const Divider(height: 20),

                      // --- Custom Environment Variables Section ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Custom Environment Variables',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            tooltip: 'Add Variable',
                            onPressed: addEnvVar,
                          ),
                        ],
                      ),
                      const Text(
                        'These variables passed to the server override system variables.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),

                      // *** Directly spread the generated Widgets into the Column ***
                      if (envVars.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'No custom variables defined.',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      else
                        ...envVars.map((pair) {
                          // Use spread operator (...)
                          return Padding(
                            key: ValueKey(pair.id), // Keep the key
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: pair.keyController,
                                    decoration: const InputDecoration(
                                      labelText: 'Key',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: pair.valueController,
                                    decoration: const InputDecoration(
                                      labelText: 'Value',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.remove_circle_outline,
                                    color: Theme.of(context).colorScheme.error,
                                    size: 20,
                                  ),
                                  tooltip: 'Remove Variable',
                                  onPressed: () => removeEnvVar(pair.id),
                                ),
                              ],
                            ),
                          );
                        }), // Still need toList() for the map result

                      const SizedBox(height: 16), // Bottom padding
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                ),
                TextButton(
                  child: Text(isEditing ? 'Save Changes' : 'Add Server'),
                  onPressed: () {
                    // SAVE LOGIC
                    if (formKey.currentState!.validate()) {
                      final name = nameController.text.trim();
                      final command = commandController.text.trim();
                      final args = argsController.text.trim();
                      final Map<String, String> customEnvMap = {};
                      bool envVarError = false;
                      for (var pair in envVars) {
                        final key = pair.keyController.text.trim();
                        final value = pair.valueController.text;
                        if (key.isNotEmpty) {
                          if (customEnvMap.containsKey(key)) {
                            _showSnackbar(
                              'Error: Duplicate environment key "$key"',
                            );
                            envVarError = true;
                            break;
                          }
                          customEnvMap[key] = value;
                        } else if (value.isNotEmpty) {
                          debugPrint(
                            "Ignoring env var with empty key and non-empty value.",
                          );
                        }
                      }

                      if (envVarError) return;

                      Navigator.of(dialogContext).pop();

                      Future<void> futureAction;
                      if (isEditing) {
                        final updatedServer = serverToEdit.copyWith(
                          name: name,
                          command: command,
                          args: args,
                          isActive: isActive,
                          customEnvironment: customEnvMap,
                        );
                        futureAction = ref
                            .read(settingsServiceProvider)
                            .updateMcpServer(updatedServer);
                        futureAction.then(
                          (_) => _showSnackbar(
                            'Server "${updatedServer.name}" updated.',
                          ),
                        );
                      } else {
                        final newServer = McpServerConfig(
                          id: _uuid.v4(),
                          name: name,
                          command: command,
                          args: args,
                          isActive: isActive,
                          customEnvironment: customEnvMap,
                        );
                        final currentList = ref.read(mcpServerListProvider);
                        futureAction = ref
                            .read(settingsServiceProvider)
                            .saveMcpServerList([...currentList, newServer]);
                        futureAction.then(
                          (_) => _showSnackbar('Server "$name" added.'),
                        );
                      }
                      futureAction.catchError(
                        (e) => _showSnackbar('Error saving server: $e'),
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
    // .whenComplete(() {
    //   // Dispose ALL controllers created for this dialog instance here.
    //   debugPrint("Disposing all dialog controllers in whenComplete...");
    //   nameController.dispose();
    //   commandController.dispose();
    //   argsController.dispose();
    //   disposeEnvVarControllers(); // Dispose env var controllers
    // });
  }

  // Helper to get status icon (Unchanged)
  Widget _buildStatusIcon(McpConnectionStatus status, ThemeData theme) {
    switch (status) {
      case McpConnectionStatus.connected:
        return Icon(Icons.check_circle, color: Colors.green[700], size: 20);
      case McpConnectionStatus.connecting:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case McpConnectionStatus.error:
        return Icon(Icons.error, color: theme.colorScheme.error, size: 20);
      case McpConnectionStatus.disconnected:
        return Icon(
          Icons.circle_outlined,
          color: theme.disabledColor,
          size: 20,
        );
    }
  }

  // build method remains the same
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentApiKey = ref.watch(apiKeyProvider);
    final showCodeBlocks = ref.watch(showCodeBlocksProvider);
    final mcpState = ref.watch(mcpClientProvider);
    final serverList = mcpState.serverConfigs;
    final serverStatuses = mcpState.serverStatuses;
    final serverErrors = mcpState.serverErrorMessages;
    int connectedCount = mcpState.connectedServerCount;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        // This is the outer ListView for the whole settings page
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- API Key Section (Unchanged) ---
          const Text(
            'Gemini API Key',
            style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8.0),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: 'Enter your Gemini API Key',
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.vpn_key),
            ),
            onSubmitted: (_) => _saveApiKey(),
          ),
          const SizedBox(height: 8.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Save Key'),
                onPressed: _saveApiKey,
              ),
              if (currentApiKey != null && currentApiKey.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear Key'),
                  onPressed: _clearApiKey,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4.0),
          const Text(
            'Stored locally using SharedPreferences.',
            style: TextStyle(
              fontSize: 12.0,
              fontStyle: FontStyle.italic,
              color: Colors.grey,
            ),
          ),
          const Divider(height: 24.0),

          // --- Display Settings Section (Unchanged) ---
          const Text(
            'Display Settings',
            style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
          ),
          SwitchListTile(
            title: const Text('Show Code Blocks'),
            subtitle: const Text(
              'Render code blocks formatted in chat messages.',
            ),
            value: showCodeBlocks,
            onChanged:
                (value) =>
                    ref.read(settingsServiceProvider).saveShowCodeBlocks(value),
            secondary: const Icon(Icons.code),
          ),
          const Divider(height: 24.0),

          // --- MCP Server Section ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'MCP Servers',
                style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('Apply Changes'),
                    onPressed: _applyMcpChanges,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Add New MCP Server',
                    onPressed: () => _showServerDialog(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4.0),
          Text(
            '$connectedCount server(s) connected. Toggle switches below and press "Apply Changes".',
            style: const TextStyle(fontSize: 12.0, color: Colors.grey),
          ),
          const SizedBox(height: 12.0),

          // Server List Display (This is the outer ListView for the servers)
          serverList.isEmpty
              ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Center(
                  child: Text(
                    "No MCP servers configured. Click '+' above to add one.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
              : ListView.builder(
                // This ListView should be fine here
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: serverList.length,
                itemBuilder: (context, index) {
                  final server = serverList[index];
                  final status =
                      serverStatuses[server.id] ??
                      McpConnectionStatus.disconnected;
                  final error = serverErrors[server.id];
                  final bool userWantsActive = server.isActive;
                  final int customEnvCount = server.customEnvironment.length;

                  return Card(
                    elevation: userWantsActive ? 2 : 1,
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: Tooltip(
                            message: status.name,
                            child: _buildStatusIcon(status, theme),
                          ),
                          trailing: Switch(
                            value: userWantsActive,
                            onChanged: (bool value) {
                              _toggleServerActive(server.id, value);
                            },
                            activeColor: theme.colorScheme.primary,
                          ),
                          title: Text(
                            server.name,
                            style: TextStyle(
                              fontWeight:
                                  userWantsActive
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${server.command} ${server.args}'.trim(),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              if (customEnvCount > 0)
                                Text(
                                  '$customEnvCount custom env var(s)',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                            ],
                          ),
                          onLongPress:
                              () => _showServerDialog(serverToEdit: server),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 52.0,
                            right: 8.0,
                            bottom: 8.0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child:
                                    error != null
                                        ? Text(
                                          'Error: $error',
                                          style: TextStyle(
                                            color: theme.colorScheme.error,
                                            fontSize: 11,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 2,
                                        )
                                        : const SizedBox(height: 14),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_note, size: 20),
                                    tooltip: 'Edit Server',
                                    onPressed:
                                        () => _showServerDialog(
                                          serverToEdit: server,
                                        ),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                      color: theme.colorScheme.error,
                                    ),
                                    tooltip: 'Delete Server',
                                    onPressed: () => _deleteServer(server),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          const SizedBox(height: 12.0),
        ],
      ),
    );
  }
}
