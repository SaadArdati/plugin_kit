import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/widgets/advanced/output_options_card.dart';
import 'package:plugin_kit_dialog/src/widgets/advanced/service_registry_inspector.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildPluginKitDialogDarkTheme(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

PluginKitDialogController _controllerFor(PluginRuntime runtime) {
  return PluginKitDialogController(
    runtime: runtime,
    initialSettings: RuntimeSettings.empty(),
  );
}

Color _statusDotColor(WidgetTester tester, String pluginId, String serviceId) {
  final dotFinder = find.descendant(
    of: find.byKey(ValueKey('status-dot-$pluginId-$serviceId')),
    matching: find.byType(Container),
  );
  final dot = tester.widget<Container>(dotFinder.first);
  final decoration = dot.decoration as BoxDecoration;
  return decoration.color!;
}

void main() {
  testWidgets('OutputOptionsCard toggles via Switch', (tester) async {
    final controller = PluginKitDialogController(
      runtime: PluginRuntime(),
      initialSettings: RuntimeSettings.empty(),
    );
    await tester.pumpWidget(_wrap(OutputOptionsCard(controller: controller)));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(controller.showAllServices, isTrue);
  });

  testWidgets(
    'ServiceRegistryInspector renders without crashing on an empty runtime',
    (tester) async {
      final runtime = PluginRuntime()..init(settings: RuntimeSettings.empty());
      final controller = _controllerFor(runtime);
      addTearDown(runtime.dispose);

      await tester.pumpWidget(
        _wrap(
          ServiceRegistryInspector(runtime: runtime, controller: controller),
        ),
      );

      expect(find.text('Service Registry'), findsOneWidget);
    },
  );

  testWidgets('ServiceRegistryInspector filter narrows rows by serviceId', (
    tester,
  ) async {
    final runtime = PluginRuntime()
      ..addPlugins([
        _StubPlugin('alpha', ['foo', 'bar.baz']),
        _StubPlugin('beta', ['qux']),
      ])
      ..init(settings: RuntimeSettings.empty());
    final controller = _controllerFor(runtime);
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      _wrap(ServiceRegistryInspector(runtime: runtime, controller: controller)),
    );

    expect(find.textContaining('.foo'), findsOneWidget);
    expect(find.textContaining('.qux'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'baz');
    await tester.pumpAndSettle();

    expect(find.textContaining('.foo'), findsNothing);
    expect(find.textContaining('.qux'), findsNothing);
    expect(find.textContaining('.baz'), findsOneWidget);
  });

  testWidgets('ServiceRegistryInspector chip filter narrows by plugin', (
    tester,
  ) async {
    final runtime = PluginRuntime()
      ..addPlugins([
        _StubPlugin('alpha', ['foo']),
        _StubPlugin('beta', ['bar']),
      ])
      ..init(settings: RuntimeSettings.empty());
    final controller = _controllerFor(runtime);
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      _wrap(ServiceRegistryInspector(runtime: runtime, controller: controller)),
    );

    expect(find.textContaining('.foo'), findsOneWidget);
    expect(find.textContaining('.bar'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plugin-filter-chip-alpha')));
    await tester.pumpAndSettle();

    expect(find.textContaining('.foo'), findsOneWidget);
    expect(find.textContaining('.bar'), findsNothing);
  });

  testWidgets('selected filter chip label is emphasized', (tester) async {
    final runtime = PluginRuntime()..init(settings: RuntimeSettings.empty());
    final controller = _controllerFor(runtime);
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      _wrap(ServiceRegistryInspector(runtime: runtime, controller: controller)),
    );

    final chipFinder = find.byKey(const ValueKey('plugin-filter-chip-All'));
    final textFinder = find.descendant(
      of: chipFinder,
      matching: find.text('All'),
    );
    final text = tester.widget<Text>(textFinder);

    // Selected chip bolds the label.
    expect(text.style?.fontWeight, FontWeight.w700);
  });

  testWidgets(
    'winner shows theme.stableAccent; shadowed shows experimentalAccent',
    (tester) async {
      final runtime = PluginRuntime()
        ..addPlugins([
          _PriorityStubPlugin(
            pluginId: 'low',
            serviceId: 'agent.model',
            priority: 10,
          ),
          _PriorityStubPlugin(
            pluginId: 'high',
            serviceId: 'agent.model',
            priority: 100,
          ),
        ])
        ..init(settings: RuntimeSettings.empty());
      final controller = _controllerFor(runtime);
      addTearDown(runtime.dispose);

      await tester.pumpWidget(
        _wrap(
          ServiceRegistryInspector(runtime: runtime, controller: controller),
        ),
      );

      // Expand the service row to surface the status-dot keys (they live
      // inside the priority chain in the expanded state, not the collapsed
      // summary).
      await tester.tap(find.text('.agent.model'));
      await tester.pumpAndSettle();

      final highDotFinder = find.byKey(
        const ValueKey('status-dot-high-agent.model'),
      );
      final lowDotFinder = find.byKey(
        const ValueKey('status-dot-low-agent.model'),
      );
      expect(highDotFinder, findsOneWidget);
      expect(lowDotFinder, findsOneWidget);

      final context = tester.element(highDotFinder);
      final theme = PluginKitDialogTheme.of(context);
      expect(
        _statusDotColor(tester, 'high', 'agent.model'),
        theme.stableAccent,
      );
      expect(
        _statusDotColor(tester, 'low', 'agent.model'),
        theme.experimentalAccent,
      );
    },
  );

  testWidgets(
    'meta namespace (plugin_kit_visuals-owned) is sorted last, collapsed by '
    'default, shows a meta badge, and expands on tap',
    (tester) async {
      // alpha owns a normal namespace; plugin_kit_visuals owns plugin_visual,
      // making that namespace meta.
      final runtime = PluginRuntime()
        ..addPlugins([
          _StubPlugin('alpha', ['agent.model']),
          _StubPlugin('plugin_kit_visuals', ['plugin_visual.auto_retry']),
        ])
        ..init(settings: RuntimeSettings.empty());
      final controller = _controllerFor(runtime);
      addTearDown(runtime.dispose);

      await tester.pumpWidget(
        _wrap(
          ServiceRegistryInspector(runtime: runtime, controller: controller),
        ),
      );

      // Meta namespaces start collapsed: children hidden.
      expect(find.text('.agent.model'), findsOneWidget);
      expect(find.text('.plugin_visual.auto_retry'), findsNothing);

      // Meta badge present.
      expect(find.text('meta'), findsOneWidget);

      // Meta namespace sorts after non-meta - agent header is above
      // plugin_visual header.
      final agentY = tester.getTopLeft(find.text('AGENT')).dy;
      final pluginVisualY = tester.getTopLeft(find.text('PLUGIN_VISUAL')).dy;
      expect(agentY, lessThan(pluginVisualY));

      // Tapping the meta header reveals its children.
      await tester.tap(find.text('PLUGIN_VISUAL'));
      await tester.pumpAndSettle();

      expect(find.text('.plugin_visual.auto_retry'), findsOneWidget);
    },
  );

  testWidgets('disabled plugin registration shows muted gray dot', (
    tester,
  ) async {
    final runtime = PluginRuntime()
      ..addPlugins([
        _PriorityStubPlugin(
          pluginId: 'low',
          serviceId: 'agent.model',
          priority: 10,
        ),
        _PriorityStubPlugin(
          pluginId: 'high',
          serviceId: 'agent.model',
          priority: 100,
        ),
      ])
      ..init(settings: RuntimeSettings.empty());
    final controller = _controllerFor(runtime);
    controller.setPluginEnabled(const PluginId('low'), false);
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      _wrap(ServiceRegistryInspector(runtime: runtime, controller: controller)),
    );

    await tester.tap(find.text('.agent.model'));
    await tester.pumpAndSettle();

    final lowDotFinder = find.byKey(
      const ValueKey('status-dot-low-agent.model'),
    );
    expect(lowDotFinder, findsOneWidget);

    final context = tester.element(lowDotFinder);
    final muted = Theme.of(
      context,
    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
    expect(_statusDotColor(tester, 'low', 'agent.model'), muted);
  });
}

class _StubPlugin extends GlobalPlugin {
  _StubPlugin(this._id, this._serviceIds);

  final String _id;
  final List<String> _serviceIds;

  @override
  PluginId get pluginId => PluginId(_id);

  @override
  void register(ScopedServiceRegistry registry) {
    for (final cid in _serviceIds) {
      registry.registerSingleton<Object>(ServiceId(cid), () => Object());
    }
  }
}

class _PriorityStubPlugin extends GlobalPlugin {
  _PriorityStubPlugin({
    required String pluginId,
    required this.serviceId,
    required this.priority,
  }) : pluginId = PluginId(pluginId);

  @override
  final PluginId pluginId;
  final String serviceId;
  final int priority;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      ServiceId(serviceId),
      () => Object(),
      priority: priority,
    );
  }
}
