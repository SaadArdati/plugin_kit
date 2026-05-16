import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _TestService extends PluginService {}

void main() {
  group('bug-hunt iter 9: confignode-generic-get-leaks-mutable-nested-map', () {
    test(
      'does not allow mutating injected nested settings through config.get',
      () {
        final service = _TestService();
        service.injectSettings({
          'nested': {'x': 1},
        });

        service.config.get<Map<String, dynamic>>('nested')!['x'] = 2;

        expect((service.settings['nested'] as Map)['x'], 1);
      },
    );
  });
}
