import 'package:docs_snippets/dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  group('dialog-ui-configurable-capability', () {
    test('registers MyService with UiConfigurableCapability', () {
      final registry = ServiceRegistry();
      const agent = Namespace('agent');
      final scoped = registry.scopedFor(const PluginId('dialog_plugin'));
      registerConfigurableService(scoped);

      final wrapper = registry.resolveRaw<MyService>(agent('temperature'));
      expect(wrapper.capabilities.hasType<UiConfigurableCapability>(), isTrue);
      final cap = wrapper.capabilities.getOfType<UiConfigurableCapability>();
      expect(cap!.fields, hasLength(1));
    });
  });

  group('dialog-extension-field', () {
    test('registers MyService with ExtensionConfigField', () {
      final registry = ServiceRegistry();
      final scoped = registry.scopedFor(const PluginId('dialog_plugin'));
      registerWithExtensionField(scoped);

      final wrapper = registry.resolveRaw<MyService>(
        const ServiceId('theme_service'),
      );
      final cap = wrapper.capabilities.getOfType<UiConfigurableCapability>();
      expect(cap, isNotNull);
      final field = cap!.fields.first as ExtensionConfigField;
      expect(field.rendererKey, equals('color_picker'));
    });
  });

  group('dialog-reference-service-namespace', () {
    test('registers MyService under namespace without error', () {
      final registry = ServiceRegistry();
      final scoped = registry.scopedFor(const PluginId('dialog_ns_plugin'));
      registerWithNamespace(scoped);

      const agent = Namespace('agent');
      final wrapper = registry.resolveRaw<MyService>(agent('temperature'));
      expect(wrapper, isNotNull);
    });
  });

  group('dialog-color-picker-renderer', () {
    test('ColorPickerRendererPlugin has correct pluginId', () {
      expect(
        ColorPickerRendererPlugin().pluginId,
        equals(const PluginId('color_picker_renderer')),
      );
    });
  });
}
