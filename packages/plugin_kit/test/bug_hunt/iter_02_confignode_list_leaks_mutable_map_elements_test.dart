import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _TestService extends PluginService {}

void main() {
  group('bug-hunt iter 2: confignode-list-leaks-mutable-map-elements', () {
    test(
      'does not allow mutating injected nested settings through config.list',
      () {
        final service = _TestService();
        service.injectSettings({
          'items': [
            {'x': 1},
          ],
        });

        service.config.list<Map<String, dynamic>>('items')![0]['x'] = 2;

        final firstItem =
            (service.settings['items'] as List).first as Map<String, dynamic>;
        expect(firstItem['x'], 1);
      },
    );
  });
}
