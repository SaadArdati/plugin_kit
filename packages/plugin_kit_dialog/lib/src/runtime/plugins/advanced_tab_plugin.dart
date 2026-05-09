import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../../runtime/dialog_global_context.dart';
import '../../runtime/events.dart';
import '../../widgets/tabs/advanced_tab.dart';

/// Global plugin that contributes the `Advanced` tab descriptor (Spec §7.8).
class AdvancedTabPlugin extends GlobalPlugin<DialogGlobalContext> {
  @override
  PluginId get pluginId => const PluginId('advanced_tab');

  @override
  List<FeatureFlag> get featureFlags => [.locked];

  @override
  void attach(DialogGlobalContext context) {
    on<CollectTabsEvent>(context, (response) {
      response.event.tabs.add(
        TabDescriptor(
          id: 'advanced',
          label: 'Advanced',
          icon: Icon(Icons.code),
          order: 300,
          builder: (_) => AdvancedTab(
            controller: context.controller,
            runtime: context.runtime,
          ),
        ),
      );
    });
  }
}
