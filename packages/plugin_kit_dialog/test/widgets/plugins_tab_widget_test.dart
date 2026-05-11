import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/runtime/plugins/plugins_tab_plugin.dart';
import 'package:plugin_kit_dialog/src/widgets/tabs/plugins_tab.dart';

class _PluginSpec {
  const _PluginSpec(this.pluginId, {this.experimental = false});

  final PluginId pluginId;
  final bool experimental;
}

PluginKitDialogController _stubController({
  required List<_PluginSpec> plugins,
  required Map<PluginId, bool> enabled,
}) {
  final runtime = PluginRuntime();
  runtime.addPlugins([
    for (final spec in plugins)
      _StubPlugin(
        pluginId: spec.pluginId,
        featureFlags: [if (spec.experimental) FeatureFlag.experimental],
      ),
  ]);
  runtime.init(settings: RuntimeSettings.empty());
  runtime.globalRegistry.registerSingleton<PluginChipsBuilder>(
    pluginId: const PluginId('test'),
    serviceId: PluginsTabPlugin.chipsBuilderId,
    create: () => PluginChipsBuilder(),
  );

  final controller = PluginKitDialogController(
    runtime: runtime,
    initialSettings: RuntimeSettings.empty(),
  );

  controller.replaceWorking(
    RuntimeSettings(
      plugins: enabled.map(
        (pluginId, isEnabled) =>
            MapEntry(pluginId, PluginConfig(enabled: isEnabled)),
      ),
      services: const {},
    ),
  );

  return controller;
}

Widget _wrapWith(PluginKitDialogController controller, Widget child) =>
    MaterialApp(
      theme: buildPluginKitDialogDarkTheme(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets(
    'PluginsTab KPI math: 1 stable enabled / 2 total stable; 0 / 1 experimental',
    (tester) async {
      final controller = _stubController(
        plugins: const [
          _PluginSpec(PluginId('a')),
          _PluginSpec(PluginId('b')),
          _PluginSpec(PluginId('c'), experimental: true),
        ],
        enabled: {
          PluginId('a'): true,
          PluginId('b'): false,
          PluginId('c'): false,
        },
      );

      await tester.pumpWidget(
        _wrapWith(
          controller,
          PluginsTab(
            controller: controller,
            registry: controller.runtime.globalRegistry,
          ),
        ),
      );

      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('0 / 1'), findsOneWidget);
    },
  );
}

class _StubPlugin extends GlobalPlugin {
  _StubPlugin({required this.pluginId, required List<FeatureFlag> featureFlags})
    : _featureFlags = List.unmodifiable(featureFlags);

  @override
  final PluginId pluginId;

  final List<FeatureFlag> _featureFlags;

  @override
  List<FeatureFlag> get featureFlags => _featureFlags;
}
