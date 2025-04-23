import '../entity/mcp_server_config.dart';

/// Abstract repository for managing application settings.
abstract class SettingsRepository {
  // API Key
  Future<String?> getApiKey();
  Future<void> saveApiKey(String apiKey);
  Future<void> clearApiKey();

  // MCP Server List
  Future<List<McpServerConfig>> getMcpServerList();
  Future<void> saveMcpServerList(List<McpServerConfig> servers);
}
