import 'package:docs_snippets/config_fields.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  group('config-field-text', () {
    test('TextConfigField has correct key and placeholder', () {
      expect(textField.key, equals('api_key'));
      expect(textField.placeholder, equals('sk-...'));
    });
  });

  group('config-field-multiline', () {
    test('MultilineConfigField has moustacheTags', () {
      expect(multilineField.moustacheTags, contains('{{user_name}}'));
    });
  });

  group('config-field-password', () {
    test('PasswordConfigField has correct key', () {
      expect(passwordField.key, equals('secret_key'));
    });
  });

  group('config-field-number', () {
    test('NumberConfigField is integer with correct bounds', () {
      expect(numberField.isInteger, isTrue);
      expect(numberField.min, equals(100));
      expect(numberField.max, equals(8192));
    });
  });

  group('config-field-dropdown', () {
    test('DropdownConfigField has correct options count', () {
      expect(dropdownField.options, hasLength(3));
      expect(dropdownField.defaultValue, equals('gpt-4.1'));
    });
  });

  group('config-field-bool', () {
    test('BoolConfigField has correct key', () {
      expect(boolField.key, equals('streaming'));
    });
  });

  group('config-field-group', () {
    test('GroupConfigField has children', () {
      expect(groupField.children, hasLength(2));
    });
  });

  group('config-field-extension', () {
    test('ExtensionConfigField has rendererKey', () {
      expect(extensionField.rendererKey, equals('color_picker'));
      expect(extensionField.args['allow_alpha'], isFalse);
    });
  });

  group('ui-configurable-capability-number', () {
    test('registers temperature service with UiConfigurableCapability', () {
      final registry = ServiceRegistry();
      final scoped = registry.scopedFor(const PluginId('agent_plugin'));
      registerWithNumberField(scoped);

      const agent = Namespace('agent');
      final wrapper = registry.resolveRaw<TemperatureService>(
        agent('temperature'),
      );
      expect(wrapper.capabilities.hasType<UiConfigurableCapability>(), isTrue);
    });
  });

  group('ui-configurable-capability-full', () {
    test('registers service with three config fields', () {
      final registry = ServiceRegistry();
      final scoped = registry.scopedFor(const PluginId('llm_plugin'));
      registerFullCapability(scoped);

      final wrapper = registry.resolveRaw<MyService>(
        const ServiceId('llm_service'),
      );
      final cap = wrapper.capabilities.getOfType<UiConfigurableCapability>();
      expect(cap, isNotNull);
      expect(cap!.fields, hasLength(3));
    });
  });
}
