import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../../runtime/dialog_global_context.dart';
import '../../runtime/events.dart';
import '../../widgets/tabs/plugins_tab.dart';
import 'plugin_kit_visuals_plugin.dart';

/// Global plugin that contributes the `Plugins` tab descriptor (Spec §7.6)
/// and registers the default [PluginChipsBuilder] consumed by [PluginsTab].
class PluginsTabPlugin extends GlobalPlugin<DialogGlobalContext> {
  /// [ServiceId] for the singleton [PluginChipsBuilder] that drives the
  /// dialog's Plugins tab. The default registration lives in
  /// `PluginsTabPlugin`; hosts override by registering a higher-priority
  /// instance under this id.
  static const ServiceId chipsBuilderId = ServiceId('chips_builder');

  @override
  PluginId get pluginId => const PluginId('plugins_tab');

  @override
  List<FeatureFlag> get featureFlags => [.locked];

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<PluginChipsBuilder>(
      chipsBuilderId,
      () => PluginChipsBuilder(),
    );
  }

  @override
  void attach(DialogGlobalContext context) {
    on<CollectTabsEvent>(context, (response) {
      response.event.tabs.add(
        TabDescriptor(
          id: 'plugins',
          label: 'Plugins',
          icon: Icon(Icons.extension),
          order: 100,
          builder: (_) => PluginsTab(
            controller: context.controller,
            registry: context.registry,
          ),
        ),
      );
    });
  }
}
