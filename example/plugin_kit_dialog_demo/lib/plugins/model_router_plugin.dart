import 'package:plugin_kit/plugin_kit.dart';

import 'core_plugin.dart';
import 'web_search_explorer_plugin.dart';

/// Experimental model-router no-op demo plugin for routing settings.
///
/// Owns an unnamespaced `strategy` service to demonstrate that namespaces
/// are optional. Also registers competitively against [CorePlugin.model] and
/// [WebSearchExplorerPlugin.provider].
class ModelRouterPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('model_router');

  /// The routing strategy service slot (unnamespaced).
  static const strategy = ServiceId('strategy');

  @override
  PluginId get pluginId => id;

  @override
  List<FeatureFlag> get featureFlags => const [.experimental];

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      CorePlugin.model,
      () => Object(),
      priority: 800,
      capabilities: const {
        UiConfigurableCapability(
          label: 'Model & Provider (router fallback)',
          fields: [
            DropdownConfigField<String>(
              key: 'provider',
              label: 'Provider',
              options: [
                DropdownOption('openai', 'OpenAI'),
                DropdownOption('anthropic', 'Anthropic'),
                DropdownOption('google', 'Google'),
              ],
              defaultValue: 'openai',
            ),
            TextConfigField(
              key: 'model',
              label: 'Model',
              defaultValue: 'router-balanced-v1',
            ),
          ],
        ),
      },
    );

    registry.registerSingleton<Object>(
      WebSearchExplorerPlugin.provider,
      () => Object(),
      priority: 600,
      capabilities: const {
        UiConfigurableCapability(
          label: 'Search Provider (router fallback)',
          fields: [
            DropdownConfigField<String>(
              key: 'provider',
              label: 'Provider',
              options: [
                DropdownOption('brave', 'Brave Search'),
                DropdownOption('serpapi', 'SerpAPI'),
              ],
              defaultValue: 'brave',
            ),
          ],
        ),
      },
    );

    registry.registerSingleton<Object>(
      strategy,
      () => Object(),
      capabilities: const {
        UiConfigurableCapability(
          label: 'Routing Strategy',
          fields: [
            DropdownConfigField<String>(
              key: 'strategy',
              label: 'Strategy',
              options: [
                DropdownOption('round_robin', 'Round Robin'),
                DropdownOption('weighted', 'Weighted'),
                DropdownOption('least_recent', 'Least Recent'),
              ],
            ),
            NumberConfigField(
              key: 'timeout_ms',
              label: 'Timeout (ms)',
              min: 100,
              max: 30000,
              defaultValue: 5000,
              helperText: 'Applies only when multiple providers are enabled.',
            ),
          ],
        ),
      },
    );
  }
}
