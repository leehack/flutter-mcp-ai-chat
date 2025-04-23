import '../entity/mcp_server_config.dart';

/// Abstract repository for managing application settings.
abstract class SettingsRepository {
  // API Key
  Future<String?> getApiKey();
  Future<void> saveApiKey(String apiKey);
  Future<void> clearApiKey();

  // REMOVED: Display Settings (Show Code Blocks)
  /*
  Future<bool> getShowCodeBlocks();
  Future<void> saveShowCodeBlocks(bool showCodeBlocks);
  */

  // MCP Server List
  Future<List<McpServerConfig>> getMcpServerList();
  Future<void> saveMcpServerList(List<McpServerConfig> servers);
  // Individual server operations could be added, but saving the whole list is simpler for now
  // Future<void> addMcpServer(McpServerConfig server);
  // Future<void> updateMcpServer(McpServerConfig server);
  // Future<void> deleteMcpServer(String serverId);
  // Future<void> toggleMcpServerActive(String serverId, bool isActive);
}
