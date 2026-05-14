import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/runtime/dialog_global_context.dart';
import 'package:plugin_kit_dialog/src/runtime/events.dart';
import 'package:plugin_kit_dialog/src/runtime/plugins/advanced_tab_plugin.dart';
import 'package:plugin_kit_dialog/src/widgets/advanced/json_preview_editor.dart';
import 'package:plugin_kit_dialog/src/widgets/advanced/output_options_card.dart';
import 'package:plugin_kit_dialog/src/widgets/advanced/service_registry_inspector.dart';
import 'package:plugin_kit_dialog/src/widgets/tabs/advanced_tab.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildPluginKitDialogDarkTheme(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets(
    'AdvancedTab renders registry inspector + output options + JSON preview in order',
    (tester) async {
      final runtime = PluginRuntime();
      runtime.init(settings: RuntimeSettings());
      addTearDown(runtime.dispose);

      final controller = PluginKitDialogController(
        runtime: runtime,
        initialSettings: RuntimeSettings(),
      );

      await tester.pumpWidget(
        _wrap(AdvancedTab(controller: controller, runtime: runtime)),
      );

      expect(find.byType(ServiceRegistryInspector), findsOneWidget);
      expect(find.byType(OutputOptionsCard), findsOneWidget);
      expect(find.byType(JsonPreviewEditor), findsOneWidget);

      final inspectorY = tester
          .getTopLeft(find.byType(ServiceRegistryInspector))
          .dy;
      final outputOptionsY = tester
          .getTopLeft(find.byType(OutputOptionsCard))
          .dy;
      final jsonPreviewY = tester.getTopLeft(find.byType(JsonPreviewEditor)).dy;

      expect(inspectorY, lessThan(outputOptionsY));
      expect(outputOptionsY, lessThan(jsonPreviewY));
    },
  );

  testWidgets('AdvancedTabPlugin contributes and builds the Advanced tab', (
    tester,
  ) async {
    final targetRuntime = PluginRuntime();
    targetRuntime.init(settings: RuntimeSettings());
    addTearDown(targetRuntime.dispose);

    final controller = PluginKitDialogController(
      runtime: targetRuntime,
      initialSettings: RuntimeSettings(),
    );

    final dialogRuntime =
        PluginRuntime<DialogGlobalContext, SessionPluginContext>(
          plugins: [AdvancedTabPlugin()],
        )..init(
          settings: RuntimeSettings(),
          globalContextFactory: (registry, bus, sessions) =>
              DialogGlobalContext(
                registry: registry,
                bus: bus,
                sessions: sessions,
                runtime: targetRuntime,
                controller: controller,
                onSave: (_) {},
                onCancel: () {},
              ),
        );
    addTearDown(dialogRuntime.dispose);

    final collect = CollectTabsEvent();
    await dialogRuntime.globalBus.emit<CollectTabsEvent>(event: collect);

    final descriptor = collect.tabs.singleWhere((tab) => tab.id == 'advanced');
    expect(descriptor.label, 'Advanced');
    expect((descriptor.icon as Icon).icon, Icons.code);
    expect(descriptor.order, 300);

    await tester.pumpWidget(_wrap(Builder(builder: descriptor.builder)));
    expect(find.byType(AdvancedTab), findsOneWidget);
  });
}
