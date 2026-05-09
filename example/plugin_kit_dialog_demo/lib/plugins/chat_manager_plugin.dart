import 'package:plugin_kit/plugin_kit.dart';

import 'core_plugin.dart';

/// Chat-manager no-op demo plugin exposing the main agent configuration stack.
///
/// Defines its own `agent.temperature` slot in the shared `agent` namespace
/// (redeclared here independently of [CorePlugin]). Registers against
/// [CorePlugin.model] and [CorePlugin.systemMessage] for the other agent slots.
class ChatManagerPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('chat_manager');

  /// The `agent` namespace, redeclared here to show namespaces are
  /// coordination points, not single-plugin possessions.
  static const agentNamespace = Namespace('agent');

  /// The sampling temperature service slot, owned by ChatManager.
  static const temperature = ServiceId.namespaced(
    agentNamespace,
    'temperature',
  );

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.withPriority(100)
      ..registerSingleton<Object>(
        CorePlugin.model,
        Object(),
        capabilities: const {
          UiConfigurableCapability(
            label: 'Model & Provider',
            fields: [
              DropdownConfigField<String>(
                key: 'provider',
                label: 'Provider',
                options: [
                  DropdownOption('openrouter', 'OpenRouter'),
                  DropdownOption('openai', 'OpenAI'),
                  DropdownOption('anthropic', 'Anthropic'),
                ],
                defaultValue: 'openrouter',
              ),
              TextConfigField(
                key: 'model',
                label: 'Model',
                defaultValue: 'anthropic/claude-sonnet-4',
              ),
              PasswordConfigField(
                key: 'api_key',
                label: 'API key',
                helperText: 'Leave empty to use default',
              ),
            ],
          ),
        },
      )
      ..registerSingleton<Object>(
        temperature,
        Object(),
        capabilities: const {
          UiConfigurableCapability(
            label: 'Temperature',
            fields: [
              NumberConfigField(
                key: 'temperature',
                label: 'Temperature',
                min: 0,
                max: 2,
                step: 0.1,
                defaultValue: 1.0,
                helperText: 'Controls randomness in responses',
              ),
            ],
          ),
        },
      )
      ..registerSingleton<Object>(
        CorePlugin.systemMessage,
        Object(),
        capabilities: const {
          UiConfigurableCapability(
            label: 'System Message',
            fields: [
              MultilineConfigField(
                key: 'system_message',
                label: 'System message',
                helperText:
                    'The content of the system message. Use moustache tags for dynamic content.',
                moustacheTags: [
                  'knowledge_cutoff',
                  'current_date',
                  'working_dir',
                  'file_tree',
                  'recursive_file_tree',
                  'flutter_file_tree',
                ],
              ),
            ],
          ),
        },
      );
  }
}
