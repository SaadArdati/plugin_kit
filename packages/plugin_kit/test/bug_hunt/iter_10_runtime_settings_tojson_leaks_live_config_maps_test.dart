import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  group('bug-hunt iter 10: runtime-settings-tojson-leaks-live-config-maps', () {
    test('returns a detached plugin config snapshot from toJson', () {
      final pluginId = PluginId('p');
      final settings = RuntimeSettings(
        plugins: {
          pluginId: PluginConfig(config: <String, dynamic>{'token': 'before'}),
        },
      );

      final json = settings.toJson();
      final pluginsJson = json['plugins'] as Map<String, dynamic>;
      final pluginJson = pluginsJson['p'] as Map<String, dynamic>;
      final configJson = pluginJson['config'] as Map<String, dynamic>;

      configJson['token'] = 'after';

      expect(settings.plugins[pluginId]!.config['token'], 'before');
    });
  });
}
