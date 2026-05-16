import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  group('bug-hunt iter 11: runtime-settings-copywith-shares-config-maps', () {
    test('keeps plugin config isolated when mutating a copyWith snapshot', () {
      final pluginId = PluginId('alpha');
      final settings = RuntimeSettings(
        plugins: {
          pluginId: PluginConfig(config: <String, dynamic>{'token': 'before'}),
        },
      );

      final copy = settings.copyWith();
      copy.plugins[pluginId]!.config['token'] = 'after';

      expect(settings.plugins[pluginId]!.config['token'], 'before');
    });
  });
}
