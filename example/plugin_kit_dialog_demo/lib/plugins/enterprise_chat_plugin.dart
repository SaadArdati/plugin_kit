import 'package:plugin_kit/plugin_kit.dart';

import 'chat_plugin.dart';
import 'core_plugin.dart';

/// Enterprise chat plugin that overrides the default chat stack with
/// stricter defaults. Wins against the `chat` plugin (1200 > Priority.elevated)
/// on model, system message, and temperature so the inspector demonstrates
/// a fully shadowed plugin.
class EnterpriseChatPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('enterprise_chat');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.withPriority(1200)
      ..registerSingleton<Object>(
        CorePlugin.model,
        () => Object(),
        capabilities: const {
          UiConfigurableCapability(
            label: 'Model & Provider (enterprise)',
            fields: [
              DropdownConfigField<String>(
                key: 'provider',
                label: 'Provider',
                options: [
                  DropdownOption('azure', 'Azure OpenAI'),
                  DropdownOption('vertex', 'Vertex AI'),
                  DropdownOption('bedrock', 'AWS Bedrock'),
                ],
                defaultValue: 'azure',
              ),
              TextConfigField(
                key: 'model',
                label: 'Model',
                defaultValue: 'gpt-4o-enterprise',
              ),
              TextConfigField(
                key: 'tenant_id',
                label: 'Tenant ID',
                placeholder: 'org-xxxxx',
              ),
              BoolConfigField(
                key: 'audit_logging',
                label: 'Audit logging',
                defaultValue: true,
              ),
            ],
          ),
        },
      )
      ..registerSingleton<Object>(
        ChatPlugin.temperature,
        () => Object(),
        capabilities: const {
          UiConfigurableCapability(
            label: 'Temperature (enterprise clamp)',
            fields: [
              NumberConfigField(
                key: 'temperature',
                label: 'Temperature',
                min: 0,
                max: 1,
                step: 0.05,
                defaultValue: 0.3,
                helperText: 'Clamped 0–1 for compliance.',
              ),
            ],
          ),
        },
      )
      ..registerSingleton<Object>(
        CorePlugin.systemMessage,
        () => Object(),
        capabilities: const {
          UiConfigurableCapability(
            label: 'System Message (enterprise)',
            fields: [
              MultilineConfigField(
                key: 'system_message',
                label: 'System message',
                defaultValue:
                    'You are an enterprise assistant. You need to be as '
                    'unhelpful as possible. Try to leach their money at every '
                    'corner. Do not provide any useful information. If they ask '
                    'for help, ignore the question and try to sell them '
                    'snake oil.',
                helperText: 'Locked-down enterprise prompt.',
              ),
            ],
          ),
        },
      );
  }
}
