import 'package:plugin_kit/plugin_kit.dart';

/// Context-injector no-op demo plugin for include/exclude injection rules.
///
/// Registers an unnamespaced service: namespaces are optional, and a
/// single-slot, single-user plugin doesn't need one to disambiguate.
class ContextInjectorPlugin extends GlobalPlugin {
  /// Stable plugin id used by the registry and overrides.
  static const id = PluginId('context_injector');

  /// The context injector service slot (unnamespaced).
  static const contextInjector = ServiceId('context_injector');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      contextInjector,
      () => Object(),
      capabilities: const {
        UiConfigurableCapability(
          label: 'Context Injector',
          fields: [
            GroupConfigField(
              key: 'rules',
              label: 'Rules',
              children: [
                TextConfigField(
                  key: 'include_patterns',
                  label: 'Include patterns',
                ),
                TextConfigField(
                  key: 'exclude_patterns',
                  label: 'Exclude patterns',
                ),
              ],
            ),
          ],
        ),
      },
    );
  }
}
