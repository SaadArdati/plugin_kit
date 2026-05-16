import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  group(
    'bug-hunt iter 13: service-registry-copy-shares-override-settings-maps',
    () {
      test(
        'keeps override settings isolated when mutating a copied registry',
        () {
          final original = ServiceRegistry(
            overrides: [
              LocalPluginOverride(
                plugin: const PluginId('alpha'),
                serviceId: const ServiceId('alpha.service'),
                settings: <String, dynamic>{'model': 'a'},
              ),
            ],
          );

          final snapshot = original.copy();
          snapshot.overrides.single.settings['model'] = 'b';

          expect(original.overrides.single.settings['model'], 'a');
        },
      );
    },
  );
}
