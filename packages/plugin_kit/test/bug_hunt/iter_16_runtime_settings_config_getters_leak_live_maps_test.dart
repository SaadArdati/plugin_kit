import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  group('bug-hunt iter 16: runtime-settings-config-getters-leak-live-maps', () {
    test('returns a detached plugin config map from getPluginConfig', () {
      final pluginId = const PluginId('alpha');
      final settings = RuntimeSettings(
        plugins: {
          pluginId: PluginConfig(config: <String, dynamic>{'token': 'before'}),
        },
      );

      final pluginConfig = settings.getPluginConfig(pluginId);
      pluginConfig['token'] = 'after';

      expect(settings.plugins[pluginId]!.config['token'], 'before');
    });
  });
}
