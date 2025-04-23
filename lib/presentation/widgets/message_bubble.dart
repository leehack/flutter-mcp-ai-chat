import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:collection/collection.dart';

import '../../domains/chat/entity/chat_message.dart';
import '../../domains/settings/entity/mcp_server_config.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final List<McpServerConfig> serverConfigs;

  const MessageBubble({
    super.key,
    required this.message,
    required this.serverConfigs,
  });

  @override
  Widget build(BuildContext context) {
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
