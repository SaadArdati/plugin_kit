import 'package:plugin_kit/plugin_kit.dart';

import 'core_plugin.dart';

/// Local LLM runner that competes for `agent:model` with Ollama/LM Studio
/// targets. Sits below the `chat` plugin (priority 50) so the Advanced
/// inspector shows it as a shadowed contender.
class LocalLlmRunnerPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('local_llm_runner');

  @override
  PluginId get pluginId => id;

  @override
  List<FeatureFlag> get featureFlags => const [.experimental];

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      CorePlugin.model,
      () => Object(),
      priority: Priority.normal,
      capabilities: const {
        UiConfigurableCapability(
          label: 'Model & Provider (local runner)',
          fields: [
            DropdownConfigField<String>(
              key: 'provider',
              label: 'Provider',
              options: [
                DropdownOption('ollama', 'Ollama'),
                DropdownOption('lmstudio', 'LM Studio'),
                DropdownOption('llamacpp', 'llama.cpp'),
              ],
              defaultValue: 'ollama',
            ),
            TextConfigField(
              key: 'model',
              label: 'Model',
              defaultValue: 'llama3.1:8b',
            ),
            TextConfigField(
              key: 'host',
              label: 'Host',
              defaultValue: 'http://localhost:11434',
            ),
          ],
        ),
      },
    );
  }
}
