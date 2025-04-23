import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart'; // For firstWhereOrNull

import '../application/chat_notifier.dart'; // Application layer notifier
import '../domains/chat/entity/chat_message.dart'; // Domain entity
import '../application/mcp_providers.dart'; // To get MCP connection count
import '../application/settings_providers.dart'; // To get server names for display
import '../domains/settings/entity/mcp_server_config.dart'; // Need type for serverConfigs list

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _textController.text;
    if (text.trim().isNotEmpty) {
      final messageToSend = text.trim();
      _textController.clear();
      // Call the notifier method to send the message
      ref.read(chatProvider.notifier).sendMessage(messageToSend);
    }
    // Refocus handled by listener on isLoading change
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Clear Chat?'),
          content: const Text(
            'Are you sure you want to clear the entire chat history? This cannot be undone.',
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
              child: const Text('Clear Chat'),
              onPressed: () {
                ref.read(chatProvider.notifier).clearChat(); // Call notifier
                Navigator.of(dialogContext).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_inputFocusNode.context != null) {
                    _inputFocusNode.requestFocus();
                  }
                });
              },
            ),
          ],
        );
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch the application layer notifier state
    final chatState = ref.watch(chatProvider);
    final mcpState = ref.watch(
      mcpClientProvider,
    ); // Watch MCP state for connection count
    final serverConfigs = ref.watch(
      mcpServerListProvider,
    ); // Watch server list for names

    final messages = chatState.displayMessages;
    final isLoading = chatState.isLoading;
    final isApiKeySet = chatState.isApiKeySet;
    final connectedServerCount = mcpState.connectedServerCount;

    // --- Listeners ---

    // Auto-scroll on new messages
    ref.listen(chatProvider.select((state) => state.displayMessages.length), (
      _,
      __,
    ) {
      _scrollToBottom();
    });

    // Refocus input when loading finishes
    ref.listen(chatProvider.select((state) => state.isLoading), (
      bool? previous,
      bool next,
    ) {
      if (previous == true && next == false) {
        // Loading finished
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_inputFocusNode.context != null) {
            _inputFocusNode.requestFocus();
          }
        });
      }
    });

    // --- Build UI ---
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Gemini Chat'),
            const Spacer(),
            Tooltip(
              message:
                  connectedServerCount > 0
                      ? '$connectedServerCount MCP Server(s) Connected'
                      : 'No MCP Servers Connected',
              child: Row(
                children: [
                  Icon(
                    connectedServerCount > 0 ? Icons.link : Icons.link_off,
                    color:
                        connectedServerCount > 0
                            ? Colors.green
                            : Theme.of(context).disabledColor,
                    size: 20,
                  ),
                  if (connectedServerCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Text(
                        '$connectedServerCount',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color:
                              connectedServerCount > 0
                                  ? Colors.green[800]
                                  : Theme.of(context).disabledColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        actions: [
          if (messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear Chat History',
              onPressed: _clearChat,
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                // Pass server configs to potentially resolve names if not already in message
                return _buildMessageBubble(context, message, serverConfigs);
              },
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: LinearProgressIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    focusNode: _inputFocusNode,
                    controller: _textController,
                    enabled: isApiKeySet && !isLoading,
                    decoration: InputDecoration(
                      hintText:
                          isApiKeySet
                              ? (isLoading
                                  ? 'Waiting for response...'
                                  : 'Enter your message...')
                              : 'Set API Key in Settings...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 12.0,
                      ),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted:
                        isApiKeySet && !isLoading
                            ? (_) => _sendMessage()
                            : null,
                    minLines: 1,
                    maxLines: 5,
                  ),
                ),
                const SizedBox(width: 8.0),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: isApiKeySet && !isLoading ? _sendMessage : null,
                  tooltip: 'Send Message',
                ),
              ],
            ),
          ),
          if (!isApiKeySet)
            Padding(
              padding: const EdgeInsets.only(
                bottom: 8.0,
                left: 16.0,
                right: 16.0,
              ),
              child: Text(
                'Please set your Gemini API Key in the Settings menu (⚙️) to start chatting.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    ChatMessage message,
    List<McpServerConfig> serverConfigs, // Removed showCodeBlocks parameter
  ) {
    final theme = Theme.of(context);
    final isUser = message.isUser;

    Widget messageContent;
    List<Widget> children = [];

    // Render text or markdown
    if (isUser) {
      messageContent = SelectableText(message.text);
    } else {
      // Handle potential Markdown rendering errors gracefully
      try {
        messageContent = MarkdownBody(data: message.text, selectable: true);
      } catch (e) {
        debugPrint("Markdown rendering error: $e");
        messageContent = SelectableText(
          "Error rendering message content.\n\n${message.text}",
        );
      }
    }
    children.add(messageContent);

    // Add tool call information if present
    if (!isUser && message.toolName != null) {
      children.add(const Divider(height: 10, thickness: 0.5));

      // Try to use pre-fetched name, otherwise look up from configs
      String serverDisplayName =
          message.sourceServerName ??
          serverConfigs
              .firstWhereOrNull((s) => s.id == message.sourceServerId)
              ?.name ??
          (message.sourceServerId != null
              ? 'Server ${message.sourceServerId!.substring(0, 6)}...'
              : 'Unknown Server');

      String toolSourceInfo =
          "Tool Called: ${message.toolName} (on $serverDisplayName)";

      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            toolSourceInfo,
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSecondaryContainer.withAlpha(204),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
        decoration: BoxDecoration(
          color:
              isUser
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
