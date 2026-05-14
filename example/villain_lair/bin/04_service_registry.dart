/// # 04: The Minion Assignment Desk (Service Registry)
///
/// The registry holds services keyed by (pluginId, serviceId). When a
/// slot has multiple entries, the highest priority wins.
///
/// Covers:
/// - `registerSingleton`: factory-built instance at registration time
/// - `registerLazySingleton`: built on first resolve, cached after
/// - `registerFactory`: fresh instance on every resolve
/// - Priority-based resolution between competing entries
/// - `resolveAfter`: skip the winner for a chain-of-responsibility fallback
/// - `Namespace(...)` + `registerSingleton`/`resolve`: grouped slots
/// - `maybeResolve` and `listAllServiceIds` for safe lookup and listing
library;

import 'package:plugin_kit/plugin_kit.dart';

abstract class EvilPlanner {
  String plan();
}

class NefariousPlanner implements EvilPlanner {
  @override
  String plan() =>
      'Step 1: Monologue. '
      'Step 2: Overcomplicate. '
      'Step 3: Leave an obvious weakness. '
      'Step 4: Profit?';
}

class AccountingPlanner implements EvilPlanner {
  @override
  String plan() =>
      'Step 1: Check budget. '
      'Step 2: Deny most of it. '
      'Step 3: Evil within fiscal constraints.';
}

class InternPlanner implements EvilPlanner {
  @override
  String plan() => "Step 1: What's a plan?";
}

/// Registered as a factory: each resolve builds a new instance.
/// `reportNumber` is assigned by a session-local factory counter.
class EvilReport {
  final int reportNumber;
  final String title;

  EvilReport(this.title, {required this.reportNumber});

  @override
  String toString() => 'Report #$reportNumber: $title';
}

/// Registered as a lazy singleton: built once on first resolve, then cached.
class CafeteriaMenu {
  final List<String> items;

  CafeteriaMenu()
    : items = [
        'Mystery Meat Surprise',
        'Salad of Suspicious Origins',
        'Coffee (bottomless, literally: the cup has no bottom)',
        "Mr. Whiskers' Approved Tuna Plate",
      ];

  @override
  String toString() => 'Today\'s Menu: ${items.join(', ')}';
}

/// One plugin acting as a stand-in for several imaginary departments, so
/// this teaching file stays in a single file.
class AssignmentDeskPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('nefarious_inc');

  @override
  void register(ScopedServiceRegistry registry) {
    // Three planners competing for the same slot; priority picks the winner.
    registry.registerSingleton<EvilPlanner>(
      const ServiceId('evil_planner'),
      () => NefariousPlanner(),
      priority: 100,
    );
    // Two more plugins register for the same slot. In a real system each
    // would live in its own plugin; we use registry.raw here as a teaching
    // shortcut to keep all three competing registrations visible in one
    // file.
    registry.raw.registerSingleton<EvilPlanner>(
      pluginId: const PluginId('accounting'),
      serviceId: const ServiceId('evil_planner'),
      create: () => AccountingPlanner(),
      priority: 50,
    );
    registry.raw.registerSingleton<EvilPlanner>(
      pluginId: const PluginId('intern_program'),
      serviceId: const ServiceId('evil_planner'),
      create: () => InternPlanner(),
      priority: 10,
    );

    // Factory: fresh instance on every resolve.
    var reportCounter = 0;
    registry.registerFactory<EvilReport>(
      const ServiceId('evil_report'),
      () => EvilReport('Quarterly Evil Metrics', reportNumber: ++reportCounter),
      priority: 50,
    );

    // Lazy singleton under a different plugin id (again via registry.raw
    // to keep the example single-file).
    registry.raw.registerLazySingleton<CafeteriaMenu>(
      pluginId: const PluginId('cafeteria'),
      serviceId: const ServiceId('menu'),
      factory: () {
        print('  (Cafeteria menu being prepared for the first time...)');
        return CafeteriaMenu();
      },
      priority: 50,
    );

    // Namespace: same serviceId under different namespaces.
    registry.registerSingleton<String>(
      const Namespace('trap_department')('motto'),
      () => "If at first you don't succeed, add more lasers.",
      priority: 50,
    );
    registry.registerSingleton<String>(
      const Namespace('cafeteria')('motto'),
      () => "You don't want to know what's in the mystery meat.",
      priority: 50,
    );
  }
}

Future<void> main() async {
  final runtime = PluginRuntime(plugins: [AssignmentDeskPlugin()])..init();
  final session = await runtime.createSession();
  final registry = session.registry;

  print('=== Priority-Based Resolution ===\n');

  // Highest priority (100) wins: Dr. Nefarious.
  final planner = registry.resolve<EvilPlanner>(
    const ServiceId('evil_planner'),
  );
  print('The plan: ${planner.plan()}');

  print('\n=== Chain of Responsibility ===\n');

  final backup = registry.resolveAfter<EvilPlanner>(
    pluginId: const PluginId('nefarious_inc'),
    serviceId: const ServiceId('evil_planner'),
  );
  print('Backup plan (Janet): ${backup.plan()}');

  final lastResort = registry.resolveAfter<EvilPlanner>(
    pluginId: const PluginId('accounting'),
    serviceId: const ServiceId('evil_planner'),
  );
  print('Last resort (Gary): ${lastResort.plan()}');

  print('\n=== Factory Registration (Fresh Every Time) ===\n');

  final report1 = registry.resolve<EvilReport>(const ServiceId('evil_report'));
  final report2 = registry.resolve<EvilReport>(const ServiceId('evil_report'));
  final report3 = registry.resolve<EvilReport>(const ServiceId('evil_report'));

  print(report1);
  print(report2);
  print(report3);
  print(
    'All different instances: '
    '${identical(report1, report2) ? "NO! Same!" : "Yes, all unique"}',
  );

  print('\n=== Lazy Singleton (Created Once) ===\n');

  // First resolve triggers the factory.
  final menu1 = registry.resolve<CafeteriaMenu>(const ServiceId('menu'));
  print(menu1);

  // Second resolve returns the cached instance.
  final menu2 = registry.resolve<CafeteriaMenu>(const ServiceId('menu'));
  print('Same menu? ${identical(menu1, menu2)}');

  print('\n=== Namespace Registration ===\n');

  final trapMotto = registry.resolve<String>(
    const Namespace('trap_department')('motto'),
  );
  final cafeMotto = registry.resolve<String>(
    const Namespace('cafeteria')('motto'),
  );

  print('Trap Dept motto: $trapMotto');
  print('Cafeteria motto: $cafeMotto');

  print('\n=== Safe Resolution ===\n');

  final missing = registry.maybeResolve<String>(
    const ServiceId('unicorn_department.motto'),
  );
  print(
    'Unicorn dept: '
    '${missing ?? "(department not found: Gary is disappointed)"}',
  );

  print('\n=== Registry Introspection ===\n');

  final allIds = registry.listAllServiceIds();
  print('All registered service IDs:');
  for (final id in allIds) {
    print('  - $id');
  }

  final nefariousServices = registry.listAllServiceIds(
    const PluginId('nefarious_inc'),
  );
  print('\nDr. Nefarious owns: $nefariousServices');

  await runtime.dispose();
  print(
    '\nAnother day at VILLAIN Inc. Gary is looking for the unicorn department.',
  );
}
