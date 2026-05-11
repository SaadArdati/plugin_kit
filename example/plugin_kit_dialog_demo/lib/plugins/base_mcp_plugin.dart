import 'package:plugin_kit/plugin_kit.dart';

/// Locked baseline MCP plugin that provides the shared `mcp` namespace and a
/// transport singleton. [FirebaseMcpPlugin] and [DartSdkMcpPlugin] declare a
/// runtime dependency on this plugin and register their own slots in
/// [namespace]; the runtime disables them if `base_mcp` is off.
class BaseMcpPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('base_mcp');

  /// The `mcp` namespace. Dependent plugins (`firebase_mcp`, `dart_sdk_mcp`)
  /// import this constant to define their own slots here.
  static const namespace = Namespace('mcp');

  /// Baseline transport service that dependent MCP plugins build on top of.
  static const transport = ServiceId.namespaced(namespace, 'transport');

  @override
  PluginId get pluginId => id;

  @override
  List<FeatureFlag> get featureFlags => const [.locked];

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      transport,
      () => Object(),
      priority: Priority.lowest,
    );
  }
}
