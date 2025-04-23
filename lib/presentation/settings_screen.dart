import 'package:flutter/material.dart';
import 'package:flutter_chat_desktop/providers/mcp_providers.dart';
import 'package:flutter_chat_desktop/providers/settings_providers.dart';
import 'package:flutter_chat_desktop/domains/mcp/entity/mcp_models.dart';
import 'package:flutter_chat_desktop/domains/settings/entity/mcp_server_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import reusable widgets
import 'widgets/api_key_section.dart';
import 'widgets/mcp_server_list_item.dart';
import 'widgets/server_dialog.dart';

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

  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _saveApiKey() {
    final newApiKey = _apiKeyController.text.trim();
    if (newApiKey.isNotEmpty) {
      ref
          .read(settingsServiceProvider)
          .saveApiKey(newApiKey)
          .then((_) => _showSnackbar('API Key Saved!'))
          .catchError((e) => _showSnackbar('Error saving API Key: $e'));
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

  void _toggleServerActive(String serverId, bool isActive) {
    ref
        .read(settingsServiceProvider)
        .toggleMcpServerActive(serverId, isActive)
        .catchError(
          (e) => _showSnackbar('Error updating server active state: $e'),
        );
  }

  void _deleteServer(McpServerConfig server) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Server?'),
          content: Text(
            'Are you sure you want to delete the server "${server.name}"?',
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
                    .then(
                      (_) => _showSnackbar('Server "${server.name}" deleted.'),
                    )
                    .catchError(
                      (e) => _showSnackbar('Error deleting server: $e'),
                    );
              },
            ),
          ],
        );
      },
    );
  }

  void _openServerDialog({McpServerConfig? serverToEdit}) {
    showServerDialog(
      context: context,
      serverToEdit: serverToEdit,
      onAddServer: (name, command, args, envVars, isActive) {
        ref
            .read(settingsServiceProvider)
            .addMcpServer(name, command, args, envVars)
            .then((_) => _showSnackbar('Server "$name" added.'))
            .catchError((e) => _showSnackbar('Error saving server: $e'));
      },
      onUpdateServer: (updatedServer) {
        ref
            .read(settingsServiceProvider)
            .updateMcpServer(updatedServer)
            .then(
              (_) => _showSnackbar('Server "${updatedServer.name}" updated.'),
            )
            .catchError((e) => _showSnackbar('Error updating server: $e'));
      },
      onError: _showSnackbar,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentApiKey = ref.watch(apiKeyProvider);
    final serverList = ref.watch(mcpServerListProvider);
    final mcpState = ref.watch(mcpClientProvider);

    final serverStatuses = mcpState.serverStatuses;
    final serverErrors = mcpState.serverErrorMessages;
    final connectedCount = mcpState.connectedServerCount;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- API Key Section ---
          ApiKeySection(
            controller: _apiKeyController,
            currentApiKey: currentApiKey,
            onSave: _saveApiKey,
            onClear: _clearApiKey,
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
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Add New MCP Server',
                onPressed: () => _openServerDialog(),
              ),
            ],
          ),
          const SizedBox(height: 4.0),
          Text(
            '$connectedCount server(s) connected. Changes are applied automatically.',
            style: const TextStyle(fontSize: 12.0, color: Colors.grey),
          ),
          const SizedBox(height: 12.0),

          // Server List Display
          serverList.isEmpty
              ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Center(
                  child: Text(
                    "No MCP servers configured. Click '+' to add.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
              : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: serverList.length,
                itemBuilder: (context, index) {
                  final server = serverList[index];
                  final status =
                      serverStatuses[server.id] ??
                      McpConnectionStatus.disconnected;
                  final error = serverErrors[server.id];

                  return McpServerListItem(
                    server: server,
                    status: status,
                    errorMessage: error,
                    onToggleActive: _toggleServerActive,
                    onEdit: (server) => _openServerDialog(serverToEdit: server),
                    onDelete: _deleteServer,
                  );
                },
              ),
          const SizedBox(height: 12.0),
        ],
      ),
    );
  }
}
