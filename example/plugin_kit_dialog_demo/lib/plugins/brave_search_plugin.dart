import 'package:plugin_kit/plugin_kit.dart';

import 'web_search_explorer_plugin.dart';

/// Brave Search competitor for the `search:provider` slot. Sits at priority
/// 90 so it is shadowed by web_search_explorer (100).
class BraveSearchPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('brave_search');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      WebSearchExplorerPlugin.provider,
      () => Object(),
      priority: 90,
      capabilities: const {
        UiConfigurableCapability(
          label: 'Search Provider (Brave)',
          fields: [
            PasswordConfigField(
              key: 'api_key',
              label: 'API key',
              helperText: 'brave.com/search/api',
            ),
            NumberConfigField(
              key: 'result_count',
              label: 'Result count',
              min: 1,
              max: 50,
              step: 1,
              defaultValue: 10,
            ),
            BoolConfigField(
              key: 'safe_search',
              label: 'Safe search',
              defaultValue: true,
            ),
          ],
        ),
      },
    );
  }
}
