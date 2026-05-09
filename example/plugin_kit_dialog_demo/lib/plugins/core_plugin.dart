import 'package:plugin_kit/plugin_kit.dart';

/// Core no-op demo plugin that provides locked baseline system and agent slots.
///
/// Owns slots in two namespaces (`agent` and `system`), demonstrating a single
/// plugin spanning multiple namespaces. Other plugins co-define their own
/// slots in `agent` by redeclaring `Namespace('agent')` independently - see
/// `ChatManagerPlugin.temperature` and `ResearchAgentPlugin.researchPolicy`.
class CorePlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('core');

  /// The `agent` namespace.
  static const agentNamespace = Namespace('agent');

  /// The LLM model service slot.
  static const model = ServiceId.namespaced(agentNamespace, 'model');

  /// The system message service slot.
  static const systemMessage = ServiceId.namespaced(
    agentNamespace,
    'system_message',
  );

  /// The `system` namespace.
  static const Namespace systemNamespace = Namespace('system');

  /// The system info service slot.
  static final ServiceId info = systemNamespace('info');

  @override
  PluginId get pluginId => id;

  @override
  List<FeatureFlag> get featureFlags => const [.locked];

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(info, Object(), priority: 0);

    registry.registerSingleton<Object>(
      model,
      Object(),
      priority: 10,
      capabilities: const {
        UiConfigurableCapability(
          label: 'Model & Provider (baseline)',
          fields: [
            TextConfigField(
              key: 'model',
              label: 'Model',
              defaultValue: 'baseline-tiny-v1',
            ),
          ],
        ),
      },
    );

    registry.registerSingleton<Object>(
      systemMessage,
      Object(),
      priority: 10,
      capabilities: const {
        UiConfigurableCapability(
          label: 'System Message (baseline)',
          fields: [
            MultilineConfigField(
              key: 'system_message',
              label: 'System message',
              defaultValue: 'You are a helpful assistant.',
            ),
          ],
        ),
      },
    );
  }
}
