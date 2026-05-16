import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  test(
    'getPluginServices skipFactories skips factory instantiation but still provides eager and lazy services',
    () {
      final registry = ServiceRegistry();
      const pluginId = PluginId('alpha');
      var factoryBuilds = 0;
      var lazyBuilds = 0;
      final eagerInstance = Object();
      final lazyInstance = Object();

      registry.registerFactory<Object>(
        pluginId: pluginId,
        serviceId: const ServiceId('factory'),
        create: () {
          factoryBuilds++;
          return Object();
        },
      );
      registry.registerLazySingleton<Object>(
        pluginId: pluginId,
        serviceId: const ServiceId('lazy'),
        factory: () {
          lazyBuilds++;
          return lazyInstance;
        },
      );
      registry.registerSingleton<Object>(
        pluginId: pluginId,
        serviceId: const ServiceId('eager'),
        create: () => eagerInstance,
      );

      final services = registry.getPluginServices(pluginId, skipFactories: true);

      expect(factoryBuilds, 0);
      expect(lazyBuilds, 1);
      expect(services, hasLength(2));
      expect(services, containsAll([same(eagerInstance), same(lazyInstance)]));
    },
  );
}
