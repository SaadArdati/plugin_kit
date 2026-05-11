import 'package:docs_snippets/runtime_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  group('runtime-settings-construct', () {
    test('builds settings with plugins and services', () {
      expect(settings.plugins, hasLength(2));
      expect(
        settings.plugins[const PluginId('sql_language')]?.enabled,
        isTrue,
      );
      expect(
        settings.plugins[const PluginId('experimental_router')]?.enabled,
        isFalse,
      );
    });
  });

  group('runtime-settings-json', () {
    test('round-trips through JSON', () {
      final json = roundTripJson();
      expect(json, isA<Map<String, dynamic>>());
      final back = RuntimeSettings.fromJson(json);
      expect(back.plugins.length, equals(settingsForJson.plugins.length));
      expect(back.services.length, equals(settingsForJson.services.length));
    });
  });

  group('runtime-settings-copy-with', () {
    test('produces updated settings with new plugin config', () {
      const base = RuntimeSettings.empty();
      final updated = updateAnalyticsEnabled(base, false);
      expect(
        updated.plugins[const PluginId('analytics')]?.enabled,
        isFalse,
      );
    });
  });

  group('runtime-settings-empty', () {
    test('empty settings has no plugins or services', () {
      expect(emptySettings.plugins, isEmpty);
      expect(emptySettings.services, isEmpty);
    });
  });

  group('service-settings-copy-with', () {
    test('copies and overrides enabled', () {
      const original = ServiceSettings(enabled: true, config: {'k': 'v'});
      final disabled = withDisabledService(original);
      expect(disabled.enabled, isFalse);
      expect(disabled.config, equals({'k': 'v'}));
    });
  });

  group('plugin-config-construct', () {
    test('plugin config has correct fields', () {
      expect(pluginConfig.enabled, isTrue);
      expect(pluginConfig.config['api_key'], equals('sk-demo'));
    });
  });

  group('runtime-settings-pin-json', () {
    test('round-trips Pin-keyed settings through JSON', () {
      final result = demonstrateSettingsWithPin();
      expect(result.plugins[const PluginId('formal')]?.enabled, isFalse);
      expect(result.services, hasLength(2));
    });
  });
}
