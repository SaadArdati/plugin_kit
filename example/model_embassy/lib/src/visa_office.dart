/// Visa offices that process [AgentBoardingCall] requests.
///
/// Each provider registers a [VisaOffice] that inspects incoming passports,
/// claims those matching its supported model families, and concedes
/// (returns null) for the rest. Registry priority decides which office
/// reviews a passport first.
library;

import 'package:model_embassy/src/clients.dart';
import 'package:model_embassy/src/credentials.dart';
import 'package:model_embassy/src/events.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// Metadata about what a provider can serve.
class ProviderManifest {
  final String providerName;
  final Set<String> supportedFamilies;
  final Set<ModelCapability> supportedCapabilities;
  final int maxContextWindow;

  const ProviderManifest({
    required this.providerName,
    required this.supportedFamilies,
    required this.supportedCapabilities,
    required this.maxContextWindow,
  });
}

/// Stateful service that listens for [AgentBoardingCall] requests and either
/// claims them with a [ModelVisa] or concedes by returning null.
abstract class VisaOffice extends StatefulPluginService {
  /// Model families this office can issue visas for.
  Set<String> get supportedFamilies;

  /// Capabilities this office can satisfy for a claimed passport.
  ///
  /// Defaults to all known capabilities so subclasses outside this library
  /// remain source-compatible.
  Set<ModelCapability> get supportedCapabilities =>
      Set<ModelCapability>.of(ModelCapability.values);

  /// Maximum context window (tokens) this office can support.
  ///
  /// Defaults to effectively unbounded so subclasses outside this library
  /// remain source-compatible.
  int get maxContextWindow => 1 << 30;

  ModelClient createClient(ModelPassport passport);

  @override
  void attach() {
    onRequest<AgentBoardingCall, ModelVisa>((req) async {
      final passport = req.event.passport;

      if (!supportedFamilies.contains(passport.modelFamily)) return null;
      if (!supportedCapabilities.containsAll(passport.requiredCapabilities)) {
        return null;
      }
      if (passport.minContextWindow > maxContextWindow) return null;

      final client = createClient(passport);
      return ModelVisa(
        passport: passport,
        provider: client.providerName,
        client: client,
      );
    });
  }
}

class AnthropicVisaOffice extends VisaOffice {
  @override
  Set<String> get supportedFamilies => {'anthropic'};

  @override
  Set<ModelCapability> get supportedCapabilities => {
    ModelCapability.vision,
    ModelCapability.toolUse,
    ModelCapability.streaming,
    ModelCapability.jsonMode,
  };

  @override
  int get maxContextWindow => 200000;

  @override
  ModelClient createClient(ModelPassport passport) =>
      AnthropicClient(modelId: passport.modelId);
}

class OpenAIVisaOffice extends VisaOffice {
  @override
  Set<String> get supportedFamilies => {'openai'};

  @override
  Set<ModelCapability> get supportedCapabilities => {
    ModelCapability.vision,
    ModelCapability.toolUse,
    ModelCapability.streaming,
    ModelCapability.jsonMode,
    ModelCapability.codeExecution,
  };

  @override
  int get maxContextWindow => 128000;

  @override
  ModelClient createClient(ModelPassport passport) =>
      OpenAIClient(modelId: passport.modelId);
}

class OllamaVisaOffice extends VisaOffice {
  @override
  Set<String> get supportedFamilies => {'meta', 'mistral', 'ollama'};

  @override
  Set<ModelCapability> get supportedCapabilities => {
    ModelCapability.streaming,
    ModelCapability.jsonMode,
  };

  @override
  int get maxContextWindow => 32000;

  @override
  ModelClient createClient(ModelPassport passport) =>
      OllamaClient(modelId: passport.modelId);
}
