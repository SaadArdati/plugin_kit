/// Base class for capability tags attached to service registrations.
///
/// Capabilities provide a way to discover features without constructing
/// instances. They are stored on [RegistrationWrapper.capabilities] and
/// queried via [CapabilityLookup].
///
/// ```dart
/// class ConfigurableCapability extends Capability {
///   const ConfigurableCapability();
/// }
///
/// registry.registerFactory<MyService>(
///   pluginId: PluginId('my_plugin'),
///   serviceId: ServiceId('my_service'),
///   create: () => MyService(),
///   capabilities: {const ConfigurableCapability()},
/// );
///
/// final wrapper = registry.resolveRaw<MyService>(ServiceId('my_service'));
/// if (wrapper.capabilities.hasType<ConfigurableCapability>()) {
///   // Service is configurable.
/// }
/// ```
abstract class Capability {
  /// Creates a capability marker instance.
  const Capability();
}

/// Extension methods for capability lookup and type checking.
extension CapabilityLookup on Set<Capability> {
  /// Returns the first capability of type [T], or null if none exist.
  ///
  /// ```dart
  /// final slow = capabilities.getOfType<IsSlowCapability>();
  /// ```
  T? getOfType<T extends Capability>() {
    for (final c in this) {
      if (c is T) return c;
    }
    return null;
  }

  /// Whether the set contains at least one capability of type [T].
  bool hasType<T extends Capability>() => getOfType<T>() != null;
}
