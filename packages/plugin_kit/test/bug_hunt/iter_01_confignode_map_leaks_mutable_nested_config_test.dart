import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _TestService extends PluginService {}

void main() {
  group('bug-hunt iter 1: confignode-map-leaks-mutable-nested-config', () {
    test(
      'does not allow mutating injected nested settings through config.map',
      () {
        final service = _TestService();
        service.injectSettings({
          'nested': {'x': 1},
        });

        service.config.map('nested')!['x'] = 2;

        expect((service.settings['nested'] as Map)['x'], 1);
      },
    );
  });
}
