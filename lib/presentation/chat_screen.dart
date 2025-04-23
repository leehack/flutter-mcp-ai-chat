import 'package:flutter/material.dart';
import 'package:flutter_chat_desktop/providers/mcp_providers.dart';
import 'package:flutter_chat_desktop/providers/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_providers.dart';
import 'widgets/chat_input_field.dart';
import 'widgets/mcp_connection_status_indicator.dart';
import 'widgets/message_bubble.dart';

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
    final mcpState = ref.watch(mcpClientProvider);
    final serverConfigs = ref.watch(mcpServerListProvider);

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
            McpConnectionCounter(connectedCount: connectedServerCount),
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
          // Messages list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                return MessageBubble(
                  message: message,
                  serverConfigs: serverConfigs,
                );
              },
            ),
          ),

          // Chat input field at bottom
          ChatInputField(
            controller: _textController,
            focusNode: _inputFocusNode,
            enabled: isApiKeySet && !isLoading,
            isLoading: isLoading,
            isApiKeySet: isApiKeySet,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }
}
