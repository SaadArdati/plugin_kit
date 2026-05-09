/// Abstract client returned after visa notarization. All mock: no real API calls.
abstract class ModelClient {
  String get providerName;

  String get modelId;

  Future<String> chat(String prompt);
}

class AnthropicClient extends ModelClient {
  @override
  final String modelId;

  AnthropicClient({required this.modelId});

  @override
  String get providerName => 'Anthropic';

  @override
  Future<String> chat(String prompt) async =>
      '[$providerName $modelId] Response to: "$prompt"';
}

class OpenAIClient extends ModelClient {
  @override
  final String modelId;

  OpenAIClient({required this.modelId});

  @override
  String get providerName => 'OpenAI';

  @override
  Future<String> chat(String prompt) async =>
      '[$providerName $modelId] Response to: "$prompt"';
}

class OllamaClient extends ModelClient {
  @override
  final String modelId;

  OllamaClient({required this.modelId});

  @override
  String get providerName => 'Ollama';

  @override
  Future<String> chat(String prompt) async =>
      '[$providerName $modelId] Response to: "$prompt"';
}
