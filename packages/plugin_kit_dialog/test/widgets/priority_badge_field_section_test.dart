import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/widgets/services/priority_badge.dart';
import 'package:plugin_kit_dialog/src/widgets/services/service_card.dart';
import 'package:plugin_kit_dialog/src/widgets/services/service_field_section.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildPluginKitDialogDarkTheme(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('PriorityBadge renders plugin id and priority', (tester) async {
    await tester.pumpWidget(
      _wrap(const PriorityBadge(pluginId: PluginId('core'), priority: 0)),
    );

    expect(find.text('core'), findsOneWidget);
    expect(find.text('Priority 0'), findsOneWidget);
  });

  testWidgets(
    'ServiceFieldSection renders one row per ConfigField and respects resolver',
    (tester) async {
      final runtime = PluginRuntime();
      runtime.init(settings: RuntimeSettings());
      addTearDown(runtime.dispose);

      final controller = PluginKitDialogController(
        runtime: runtime,
        initialSettings: RuntimeSettings(),
      );

      const cap = UiConfigurableCapability(
        label: 'Model & Provider',
        fields: [
          TextConfigField(key: 'model', label: 'Model'),
          BoolConfigField(key: 'streaming', label: 'Streaming'),
        ],
      );

      int invocations = 0;
      ConfigFieldRenderer fakeResolver(ConfigField field) {
        invocations++;
        return const _StubRenderer();
      }

      await tester.pumpWidget(
        _wrap(
          ServiceFieldSection(
            capability: cap,
            pluginId: const PluginId('core'),
            controller: controller,
            scopedKey: Pin('core', ['agent_service']),
            resolveRenderer: fakeResolver,
          ),
        ),
      );

      expect(invocations, 2);
      expect(find.text('Model & Provider'), findsOneWidget);
      expect(find.text('Model'), findsAtLeastNWidgets(1));
      expect(find.text('Streaming'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets('ServiceFieldSection handle supports dotted keys', (
    tester,
  ) async {
    final runtime = PluginRuntime();
    runtime.init(settings: RuntimeSettings());
    addTearDown(runtime.dispose);

    final controller = PluginKitDialogController(
      runtime: runtime,
      initialSettings: RuntimeSettings(),
    );

    const cap = UiConfigurableCapability(
      label: 'Provider',
      fields: [
        TextConfigField(
          key: 'provider.name',
          label: 'Provider Name',
          defaultValue: 'default-provider',
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(
        ServiceFieldSection(
          capability: cap,
          pluginId: const PluginId('core'),
          controller: controller,
          scopedKey: Pin('core', ['agent_service']),
          resolveRenderer: (_) => const _HandleProbeRenderer(),
        ),
      ),
    );

    expect(
      find.text('value=default-provider; overridden=false'),
      findsOneWidget,
    );

    await tester.tap(find.text('Set field'));
    await tester.pump();

    final configAfterSet =
        controller
                .draft
                .working
                .services[Pin('core', ['agent_service'])]
                ?.config['provider']
            as Map<String, dynamic>;
    expect(configAfterSet['name'], 'anthropic');

    await tester.tap(find.text('Reset field'));
    await tester.pump();

    expect(
      controller.draft.working.services.containsKey(
        Pin('core', ['agent_service']),
      ),
      isFalse,
    );
  });

  testWidgets('field reset button clears only the targeted field', (
    tester,
  ) async {
    final runtime = PluginRuntime();
    runtime.init(settings: RuntimeSettings());
    addTearDown(runtime.dispose);

    final controller = PluginKitDialogController(
      runtime: runtime,
      initialSettings: RuntimeSettings(),
    );

    const cap = UiConfigurableCapability(
      label: 'Rules',
      fields: [
        TextConfigField(key: 'rules.first', label: 'First Rule'),
        TextConfigField(key: 'rules.second', label: 'Second Rule'),
      ],
    );

    await tester.pumpWidget(
      _wrap(
        ServiceFieldSection(
          capability: cap,
          pluginId: const PluginId('core'),
          controller: controller,
          scopedKey: Pin('core', ['agent_service']),
          resolveRenderer: (_) => const _SetValueRenderer(),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('set-rules.first')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('set-rules.second')));
    await tester.pump();

    expect(
      controller.draft.working.services[Pin('core', ['agent_service'])]?.config,
      equals({
        'rules': {'first': 'value-rules.first', 'second': 'value-rules.second'},
      }),
    );

    await tester.tap(find.byTooltip('Reset to default').at(0));
    await tester.pump();

    expect(
      controller.draft.working.services[Pin('core', ['agent_service'])]?.config,
      equals({
        'rules': {'second': 'value-rules.second'},
      }),
    );
  });

  testWidgets('service reset button only resets its own scoped service', (
    tester,
  ) async {
    final runtime = PluginRuntime();
    runtime.init(settings: RuntimeSettings());
    addTearDown(runtime.dispose);

    final controller = PluginKitDialogController(
      runtime: runtime,
      initialSettings: RuntimeSettings(),
    );

    controller.setServiceField(
      scopedKey: Pin('core', ['service_a']),
      fieldKey: 'custom',
      value: 1,
    );
    controller.setServiceField(
      scopedKey: Pin('core', ['service_b']),
      fieldKey: 'custom',
      value: 2,
    );

    const capabilityA = UiConfigurableCapability(
      label: 'Service A',
      fields: [],
    );
    const capabilityB = UiConfigurableCapability(
      label: 'Service B',
      fields: [],
    );

    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            ServiceCard(
              pluginId: const PluginId('core'),
              serviceId: const ServiceId('service_a'),
              priority: 0,
              capabilities: const [capabilityA],
              controller: controller,
              resolveRenderer: (_) => const _StubRenderer(),
            ),
            ServiceCard(
              pluginId: const PluginId('core'),
              serviceId: const ServiceId('service_b'),
              priority: 0,
              capabilities: const [capabilityB],
              controller: controller,
              resolveRenderer: (_) => const _StubRenderer(),
              expanded: true,
              onToggleExpanded: () {},
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byTooltip('Reset to default'));
    await tester.pumpAndSettle();

    expect(
      controller.draft.working.services[Pin('core', ['service_a'])]?.config,
      equals({'custom': 1}),
    );
    expect(
      controller.draft.working.services.containsKey(Pin('core', ['service_b'])),
      isFalse,
    );
  });

  testWidgets('ServiceCard priority badge edits and clears override', (
    tester,
  ) async {
    final runtime = PluginRuntime();
    runtime.init(settings: RuntimeSettings());
    addTearDown(runtime.dispose);

    final controller = PluginKitDialogController(
      runtime: runtime,
      initialSettings: RuntimeSettings(),
    );

    const cap = UiConfigurableCapability(
      label: 'Priority Target',
      fields: [TextConfigField(key: 'provider', label: 'Provider')],
    );

    await tester.pumpWidget(
      _wrap(
        ServiceCard(
          pluginId: const PluginId('core'),
          serviceId: const ServiceId('agent_service'),
          priority: 100,
          capabilities: const [cap],
          controller: controller,
          resolveRenderer: (_) => const _StubRenderer(),
          expanded: true,
          onToggleExpanded: () {},
        ),
      ),
    );

    await tester.tap(find.text('Priority 100'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '250');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      controller
          .draft
          .working
          .services[Pin('core', ['agent_service'])]
          ?.priority,
      250,
    );

    await tester.tap(find.text('Priority 250'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Use default priority'));
    await tester.pumpAndSettle();

    expect(
      controller.draft.working.services.containsKey(
        Pin('core', ['agent_service']),
      ),
      isFalse,
    );
  });
}

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

class _HandleProbeRenderer implements ConfigFieldRenderer {
  const _HandleProbeRenderer();

  @override
  Widget build(
    BuildContext context,
    ConfigField field,
    ConfigFieldHandle handle,
    FieldRenderResolver resolveRenderer,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('value=${handle.value}; overridden=${handle.isOverridden}'),
        TextButton(
          onPressed: () => handle.value = 'anthropic',
          child: const Text('Set field'),
        ),
        TextButton(onPressed: handle.reset, child: const Text('Reset field')),
      ],
    );
  }
}

class _SetValueRenderer implements ConfigFieldRenderer {
  const _SetValueRenderer();

  @override
  Widget build(
    BuildContext context,
    ConfigField field,
    ConfigFieldHandle handle,
    FieldRenderResolver resolveRenderer,
  ) {
    return TextButton(
      key: ValueKey('set-${field.key}'),
      onPressed: () => handle.value = 'value-${field.key}',
      child: Text('Set ${field.key}'),
    );
  }
}
