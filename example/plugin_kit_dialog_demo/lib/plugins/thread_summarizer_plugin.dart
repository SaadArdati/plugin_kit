import 'package:plugin_kit/plugin_kit.dart';

import 'core_plugin.dart';

/// Thread-summarizer competitor for `agent:system_message`. Sits just under
/// the `chat` plugin (priority 90 < 100) so the inspector shows it as the
/// runner-up.
class ThreadSummarizerPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('thread_summarizer');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      CorePlugin.systemMessage,
      () => Object(),
      priority: 900,
      capabilities: const {
        UiConfigurableCapability(
          label: 'System Message (rolling summary)',
          fields: [
            MultilineConfigField(
              key: 'system_message',
              label: 'Summary template',
              defaultValue:
                  'Conversation so far ({{message_count}} messages):\n'
                  '{{rolling_summary}}',
              moustacheTags: [
                'message_count',
                'rolling_summary',
                'last_user_message',
              ],
            ),
            NumberConfigField(
              key: 'window_messages',
              label: 'Window size',
              min: 4,
              max: 64,
              step: 2,
              defaultValue: 16,
              helperText: 'Messages to summarize before truncating.',
            ),
          ],
        ),
      },
    );
  }
}
