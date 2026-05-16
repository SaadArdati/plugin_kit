import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  group(
    'bug-hunt iter 15: runtime-settings-fromjson-shares-source-config-maps',
    () {
      test('detaches plugin config from source JSON after deserialization', () {
        final json = <String, dynamic>{
          'plugins': <String, dynamic>{
            'alpha': <String, dynamic>{
              'enabled': true,
              'config': <String, dynamic>{'token': 'before'},
            },
          },
        };

        final settings = RuntimeSettings.fromJson(json);

        final pluginJson = json['plugins'] as Map<String, dynamic>;
        final alphaJson = pluginJson['alpha'] as Map<String, dynamic>;
        final sourceConfig = alphaJson['config'] as Map<String, dynamic>;
        sourceConfig['token'] = 'after';

        expect(settings.plugins[PluginId('alpha')]!.config['token'], 'before');
      });
    },
  );
}
