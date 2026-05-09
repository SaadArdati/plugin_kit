/// Core credential types for the Model Embassy system.
///
/// A [ModelPassport] declares what an agent needs from a model provider.
/// A [ModelVisa] is the notarized result: proof that a provider has
/// claimed the agent and issued an authenticated client.
library;

import 'package:model_embassy/src/clients.dart';

/// What a model can do.
enum ModelCapability { vision, toolUse, streaming, jsonMode, codeExecution }

/// An agent's requirements: presented to visa offices for model selection.
class ModelPassport {
  final String modelFamily; // 'anthropic', 'openai', 'meta', etc.
  final String
  modelId; // 'claude-sonnet-4-5-20250929', 'gpt-4o', 'llama-3', etc.
  final Set<ModelCapability> requiredCapabilities;
  final int minContextWindow; // Minimum tokens. 0 = no requirement.

  const ModelPassport({
    required this.modelFamily,
    required this.modelId,
    this.requiredCapabilities = const {},
    this.minContextWindow = 0,
  });

  @override
  String toString() =>
      'ModelPassport($modelFamily/$modelId, '
      'caps: $requiredCapabilities, minCtx: $minContextWindow)';
}

/// The notarized result of a successful visa office claim.
class ModelVisa {
  final ModelPassport passport;
  final String provider;
  final ModelClient client;

  const ModelVisa({
    required this.passport,
    required this.provider,
    required this.client,
  });

  @override
  String toString() =>
      'ModelVisa(provider: $provider, model: ${passport.modelId})';
}
