// Pinning the cost of `ServiceRegistry.updateSettings`. The original
// implementation re-stamps every wrapper's effective priority and
// re-sorts every per-service list on every call, regardless of whether
// any priority actually changed.
//
// For a runtime with many services (each its own slot), this is wasted
// work on every settings reconciliation - including reconciliations
// where the priority subset of the overrides is unchanged. The fix is
// selective: only re-sort lists whose wrappers actually had an
// effective-priority change.
//
// This test exercises that path at a size where the naive
// re-sort-every-list approach is observably slower than the selective
// implementation.
import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  test('updateSettings with unchanged overrides is fast even with many '
      'registered services', () {
    // Many services across many plugins, each with several
    // registrants. Naive: every wrapper visits every override on
    // every call, and every list is sorted unconditionally.
    const slotCount = 10000;
    const registrantsPerSlot = 50;
    const updateCalls = 1000;
    const wallClockBudgetMs = 1500;

    final registry = ServiceRegistry();
    for (var slot = 0; slot < slotCount; slot++) {
      final serviceId = ServiceId('svc_$slot');
      for (var plugin = 0; plugin < registrantsPerSlot; plugin++) {
        registry.registerSingleton<int>(
          pluginId: PluginId('p_${slot}_$plugin'),
          serviceId: serviceId,
          create: () => slot * 10 + plugin,
          priority: plugin * 10,
        );
      }
    }

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < updateCalls; i++) {
      // Empty overrides means every wrapper's effective priority
      // resolves to its basePriority, identical to the previous call.
      // The naive implementation still walks every wrapper and
      // re-sorts every list.
      registry.updateSettings(overrides: const []);
    }
    stopwatch.stop();

    expect(
      stopwatch.elapsed.inMilliseconds,
      lessThan(wallClockBudgetMs),
      reason:
          'updateSettings with unchanged overrides should be cheap; '
          '$updateCalls iterations of $slotCount slots took '
          '${stopwatch.elapsed.inMilliseconds}ms.',
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'updateSettings with a priority change still re-sorts the affected list',
    () {
      // Correctness pin: the optimization must not skip the sort when
      // a priority override actually changed an effective priority.
      final registry = ServiceRegistry();
      registry.registerSingleton<int>(
        pluginId: const PluginId('alpha'),
        serviceId: const ServiceId('svc'),
        create: () => 1,
        priority: 100,
      );
      registry.registerSingleton<int>(
        pluginId: const PluginId('beta'),
        serviceId: const ServiceId('svc'),
        create: () => 2,
        priority: 50,
      );

      // Initial state: alpha (100) wins.
      expect(registry.resolve<int>(const ServiceId('svc')), 1);

      // Override beta to priority 200: beta should now win, and the
      // list's sorted invariant must reflect that.
      registry.updateSettings(
        overrides: [
          const LocalPluginOverride.withPriority(
            plugin: PluginId('beta'),
            serviceId: ServiceId('svc'),
            priority: 200,
          ),
        ],
      );

      expect(
        registry.resolve<int>(const ServiceId('svc')),
        2,
        reason:
            'beta now has the higher effective priority and must win; the '
            'list must have been re-sorted in updateSettings',
      );
    },
  );

  test('updateSettings removing a priority override restamps the wrapper '
      'back to its base priority', () {
    // The selective sort must trigger when removing an override too,
    // not just when adding one. Otherwise an override-then-clear
    // sequence leaks the override's effective priority into the
    // wrapper indefinitely.
    final registry = ServiceRegistry();
    registry.registerSingleton<int>(
      pluginId: const PluginId('alpha'),
      serviceId: const ServiceId('svc'),
      create: () => 1,
      priority: 100,
    );
    registry.registerSingleton<int>(
      pluginId: const PluginId('beta'),
      serviceId: const ServiceId('svc'),
      create: () => 2,
      priority: 50,
    );

    // Boost beta over alpha.
    registry.updateSettings(
      overrides: [
        const LocalPluginOverride.withPriority(
          plugin: PluginId('beta'),
          serviceId: ServiceId('svc'),
          priority: 200,
        ),
      ],
    );
    expect(registry.resolve<int>(const ServiceId('svc')), 2);

    // Clear all overrides. alpha (base 100) should win again.
    registry.updateSettings(overrides: const []);
    expect(
      registry.resolve<int>(const ServiceId('svc')),
      1,
      reason:
          'clearing the override must restamp beta back to its base 50 '
          'so alpha wins',
    );
  });
}
