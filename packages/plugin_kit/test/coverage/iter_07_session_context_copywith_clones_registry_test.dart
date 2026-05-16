import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  test(
    'SessionPluginContext.copyWith snapshots registry state so later registrations on original are not visible in the copy',
    () {
      const preCopyService = ServiceId('svc.pre_copy');
      const postCopyService = ServiceId('svc.post_copy');

      final registry = ServiceRegistry.empty();
      registry.registerSingleton<String>(
        pluginId: const PluginId('seed_plugin'),
        serviceId: preCopyService,
        create: () => 'seed',
      );

      final original = SessionPluginContext(
        registry: registry,
        bus: EventBus(),
        globalBus: EventBus(),
      );
      final copied = original.copyWith();

      original.registry.registerSingleton<String>(
        pluginId: const PluginId('late_plugin'),
        serviceId: postCopyService,
        create: () => 'late',
      );

      expect(copied.resolve<String>(preCopyService), 'seed');
      expect(() => copied.resolve<String>(postCopyService), throwsStateError);
    },
  );
}
