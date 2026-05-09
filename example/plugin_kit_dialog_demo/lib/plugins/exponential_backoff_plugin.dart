import 'package:plugin_kit/plugin_kit.dart';

/// Exponential-backoff retry policy. Defines its own `retry.exponential`
/// slot in the shared `retry` namespace.
class ExponentialBackoffPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('exponential_backoff');

  /// The `retry` namespace, redeclared here independently of
  /// [AutoRetryPlugin].
  static const namespace = Namespace('retry');

  /// The exponential backoff retry policy slot.
  static const exponential = ServiceId.namespaced(namespace, 'exponential');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      exponential,
      Object(),
      capabilities: const {
        UiConfigurableCapability(
          label: 'Retry Policy (exponential)',
          fields: [
            NumberConfigField(
              key: 'max_retries',
              label: 'Max retries',
              min: 0,
              max: 10,
              step: 1,
              defaultValue: 5,
            ),
            NumberConfigField(
              key: 'base_delay_ms',
              label: 'Base delay (ms)',
              min: 50,
              max: 5000,
              step: 50,
              defaultValue: 250,
              helperText: 'Initial wait, doubled per attempt.',
            ),
            NumberConfigField(
              key: 'jitter_pct',
              label: 'Jitter %',
              min: 0,
              max: 100,
              step: 5,
              defaultValue: 25,
            ),
          ],
        ),
      },
    );
  }
}
