import 'package:flutter/material.dart';
import '../../domains/mcp/entity/mcp_models.dart';

class McpConnectionStatusIndicator extends StatelessWidget {
  final McpConnectionStatus status;

  const McpConnectionStatusIndicator({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
}

class McpConnectionCounter extends StatelessWidget {
  final int connectedCount;

  const McpConnectionCounter({super.key, required this.connectedCount});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          connectedCount > 0
              ? '$connectedCount MCP Server(s) Connected'
              : 'No MCP Servers Connected',
      child: Row(
        children: [
          Icon(
            connectedCount > 0 ? Icons.link : Icons.link_off,
            color:
                connectedCount > 0
                    ? Colors.green
                    : Theme.of(context).disabledColor,
            size: 20,
          ),
          if (connectedCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Text(
                '$connectedCount',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color:
                      connectedCount > 0
                          ? Colors.green[800]
                          : Theme.of(context).disabledColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
