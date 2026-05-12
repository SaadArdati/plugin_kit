import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../../runtime/dialog_global_context.dart';
import '../../runtime/events.dart';
import '../../widgets/services/fields/missing_extension_input.dart';
import '../../widgets/tabs/services_tab.dart';
import 'default_field_renderers_plugin.dart';
import 'plugin_kit_visuals_plugin.dart';

/// Global plugin that contributes the `Services` tab descriptor (Spec §7.7).
class ServicesTabPlugin extends GlobalPlugin<DialogGlobalContext> {
  @override
  PluginId get pluginId => const PluginId('services_tab');

  @override
  List<FeatureFlag> get featureFlags => [.locked];

  @override
  void attach(DialogGlobalContext context) {
    on<CollectTabsEvent>(context, (response) {
      response.event.tabs.add(
        TabDescriptor(
          id: 'services',
          label: 'Services',
          icon: Icon(Icons.settings),
          order: 200,
          builder: (_) {
            final dialogRegistry = context.registry;
            return ServicesTab(
              controller: context.controller,
              entries: _collectServiceEntries(context.runtime),
              resolveRenderer: (field) =>
                  resolveConfigFieldRenderer(dialogRegistry, field),
            );
          },
        ),
      );
    });
  }

  /// Collects [ServiceEntry] instances for the Services tab from [runtime]'s
  /// registry.
  ///
  /// For each registration that exposes a [UiConfigurableCapability], looks up
  /// the three-axis visuals (service, namespace, plugin) from the namespaces
  /// registered by [PluginKitVisualsPlugin]. Standard priority resolution
  /// picks the winner for each axis independently.
  static List<ServiceEntry> _collectServiceEntries(PluginRuntime runtime) {
    final registry =
        runtime.sessions.lastOrNull?.registry ?? runtime.globalRegistry;

    final entries = <ServiceEntry>[];
    final registrations = registry.getAllResolvedRegistrations();

    for (final registration in registrations.entries) {
      final wrapper = registration.value;
      if (!wrapper.capabilities.hasType<UiConfigurableCapability>()) {
        continue;
      }

      final capabilities = wrapper.capabilities
          .whereType<UiConfigurableCapability>()
          .toList(growable: false);

      final serviceId = registration.key;
      // The dialog groups by top-level namespace (first dot) for the
      // services tab section headers. Nested keys
      // ('agent.system_prompt.scope') still group under their first segment
      // ('agent') here, which is the presentation choice for this surface.
      final namespace = serviceId.topNamespace;

      final serviceVisual = registry.maybeResolve<PluginKitVisual>(
        PluginKitVisualsPlugin.visualOfService(serviceId),
      );
      final namespaceVisual = namespace != null
          ? registry.maybeResolve<PluginKitVisual>(
              PluginKitVisualsPlugin.visualOf(namespace),
            )
          : null;
      final pluginVisual = registry.maybeResolve<PluginKitVisual>(
        PluginKitVisualsPlugin.visualFor(wrapper.pluginId),
      );

      entries.add(
        ServiceEntry(
          pluginId: wrapper.pluginId,
          serviceId: serviceId,
          namespace: namespace,
          priority: wrapper.priority,
          capabilities: capabilities,
          serviceVisual: serviceVisual,
          namespaceVisual: namespaceVisual,
          pluginVisual: pluginVisual,
        ),
      );
    }

    entries.sort((a, b) {
      // Group by namespace, then service id, then plugin id (so multiple
      // registrants of the same slot cluster together).
      final aNs = a.namespace ?? '';
      final bNs = b.namespace ?? '';
      final nsCompare = aNs.compareTo(bNs);
      if (nsCompare != 0) return nsCompare;
      final svcCompare = a.serviceId.compareTo(b.serviceId);
      if (svcCompare != 0) return svcCompare;
      return a.pluginId.compareTo(b.pluginId);
    });

    return List.unmodifiable(entries);
  }

  /// Maps a [ConfigField] subtype to the renderer key registered with the
  /// dialog runtime under [FieldRenderersPlugin.namespace].
  ///
  /// Built-in sealed subtypes resolve to a stable string; [ExtensionConfigField]
  /// forwards its own [ExtensionConfigField.rendererKey] verbatim so a Flutter
  /// plugin can register a custom renderer under that key.
  static String configFieldRendererKey(ConfigField field) => switch (field) {
    TextConfigField() => 'text',
    MultilineConfigField() => 'multiline',
    PasswordConfigField() => 'password',
    NumberConfigField() => 'number',
    DropdownConfigField() => 'dropdown',
    BoolConfigField() => 'bool',
    GroupConfigField() => 'group',
    ExtensionConfigField(:final rendererKey) => rendererKey,
  };

  /// Resolves the [ConfigFieldRenderer] for [field] from [registry].
  ///
  /// Returns a placeholder renderer that surfaces the missing key (rather than
  /// throwing a `StateError` at widget-build time) when [field] is an
  /// [ExtensionConfigField] whose [ExtensionConfigField.rendererKey] has no
  /// registered Flutter-side renderer. Built-in sealed subtypes always resolve
  /// because [FieldRenderersPlugin] registers all of them at init.
  static ConfigFieldRenderer resolveConfigFieldRenderer(
    ServiceRegistry registry,
    ConfigField field,
  ) {
    final key = configFieldRendererKey(field);
    final renderer = registry.maybeResolve<ConfigFieldRenderer>(
      FieldRenderersPlugin.namespace(key),
    );
    if (renderer != null) {
      return renderer;
    }
    return MissingExtensionRenderer(key);
  }
}
