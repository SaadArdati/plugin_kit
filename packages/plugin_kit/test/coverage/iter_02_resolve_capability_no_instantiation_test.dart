import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _TaggedCapability extends Capability {
  final String tag;
  const _TaggedCapability(this.tag);
}

void main() {
  test(
    'resolveCapability returns the enabled winner capability without constructing services',
    () {
      var highBuilds = 0;
      var lowBuilds = 0;
      const serviceId = ServiceId('svc');
      const lowCapability = _TaggedCapability('low');

      final registry = ServiceRegistry(
        overrides: [
          const LocalPluginOverride.disable(
            plugin: PluginId('high'),
            serviceId: serviceId,
          ),
        ],
      );
      registry.registerFactory<String>(
        pluginId: const PluginId('high'),
        serviceId: serviceId,
        priority: 100,
        capabilities: {const _TaggedCapability('high')},
        create: () => 'high-${++highBuilds}',
      );
      registry.registerFactory<String>(
        pluginId: const PluginId('low'),
        serviceId: serviceId,
        priority: 50,
        capabilities: {lowCapability},
        create: () => 'low-${++lowBuilds}',
      );

      expect(registry.resolveCapability<_TaggedCapability>(serviceId), same(lowCapability));
      expect(highBuilds, 0);
      expect(lowBuilds, 0);
      expect(registry.resolve<String>(serviceId), 'low-1');
      expect(highBuilds, 0);
      expect(lowBuilds, 1);
    },
  );
}
