import 'package:plugin_kit/plugin_kit.dart';

import 'core_plugin.dart';

/// Legacy Anthropic competitor for `agent:model`. Locked + low priority so
/// it appears as a deprecated baseline in the inspector.
class LegacyAnthropicPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('legacy_anthropic');

  @override
  PluginId get pluginId => id;

  @override
  List<FeatureFlag> get featureFlags => const [.locked];

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      CorePlugin.model,
      () => Object(),
      priority: 30,
      capabilities: const {
        UiConfigurableCapability(
          label: 'Model & Provider (legacy)',
          fields: [
            DropdownConfigField<String>(
              key: 'model',
              label: 'Model',
              options: [
                DropdownOption('claude-2.1', 'claude-2.1'),
                DropdownOption('claude-instant-1.2', 'claude-instant-1.2'),
              ],
              defaultValue: 'claude-2.1',
            ),
            PasswordConfigField(key: 'api_key', label: 'API key'),
          ],
        ),
      },
    );
  }
}
