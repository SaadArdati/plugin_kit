import 'package:plugin_kit/plugin_kit.dart';

/// Auto-retry no-op demo plugin with configurable retry limits.
///
/// Defines the `retry.linear` slot in the shared `retry` namespace.
/// `ExponentialBackoffPlugin`, `CircuitBreakerPlugin`, and
/// `DebugOverridesPlugin` each define their own slots in the same namespace
/// (redeclared independently) - `retry` becomes a coordination point with
/// several distinct policies side-by-side.
class AutoRetryPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('auto_retry');

  /// The `retry` namespace, redeclared here independently.
  static const namespace = Namespace('retry');

  /// The linear retry policy slot.
  static const linear = ServiceId.namespaced(namespace, 'linear');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      linear,
      () => Object(),
      capabilities: const {
        UiConfigurableCapability(
          label: 'Retry Policy (linear)',
          fields: [
            NumberConfigField(
              key: 'max_retries',
              label: 'Max retries',
              min: 0,
              max: 10,
              defaultValue: 3,
              isInteger: true,
              style: NumberFieldStyle.textInput,
              helperText: 'Bounded 0–10, integer only.',
            ),
            NumberConfigField(
              key: 'budget_seconds',
              label: 'Total retry budget (s)',
              defaultValue: 30,
              isInteger: true,
              helperText: 'Unbounded: type any integer.',
            ),
          ],
        ),
      },
    );
  }
}
