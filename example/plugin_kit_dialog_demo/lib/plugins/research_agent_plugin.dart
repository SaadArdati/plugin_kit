import 'package:plugin_kit/plugin_kit.dart';

/// Experimental research-agent no-op demo plugin for research policy fields.
///
/// Defines its own `agent.research_policy` slot in the shared `agent`
/// namespace (redeclared here, no central authority).
class ResearchAgentPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('research_agent');

  /// The `agent` namespace, redeclared here independently.
  static const agentNamespace = Namespace('agent');

  /// The research policy service slot, owned by ResearchAgent.
  static const researchPolicy = ServiceId.namespaced(
    agentNamespace,
    'research_policy',
  );

  @override
  PluginId get pluginId => id;

  @override
  List<FeatureFlag> get featureFlags => const [.experimental];

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      researchPolicy,
      Object(),
      capabilities: const {
        UiConfigurableCapability(
          label: 'Research Policy',
          fields: [
            MultilineConfigField(
              key: 'system_prompt',
              label: 'System prompt',
              minLines: 4,
              maxLines: 12,
            ),
            BoolConfigField(key: 'enable_web_fetch', label: 'Enable web fetch'),
          ],
        ),
      },
    );
  }
}
