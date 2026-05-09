import 'package:plugin_kit/plugin_kit.dart';

import 'core_plugin.dart';

/// Memory-keeper competitor for `agent:system_message`. Demonstrates a
/// shadowed system-message contender that prepends recall blocks.
class MemoryKeeperPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('memory_keeper');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      CorePlugin.systemMessage,
      Object(),
      priority: 50,
      capabilities: const {
        UiConfigurableCapability(
          label: 'System Message (memory recall)',
          fields: [
            MultilineConfigField(
              key: 'system_message',
              label: 'Recall preamble',
              defaultValue:
                  'Use the following long-term memories to ground responses:',
              minLines: 3,
              maxLines: 8,
            ),
            NumberConfigField(
              key: 'recall_count',
              label: 'Memories to recall',
              min: 1,
              max: 25,
              step: 1,
              defaultValue: 8,
            ),
          ],
        ),
      },
    );
  }
}
