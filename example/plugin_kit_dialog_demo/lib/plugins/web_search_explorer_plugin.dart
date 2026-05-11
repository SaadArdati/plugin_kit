import 'package:plugin_kit/plugin_kit.dart';

/// Web-search no-op demo plugin for selecting the search provider.
///
/// Owns the `search` namespace. Competing search plugins reference
/// [provider] when registering against the same slot.
class WebSearchExplorerPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('web_search_explorer');

  /// The `search` namespace.
  static const namespace = Namespace('search');

  /// The search provider service slot.
  static const provider = ServiceId.namespaced(namespace, 'provider');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      provider,
      () => Object(),
      priority: Priority.elevated,
      capabilities: const {
        UiConfigurableCapability(
          label: 'Search Provider',
          fields: [
            DropdownConfigField<String>(
              key: 'provider',
              label: 'Provider',
              options: [
                DropdownOption('google', 'Google'),
                DropdownOption('bing', 'Bing'),
                DropdownOption('duckduckgo', 'DuckDuckGo'),
              ],
              defaultValue: 'google',
            ),
          ],
        ),
      },
    );
  }
}
