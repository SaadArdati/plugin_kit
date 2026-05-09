/// Provider plugins that register visa offices for specific model families.
///
/// Each plugin registers a [VisaOffice] singleton that claims
/// [AgentBoardingCall] requests matching its supported families. Priority
/// decides which provider gets first look when families overlap.
library;

import 'package:model_embassy/src/visa_office.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// Anthropic provider: claims passports for Claude models.
class AnthropicPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('anthropic');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<VisaOffice>(
      const ServiceId('visa_office'),
      AnthropicVisaOffice(),
      priority: 100,
    );
  }
}

class OpenAIPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('openai');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<VisaOffice>(
      const ServiceId('visa_office'),
      OpenAIVisaOffice(),
      priority: 80,
    );
  }
}

class OllamaPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('ollama');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<VisaOffice>(
      const ServiceId('visa_office'),
      OllamaVisaOffice(),
      priority: 50,
    );
  }
}
