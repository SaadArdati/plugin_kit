import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';
void main() {
  test(
    'getPluginServicesWithIds skipFactories returns enabled eager and lazy instances paired to their service ids',
    () {
      const pluginId = PluginId('alpha');
      const eagerId = ServiceId('eager');
      const lazyId = ServiceId('lazy');
      const factoryId = ServiceId('factory');
      const disabledId = ServiceId('disabled');
      var factoryBuilds = 0;
      var disabledBuilds = 0;
      final eagerInstance = Object();
      final lazyInstance = Object();
      final registry = ServiceRegistry(overrides: const [
        LocalPluginOverride.disable(plugin: pluginId, serviceId: disabledId),
      ]);
      registry.registerSingleton<Object>(
        pluginId: pluginId,
        serviceId: eagerId,
        create: () => eagerInstance,
      );
      registry.registerLazySingleton<Object>(
        pluginId: pluginId,
        serviceId: lazyId,
        factory: () => lazyInstance,
      );
      registry.registerFactory<Object>(
        pluginId: pluginId,
        serviceId: factoryId,
        create: () {
          factoryBuilds++;
          return Object();
        },
      );
      registry.registerLazySingleton<Object>(
        pluginId: pluginId,
        serviceId: disabledId,
        factory: () {
          disabledBuilds++;
          return Object();
        },
      );
      final byId = {
        for (
          final pair
              in registry.getPluginServicesWithIds(pluginId, skipFactories: true)
        )
          pair.$1: pair.$2,
      };
      expect(byId.keys, unorderedEquals([eagerId, lazyId]));
      expect(byId[eagerId], same(eagerInstance));
      expect(byId[lazyId], same(lazyInstance));
      expect(factoryBuilds, 0);
      expect(disabledBuilds, 0);
    },
  );
}
