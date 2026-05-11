import 'package:plugin_kit/plugin_kit.dart';

import 'web_search_explorer_plugin.dart';

/// Kagi Search competitor for the `search:provider` slot. Beats
/// web_search_explorer (priority 110 > 100), demonstrating how an
/// experimental plugin can become the winner.
class KagiSearchPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('kagi_search');

  @override
  PluginId get pluginId => id;

  @override
  List<FeatureFlag> get featureFlags => const [.experimental];

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      WebSearchExplorerPlugin.provider,
      () => Object(),
      priority: 1100,
      capabilities: const {
        UiConfigurableCapability(
          label: 'Search Provider (Kagi)',
          fields: [
            PasswordConfigField(key: 'api_key', label: 'API key'),
            BoolConfigField(
              key: 'fastgpt_summary',
              label: 'FastGPT summary',
              defaultValue: true,
            ),
            BoolConfigField(key: 'follow_links', label: 'Follow result links'),
          ],
        ),
      },
    );
  }
}
