import 'package:plugin_kit/plugin_kit.dart';

import 'base_mcp_plugin.dart';

/// Firebase MCP no-op demo plugin with endpoint and auth token fields.
///
/// Depends on [BaseMcpPlugin] and reuses [BaseMcpPlugin.namespace] for the
/// `mcp.firebase` slot. The runtime auto-disables this plugin if `base_mcp`
/// is off.
class FirebaseMcpPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('firebase_mcp');

  /// The Firebase MCP service slot, in the shared `mcp` namespace.
  static const firebase = ServiceId.namespaced(
    BaseMcpPlugin.namespace,
    'firebase',
  );

  @override
  PluginId get pluginId => id;

  @override
  Set<PluginId> get dependencies => const {BaseMcpPlugin.id};

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      firebase,
      Object(),
      capabilities: const {
        UiConfigurableCapability(
          label: 'Firebase MCP',
          fields: [
            TextConfigField(key: 'endpoint', label: 'Endpoint'),
            PasswordConfigField(key: 'auth_token', label: 'Auth token'),
          ],
        ),
      },
    );
  }
}
