import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/runtime/dialog_global_context.dart';
import 'package:plugin_kit_dialog/src/runtime/events.dart';
import 'package:plugin_kit_dialog/src/runtime/plugins/services_tab_plugin.dart';
import 'package:plugin_kit_dialog/src/widgets/services/service_card.dart';
import 'package:plugin_kit_dialog/src/widgets/tabs/services_tab.dart';

/// Plugin authored as if it lived in a Dart-only package: declares a
/// `UiConfigurableCapability` but no visual registration.
class _DartOnlyConfigurablePlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('dart_only');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      const Namespace('agent')('service'),
      () => Object(),
      capabilities: const {
        UiConfigurableCapability(label: 'Service', fields: []),
      },
    );
  }
}

/// Flutter plugin that self-attaches a [PluginKitVisual] alongside its
/// configurable capability: exercises the "self-attached" path.
class _FlutterAuthoredPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('flutter_owned');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      const Namespace('tool')('editor'),
      () => Object(),
      capabilities: const {
        UiConfigurableCapability(label: 'Editor', fields: []),
      },
    );
    // Self-attached visuals via the new service_visual namespace.
    registry.registerSingleton<PluginKitVisual>(
      PluginKitVisualsPlugin.serviceVisualNamespace('tool.editor'),
      () => const PluginKitVisual(
        icon: Icon(Icons.edit),
        color: Color(0xFF00FF00),
      ),
    );
  }
}

Widget _wrap(Widget child) => MaterialApp(
  theme: buildPluginKitDialogDarkTheme(),
  home: Scaffold(body: child),
);

Future<TabDescriptor> _buildServicesTabDescriptor({
  required PluginRuntime targetRuntime,
}) async {
  final controller = PluginKitDialogController(
    runtime: targetRuntime,
    initialSettings: RuntimeSettings(),
  );

  final dialogRuntime =
      PluginRuntime<DialogGlobalContext, SessionPluginContext>(
        plugins: [FieldRenderersPlugin(), ServicesTabPlugin()],
      )..init(
        settings: RuntimeSettings(),
        globalContextFactory: (registry, bus, sessions) => DialogGlobalContext(
          registry: registry,
          bus: bus,
          sessions: sessions,
          runtime: targetRuntime,
          controller: controller,
          onSave: (_) {},
          onCancel: () {},
        ),
      );

  final collect = CollectTabsEvent();
  await dialogRuntime.globalBus.emit<CollectTabsEvent>(event: collect);
  return collect.tabs.singleWhere((tab) => tab.id == 'services');
}

ServiceEntry _firstEntry(WidgetTester tester) {
  final tab = tester.widget<ServicesTab>(find.byType(ServicesTab));
  return tab.entries.first;
}

void main() {
  testWidgets('adapter visuals decorate dart-only plugin services', (
    tester,
  ) async {
    final targetRuntime = PluginRuntime()
      ..addPlugin(_DartOnlyConfigurablePlugin())
      ..addPlugin(
        PluginKitVisualsPlugin(
          serviceVisuals: {
            ServiceId('agent.service'): const PluginKitVisual(
              icon: Icon(Icons.cloud),
              color: Color(0xFFAA00AA),
            ),
          },
        ),
      )
      ..init(settings: RuntimeSettings());
    addTearDown(targetRuntime.dispose);

    final descriptor = await _buildServicesTabDescriptor(
      targetRuntime: targetRuntime,
    );
    await tester.pumpWidget(_wrap(Builder(builder: descriptor.builder)));

    final entry = _firstEntry(tester);
    expect(entry.serviceVisual, isNotNull);
    expect((entry.serviceVisual!.icon as Icon).icon, Icons.cloud);
    expect(entry.serviceVisual!.color, const Color(0xFFAA00AA));
  });

  testWidgets(
    'host overlay wins against self-attached visuals on the same service key',
    (tester) async {
      final targetRuntime = PluginRuntime()
        ..addPlugin(_FlutterAuthoredPlugin())
        ..addPlugin(
          // Host overlay registers at higher priority and wins.
          PluginKitVisualsPlugin(
            serviceVisuals: {
              ServiceId('tool.editor'): const PluginKitVisual(
                icon: Icon(Icons.cancel),
                color: Color(0xFFFF00FF),
              ),
            },
          ),
        )
        ..init(settings: RuntimeSettings());
      addTearDown(targetRuntime.dispose);

      final descriptor = await _buildServicesTabDescriptor(
        targetRuntime: targetRuntime,
      );
      await tester.pumpWidget(_wrap(Builder(builder: descriptor.builder)));

      final entry = _firstEntry(tester);
      expect(entry.serviceVisual, isNotNull);
      expect((entry.serviceVisual!.icon as Icon).icon, Icons.cancel);
      expect(entry.serviceVisual!.color, const Color(0xFFFF00FF));
    },
  );

  testWidgets(
    'no visuals -> entry.serviceVisual is null and card uses default chrome',
    (tester) async {
      final targetRuntime = PluginRuntime()
        ..addPlugin(_DartOnlyConfigurablePlugin())
        ..init(settings: RuntimeSettings());
      addTearDown(targetRuntime.dispose);

      final descriptor = await _buildServicesTabDescriptor(
        targetRuntime: targetRuntime,
      );
      await tester.pumpWidget(_wrap(Builder(builder: descriptor.builder)));

      final entry = _firstEntry(tester);
      expect(entry.serviceVisual, isNull);
      expect(find.byType(ServiceCard), findsOneWidget);
    },
  );

  testWidgets(
    'PluginKitDialog (fallback tabs path) also resolves visuals: guards '
    'against the body re-implementing entry collection without the lookup',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final targetRuntime = PluginRuntime()
        ..addPlugin(_FlutterAuthoredPlugin())
        ..addPlugin(_DartOnlyConfigurablePlugin())
        ..addPlugin(
          PluginKitVisualsPlugin(
            serviceVisuals: {
              ServiceId('agent.service'): const PluginKitVisual(
                icon: Icon(Icons.cloud),
                color: Color(0xFFAA00AA),
              ),
            },
          ),
        )
        ..init(settings: RuntimeSettings());
      addTearDown(targetRuntime.dispose);

      final controller = PluginKitDialogController(
        runtime: targetRuntime,
        initialSettings: RuntimeSettings(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildPluginKitDialogDarkTheme(),
          home: Scaffold(
            body: PluginKitDialog(
              controller: controller,
              onSave: (_) async {},
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to the Services tab.
      await tester.tap(find.text('Services'));
      await tester.pumpAndSettle();

      final entries = tester
          .widget<ServicesTab>(find.byType(ServicesTab))
          .entries;

      // Self-attached on the Flutter plugin.
      final flutterEntry = entries.firstWhere(
        (e) => e.pluginId == const PluginId('flutter_owned'),
      );
      expect((flutterEntry.serviceVisual?.icon as Icon).icon, Icons.edit);
      expect(flutterEntry.serviceVisual?.color, const Color(0xFF00FF00));

      // Adapter-attached on the dart-only plugin.
      final dartEntry = entries.firstWhere(
        (e) => e.pluginId == const PluginId('dart_only'),
      );
      expect((dartEntry.serviceVisual?.icon as Icon).icon, Icons.cloud);
      expect(dartEntry.serviceVisual?.color, const Color(0xFFAA00AA));
    },
  );
}
