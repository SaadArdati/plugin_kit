import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  test(
    'copyWith snapshots omitted services map when plugins are replaced',
    () {
      final servicePin = const PluginId('alpha').service('chat.model');
      final sourceServices = <Pin, ServiceSettings>{
        servicePin: const ServiceSettings(enabled: true),
      };
      final settings = RuntimeSettings(
        plugins: {
          const PluginId('alpha'): const PluginConfig(enabled: true),
        },
        services: sourceServices,
      );

      final copy = settings.copyWith(
        plugins: {
          const PluginId('beta'): const PluginConfig(enabled: false),
        },
      );

      sourceServices[servicePin] = const ServiceSettings(enabled: false);

      expect(copy.services[servicePin], const ServiceSettings(enabled: true));
      expect(copy.services, isNot(same(sourceServices)));
    },
  );
}
