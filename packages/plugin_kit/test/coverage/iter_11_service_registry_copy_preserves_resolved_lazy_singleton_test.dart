import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  test(
    'ServiceRegistry.copy preserves resolved lazy singleton identity and does not rerun its factory',
    () {
      final registry = ServiceRegistry();
      final scoped = ScopedServiceRegistry(registry, const PluginId('alpha'));
      var factoryRuns = 0;
      const serviceId = ServiceId('lazy.cached');

      scoped.registerLazySingleton<Object>(serviceId, () {
        factoryRuns++;
        return Object();
      });

      final original = registry.resolve<Object>(serviceId);
      final snapshot = registry.copy();
      final fromCopy = snapshot.resolve<Object>(serviceId);

      expect(factoryRuns, 1);
      expect(fromCopy, same(original));
    },
  );
}
