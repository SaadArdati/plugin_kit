import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/runtime/dialog_global_context.dart';
import 'package:plugin_kit_dialog/src/runtime/plugins/services_tab_plugin.dart';

class _MutableHandle implements ConfigFieldHandle {
  Object? _value;
  @override
  Object? get value => _value;
  @override
  set value(Object? next) => _value = next;
  @override
  bool get isOverridden => false;
  @override
  void reset() => _value = null;
}

class _StubExtensionRenderer
    implements ConfigFieldRenderer<ExtensionConfigField> {
  const _StubExtensionRenderer();

  @override
  Widget build(
    BuildContext context,
    ExtensionConfigField field,
    ConfigFieldHandle handle,
    FieldRenderResolver resolveRenderer,
  ) {
    return Text('extension:${field.rendererKey}');
  }
}

PluginRuntime<DialogGlobalContext, SessionPluginContext> _dialogRuntime(
  List<Plugin> plugins,
) {
  final target = PluginRuntime();
  target.init(settings: RuntimeSettings.empty());
  final controller = PluginKitDialogController(
    runtime: target,
    initialSettings: RuntimeSettings.empty(),
  );
  return PluginRuntime<DialogGlobalContext, SessionPluginContext>(
    plugins: plugins,
  )..init(
    settings: RuntimeSettings.empty(),
    globalContextFactory: (registry, bus, sessions) => DialogGlobalContext(
      registry: registry,
      bus: bus,
      sessions: sessions,
      runtime: target,
      controller: controller,
      onSave: (_) {},
      onCancel: () {},
    ),
  );
}

class _ExtensionRendererPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('extension_renderer_demo');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerFactory<ConfigFieldRenderer>(
      FieldRenderersPlugin.namespace('color_picker'),
      _StubExtensionRenderer.new,
    );
  }
}

void main() {
  group('configFieldRendererKey', () {
    test('maps each built-in subtype to its stable string', () {
      expect(
        ServicesTabPlugin.configFieldRendererKey(
          const TextConfigField(key: 'k', label: 'L'),
        ),
        'text',
      );
      expect(
        ServicesTabPlugin.configFieldRendererKey(
          const MultilineConfigField(key: 'k', label: 'L'),
        ),
        'multiline',
      );
      expect(
        ServicesTabPlugin.configFieldRendererKey(
          const PasswordConfigField(key: 'k', label: 'L'),
        ),
        'password',
      );
      expect(
        ServicesTabPlugin.configFieldRendererKey(
          const NumberConfigField(key: 'k', label: 'L'),
        ),
        'number',
      );
      expect(
        ServicesTabPlugin.configFieldRendererKey(
          const DropdownConfigField<String>(
            key: 'k',
            label: 'L',
            options: [DropdownOption('a', 'A')],
          ),
        ),
        'dropdown',
      );
      expect(
        ServicesTabPlugin.configFieldRendererKey(
          const BoolConfigField(key: 'k', label: 'L'),
        ),
        'bool',
      );
      expect(
        ServicesTabPlugin.configFieldRendererKey(
          const GroupConfigField(key: 'k', label: 'L', children: []),
        ),
        'group',
      );
    });

    test('forwards ExtensionConfigField.rendererKey verbatim', () {
      expect(
        ServicesTabPlugin.configFieldRendererKey(
          const ExtensionConfigField(
            key: 'theme.accent',
            label: 'Accent',
            rendererKey: 'color_picker',
          ),
        ),
        'color_picker',
      );
    });
  });

  group('resolveConfigFieldRenderer', () {
    testWidgets('resolves a registered ExtensionConfigField renderer', (
      tester,
    ) async {
      final runtime = _dialogRuntime([
        FieldRenderersPlugin(),
        _ExtensionRendererPlugin(),
      ]);
      addTearDown(runtime.dispose);

      final renderer = ServicesTabPlugin.resolveConfigFieldRenderer(
        runtime.globalRegistry,
        const ExtensionConfigField(
          key: 'theme.accent',
          label: 'Accent',
          rendererKey: 'color_picker',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => renderer.build(
              context,
              const ExtensionConfigField(
                key: 'theme.accent',
                label: 'Accent',
                rendererKey: 'color_picker',
              ),
              _MutableHandle(),
              (_) => throw UnimplementedError(),
            ),
          ),
        ),
      );

      expect(find.text('extension:color_picker'), findsOneWidget);
    });

    testWidgets(
      'returns a placeholder renderer (not a thrown StateError) when the '
      'extension key is unregistered',
      (tester) async {
        final runtime = _dialogRuntime([FieldRenderersPlugin()]);
        addTearDown(runtime.dispose);

        const field = ExtensionConfigField(
          key: 'theme.accent',
          label: 'Accent',
          rendererKey: 'missing_renderer',
        );
        final renderer = ServicesTabPlugin.resolveConfigFieldRenderer(
          runtime.globalRegistry,
          field,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => renderer.build(
                context,
                field,
                _MutableHandle(),
                (_) => throw UnimplementedError(),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('missing_renderer'),
          findsOneWidget,
          reason: 'placeholder names the missing key',
        );
        expect(
          find.textContaining('theme.accent'),
          findsOneWidget,
          reason: 'placeholder also names the field key for diagnosis',
        );
      },
    );
  });
}
