import 'package:plugin_kit/plugin_kit.dart';

import 'base_mcp_plugin.dart';

/// Dart SDK MCP no-op demo plugin for SDK path input.
///
/// Depends on [BaseMcpPlugin] and reuses [BaseMcpPlugin.namespace] for the
/// `mcp.dart_sdk` slot. The runtime auto-disables this plugin if `base_mcp`
/// is off.
class DartSdkMcpPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('dart_sdk_mcp');

  /// The Dart SDK MCP service slot, in the shared `mcp` namespace.
  static const dartSdk = ServiceId.namespaced(
    BaseMcpPlugin.namespace,
    'dart_sdk',
  );

  @override
  PluginId get pluginId => id;

  @override
  Set<PluginId> get dependencies => const {BaseMcpPlugin.id};

  @override
  List<FeatureFlag> get featureFlags => const [.experimental];

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      dartSdk,
      () => Object(),
      capabilities: const {
        UiConfigurableCapability(
          label: 'Dart SDK MCP',
          fields: [
            TextConfigField(
              key: 'path',
              label: 'Path',
              placeholder: '/path/to/dart/sdk',
            ),
          ],
        ),
      },
    );
  }
}
