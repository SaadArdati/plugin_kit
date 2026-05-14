import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/runtime/dialog_global_context.dart';
import 'package:plugin_kit_dialog/src/widgets/services/fields/text_field_input.dart';

void main() {
  test(
    'all default field renderers resolve from the runtime at default priority',
    () {
      const serviceIds = <ServiceId>[
        ServiceId('config_field_renderer.text'),
        ServiceId('config_field_renderer.multiline'),
        ServiceId('config_field_renderer.password'),
        ServiceId('config_field_renderer.number'),
        ServiceId('config_field_renderer.dropdown'),
        ServiceId('config_field_renderer.bool'),
        ServiceId('config_field_renderer.group'),
      ];

      final runtime = _createDialogRuntime();
      addTearDown(runtime.dispose);

      for (final serviceId in serviceIds) {
        final renderer = runtime.globalRegistry.resolve<ConfigFieldRenderer>(
          serviceId,
        );
        final wrapper = runtime.globalRegistry.resolveRaw<ConfigFieldRenderer>(
          serviceId,
        );

        expect(renderer, isNotNull, reason: 'expected renderer for $serviceId');
        expect(
          wrapper.priority,
          ServiceRegistry.defaultPriority,
          reason: 'expected default priority for $serviceId',
        );
      }
    },
  );

  testWidgets(
    'group renderer builds child text inputs and writes through nested handle',
    (tester) async {
      final runtime = _createDialogRuntime();
      addTearDown(runtime.dispose);

      final registry = runtime.globalRegistry;
      final handle = _MutableHandle();
      final field = const GroupConfigField(
        key: 'rules',
        label: 'Rules',
        children: [
          TextConfigField(key: 'include_patterns', label: 'Include patterns'),
          TextConfigField(key: 'exclude_patterns', label: 'Exclude patterns'),
        ],
      );

      ConfigFieldRenderer resolveRenderer(ConfigField configField) {
        final rendererKey = switch (configField) {
          TextConfigField() => 'text',
          MultilineConfigField() => 'multiline',
          PasswordConfigField() => 'password',
          NumberConfigField() => 'number',
          DropdownConfigField() => 'dropdown',
          BoolConfigField() => 'bool',
          GroupConfigField() => 'group',
          ExtensionConfigField(:final rendererKey) => rendererKey,
        };
        return registry.resolve<ConfigFieldRenderer>(
          ServiceId('config_field_renderer.$rendererKey'),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: buildPluginKitDialogDarkTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return resolveRenderer(
                  field,
                ).build(context, field, handle, resolveRenderer);
              },
            ),
          ),
        ),
      );

      expect(find.byType(TextFieldInput), findsNWidgets(2));

      await tester.enterText(find.byType(TextField).at(0), 'src/');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.enterText(find.byType(TextField).at(1), 'build/');
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        handle.value,
        equals({'include_patterns': 'src/', 'exclude_patterns': 'build/'}),
      );
    },
  );
}

PluginRuntime<DialogGlobalContext, SessionPluginContext>
_createDialogRuntime() {
  final targetRuntime = PluginRuntime();
  targetRuntime.init(settings: RuntimeSettings());

  final controller = PluginKitDialogController(
    runtime: targetRuntime,
    initialSettings: RuntimeSettings(),
  );

  return PluginRuntime<DialogGlobalContext, SessionPluginContext>(
    plugins: [FieldRenderersPlugin()],
  )..init(
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
}

class _MutableHandle implements ConfigFieldHandle {
  Object? _value;

  @override
  Object? get value => _value;

  @override
  set value(Object? next) => _value = next;

  @override
  bool get isOverridden => _value != null;

  @override
  void reset() => _value = null;
}
