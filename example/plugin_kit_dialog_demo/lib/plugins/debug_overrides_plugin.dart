import 'package:plugin_kit/plugin_kit.dart';

import 'chat_plugin.dart';
import 'core_plugin.dart';

/// Debug overrides plugin that wins every contested agent slot at priority 200.
/// Also owns its own `retry.debug` policy in the shared `retry` namespace,
/// useful for runs that surface failures immediately.
class DebugOverridesPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('debug_overrides');

  /// The `retry` namespace, redeclared here independently.
  static const namespace = Namespace('retry');

  /// The debug retry policy slot - disables retries to surface failures.
  static const debug = ServiceId.namespaced(namespace, 'debug');

  @override
  PluginId get pluginId => id;

  @override
  List<FeatureFlag> get featureFlags => const [.experimental];

  @override
  void register(ScopedServiceRegistry registry) {
    registry.withPriority(200)
      ..registerSingleton<Object>(
        CorePlugin.model,
        Object(),
        capabilities: const {
          UiConfigurableCapability(
            label: 'Model & Provider (debug)',
            fields: [
              TextConfigField(
                key: 'model',
                label: 'Model',
                defaultValue: 'debug-echo-v0',
              ),
              BoolConfigField(
                key: 'replay',
                label: 'Replay fixtures',
                defaultValue: true,
              ),
            ],
          ),
        },
      )
      ..registerSingleton<Object>(
        ChatPlugin.temperature,
        Object(),
        capabilities: const {
          UiConfigurableCapability(
            label: 'Temperature (debug pin)',
            fields: [
              NumberConfigField(
                key: 'temperature',
                label: 'Temperature',
                min: 0,
                max: 2,
                step: 0.1,
                defaultValue: 0,
                helperText: 'Pinned to 0 for reproducible runs.',
              ),
            ],
          ),
        },
      )
      ..registerSingleton<Object>(
        CorePlugin.systemMessage,
        Object(),
        capabilities: const {
          UiConfigurableCapability(
            label: 'System Message (debug)',
            fields: [
              MultilineConfigField(
                key: 'system_message',
                label: 'System message',
                defaultValue: 'DEBUG: respond with the literal echo of input.',
              ),
            ],
          ),
        },
      );

    registry.registerSingleton<Object>(
      debug,
      Object(),
      capabilities: const {
        UiConfigurableCapability(
          label: 'Retry Policy (debug)',
          fields: [
            NumberConfigField(
              key: 'max_retries',
              label: 'Max retries',
              min: 0,
              max: 10,
              step: 1,
              defaultValue: 0,
              helperText: 'Disabled: debug runs surface failures immediately.',
            ),
          ],
        ),
      },
    );
  }
}
