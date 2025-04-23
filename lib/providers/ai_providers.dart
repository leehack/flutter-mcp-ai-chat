import 'package:flutter_chat_desktop/domains/ai/data/ai_repository_impl.dart';
import 'package:flutter_chat_desktop/domains/ai/repository/ai_repository.dart';
import 'package:flutter_chat_desktop/providers/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for the AI Repository.
/// It depends on the API key from the settings providers.
final aiRepositoryProvider = Provider<AiRepository?>((ref) {
  final apiKey = ref.watch(apiKeyProvider);
  if (apiKey != null && apiKey.isNotEmpty) {
    return AiRepositoryImpl(apiKey);
  }
  // Return null if API key is not available
  return null;
});
