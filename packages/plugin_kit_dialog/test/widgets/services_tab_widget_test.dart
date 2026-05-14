import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/runtime/dialog_global_context.dart';
import 'package:plugin_kit_dialog/src/runtime/events.dart';
import 'package:plugin_kit_dialog/src/runtime/plugins/services_tab_plugin.dart';
import 'package:plugin_kit_dialog/src/widgets/services/service_card.dart';
import 'package:plugin_kit_dialog/src/widgets/services/service_field_section.dart';
import 'package:plugin_kit_dialog/src/widgets/tabs/services_tab.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildPluginKitDialogDarkTheme(),
  home: Scaffold(body: child),
);

class _StubRenderer implements ConfigFieldRenderer {
  const _StubRenderer();

  @override
  Widget build(
    BuildContext context,
    ConfigField field,
    ConfigFieldHandle handle,
    FieldRenderResolver resolveRenderer,
  ) {
    return Text(field.label);
  }
}

void main() {
  testWidgets(
    'ServiceCard with two capabilities starts collapsed and expands on tap',
    (tester) async {
      final runtime = PluginRuntime();
      runtime.init(settings: RuntimeSettings());
      addTearDown(runtime.dispose);

      final controller = PluginKitDialogController(
        runtime: runtime,
        initialSettings: RuntimeSettings(),
      );

      var expanded = false;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return ServiceCard(
                pluginId: const PluginId('main_agent'),
                serviceId: const ServiceId('agent_service'),
                priority: 0,
                capabilities: const [
                  UiConfigurableCapability(
                    label: 'Model & Provider',
                    fields: [],
                  ),
                  UiConfigurableCapability(label: 'Temperature', fields: []),
                ],
                controller: controller,
                resolveRenderer: (_) => const _StubRenderer(),
                expanded: expanded,
                onToggleExpanded: () => setState(() => expanded = !expanded),
              );
            },
          ),
        ),
      );

      expect(find.text('2 configurable services'), findsOneWidget);
      expect(find.byType(ServiceFieldSection), findsNothing);
      expect(find.text('Temperature'), findsNothing);

      // Tap the subtitle text: unambiguous, and shared between the two
      // states. (Tapping the title 'main_agent' would collide with the
      // PriorityBadge chip, which also renders the pluginId once expanded.)
      await tester.tap(find.text('2 configurable services'));
      await tester.pump();

      expect(find.byType(ServiceFieldSection), findsNWidgets(2));
      expect(find.text('Temperature'), findsOneWidget);

      await tester.tap(find.text('2 configurable services'));
      await tester.pump();

      expect(find.byType(ServiceFieldSection), findsNothing);
    },
  );

  testWidgets(
    'ServiceCard switch toggles service enabled override and clears on default',
    (tester) async {
      final runtime = PluginRuntime();
      runtime.init(settings: RuntimeSettings());
      addTearDown(runtime.dispose);

      final controller = PluginKitDialogController(
        runtime: runtime,
        initialSettings: RuntimeSettings(),
      );

      await tester.pumpWidget(
        _wrap(
          ServiceCard(
            pluginId: const PluginId('main_agent'),
            serviceId: const ServiceId('agent_service'),
            priority: 0,
            capabilities: const [
              UiConfigurableCapability(label: 'Model & Provider', fields: []),
            ],
            controller: controller,
            resolveRenderer: (_) => const _StubRenderer(),
          ),
        ),
      );

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(
        controller
            .draft
            .working
            .services[Pin('main_agent', ['agent_service'])]
            ?.enabled,
        isFalse,
      );

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(
        controller.draft.working.services.containsKey(
          Pin('main_agent', ['agent_service']),
        ),
        isFalse,
      );
      expect(controller.isDirty, isFalse);
    },
  );

  testWidgets(
    'ServicesTabPlugin renders services regardless of showAllServices',
    (tester) async {
      final targetRuntime = PluginRuntime()
        ..addPlugin(_ConfigurableTargetPlugin());
      targetRuntime.init(settings: RuntimeSettings());
      addTearDown(targetRuntime.dispose);

      final controller = PluginKitDialogController(
        runtime: targetRuntime,
        initialSettings: RuntimeSettings(),
      );

      final dialogRuntime =
          PluginRuntime<DialogGlobalContext, SessionPluginContext>(
            plugins: [FieldRenderersPlugin(), ServicesTabPlugin()],
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

      final descriptor = collect.tabs.singleWhere(
        (tab) => tab.id == 'services',
      );
      expect(descriptor.label, 'Services');
      expect(descriptor.order, 200);

      await tester.pumpWidget(_wrap(Builder(builder: descriptor.builder)));

      expect(find.byType(ServicesTab), findsOneWidget);
      expect(find.byType(ServiceCard), findsOneWidget);
      expect(find.text('2 configurable services'), findsOneWidget);

      controller.showAllServices = true;
      await tester.pump();
      expect(find.byType(ServiceCard), findsOneWidget);

      controller.showAllServices = false;
      await tester.pump();
      expect(find.byType(ServiceCard), findsOneWidget);
    },
  );

  testWidgets('groups namespaced entries under a section header', (
    tester,
  ) async {
    final controller = PluginKitDialogController(
      runtime: PluginRuntime()..init(settings: RuntimeSettings()),
      initialSettings: RuntimeSettings(),
    );
    addTearDown(controller.dispose);

    final entries = <ServiceEntry>[
      const ServiceEntry(
        pluginId: PluginId('core'),
        serviceId: ServiceId('rootSlot'),
        namespace: null,
        priority: 50,
        capabilities: [UiConfigurableCapability(label: 'Root', fields: [])],
      ),
      const ServiceEntry(
        pluginId: PluginId('chat'),
        serviceId: ServiceId('agent.model'),
        namespace: Namespace('agent'),
        priority: 100,
        capabilities: [UiConfigurableCapability(label: 'Model', fields: [])],
        namespaceVisual: PluginKitVisual(label: 'Main Agent'),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServicesTab(
            controller: controller,
            entries: entries,
            resolveRenderer: (field) => throw UnimplementedError(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Section header for "Main Agent" appears.
    expect(find.text('Main Agent'), findsOneWidget);
    // Both service cards exist.
    expect(find.text('Root'), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);
  });
}

class _ConfigurableTargetPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('main_agent');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerFactory<Object>(
      ServiceId('agent_service'),
      Object.new,
      capabilities: const {
        UiConfigurableCapability(label: 'Model & Provider', fields: []),
        UiConfigurableCapability(label: 'Temperature', fields: []),
      },
    );
  }
}
