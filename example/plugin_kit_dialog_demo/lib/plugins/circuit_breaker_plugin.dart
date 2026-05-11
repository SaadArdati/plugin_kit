import 'package:plugin_kit/plugin_kit.dart';

/// Circuit-breaker retry policy. Defines its own `retry.circuit_breaker` slot
/// in the shared `retry` namespace.
class CircuitBreakerPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('circuit_breaker');

  /// The `retry` namespace, redeclared here independently.
  static const namespace = Namespace('retry');

  /// The circuit-breaker retry policy slot.
  static const circuitBreaker = ServiceId.namespaced(
    namespace,
    'circuit_breaker',
  );

  @override
  PluginId get pluginId => id;

  @override
  List<FeatureFlag> get featureFlags => const [.experimental];

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      circuitBreaker,
      () => Object(),
      capabilities: const {
        UiConfigurableCapability(
          label: 'Retry Policy (circuit breaker)',
          fields: [
            NumberConfigField(
              key: 'failure_threshold',
              label: 'Failure threshold',
              min: 1,
              max: 20,
              step: 1,
              defaultValue: 5,
            ),
            NumberConfigField(
              key: 'cool_down_ms',
              label: 'Cool-down (ms)',
              min: 1000,
              max: 60000,
              step: 500,
              defaultValue: 10000,
            ),
            BoolConfigField(
              key: 'half_open_probe',
              label: 'Half-open probe',
              defaultValue: true,
            ),
          ],
        ),
      },
    );
  }
}
