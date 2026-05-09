/// # 13: Settings Reconciliation
///
/// `PluginRuntimeManager` wraps a `PluginRuntime` with a `settingsStream`
/// and lets you reconcile settings mid-session. Disabled plugins detach;
/// surviving plugins get `onPluginSettingsChanged` so they can re-read
/// their service config and change behavior without restarting.
///
/// Covers:
/// - `PluginRuntimeManager` plus `settingsStream`
/// - `manager.init(initialSettings: ...)` for initial plugin enablement
/// - `runtime.updateSessionSettings(...)` for session reconciliation
/// - `Plugin.onPluginSettingsChanged`: react to new service config
/// - `ServiceSettings` keyed by `pluginId:serviceId`
/// - `manager.updateSettingsSnapshot(...)`: config-only update, no lifecycle
/// - `manager.isPluginEnabled(...)`
library;

import 'dart:async';

import 'package:plugin_kit/plugin_kit.dart';

class CafeteriaMenu extends PluginService {
  CafeteriaMenu();

  String get tier => config.getString('menu_tier') ?? 'mystery_meat';

  String currentMenu() {
    switch (tier) {
      case 'premium':
        return 'Menu: Filet Mignon (Mr. Whiskers approved)';
      case 'decent':
        return 'Menu: Chicken & Rice';
      case 'mystery_meat':
      default:
        return 'Menu: Mystery Meat Surprise';
    }
  }
}

class CafeteriaPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('cafeteria');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerLazySingleton<CafeteriaMenu>(
      const ServiceId('menu'),
      () => CafeteriaMenu(),
      priority: 50,
    );
  }

  @override
  void attach(SessionPluginContext context) {
    final menu = context.resolve<CafeteriaMenu>(const ServiceId('menu'));
    print('  [Cafeteria] ${menu.currentMenu()}');
  }

  @override
  Future<void> onPluginSettingsChanged(
    PluginContext oldContext,
    PluginContext newContext,
  ) async {
    final menu = newContext.resolve<CafeteriaMenu>(const ServiceId('menu'));
    print('  [Cafeteria] Budget shifted: ${menu.currentMenu()}');
  }

  @override
  Future<void> detach(SessionPluginContext context) async {
    print('  [Cafeteria] Kitchen closing. Gary is sad.');
  }
}

class DeathRayController extends PluginService {
  DeathRayController();

  int get powerLevel => config.getInt('power_level') ?? 5;

  String currentStatus() {
    final p = powerLevel;
    if (p <= 3) return 'Death ray output: low. Dr. Nefarious sulks.';
    if (p <= 7) return 'Death ray output: standard.';
    return 'Death ray output: MAXIMUM. Janet objects.';
  }
}

class DeathRayPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('death_ray');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerLazySingleton<DeathRayController>(
      const ServiceId('controller'),
      () => DeathRayController(),
      priority: 100,
    );
  }

  @override
  void attach(SessionPluginContext context) {
    final ctl = context.resolve<DeathRayController>(
      const ServiceId('controller'),
    );
    print(
      '  [Death Ray] Power level ${ctl.powerLevel}. ${ctl.currentStatus()}',
    );
  }

  @override
  Future<void> onPluginSettingsChanged(
    PluginContext oldContext,
    PluginContext newContext,
  ) async {
    final ctl = newContext.resolve<DeathRayController>(
      const ServiceId('controller'),
    );
    print(
      '  [Death Ray] Recalibrated to ${ctl.powerLevel}. ${ctl.currentStatus()}',
    );
  }

  @override
  Future<void> detach(SessionPluginContext context) async {
    print('  [Death Ray] Shutting down. Janet wins again.');
  }
}

class TrapDepartment extends PluginService {
  TrapDepartment();

  String get trap => config.getString('trap_type') ?? 'laser_grid';

  String currentTrap() {
    switch (trap) {
      case 'pit':
        return 'Active trap: Spike Pit (Doug dug it himself).';
      case 'net':
        return 'Active trap: Rope Net (budget-friendly).';
      case 'laser_grid':
      default:
        return "Active trap: Doug's Laser Grid.";
    }
  }
}

class TrapDepartmentPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('trap_department');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerLazySingleton<TrapDepartment>(
      const ServiceId('trap'),
      () => TrapDepartment(),
      priority: 50,
    );
  }

  @override
  void attach(SessionPluginContext context) {
    final t = context.resolve<TrapDepartment>(const ServiceId('trap'));
    print('  [Trap Dept] ${t.currentTrap()}');
  }

  @override
  Future<void> onPluginSettingsChanged(
    PluginContext oldContext,
    PluginContext newContext,
  ) async {
    final t = newContext.resolve<TrapDepartment>(const ServiceId('trap'));
    print('  [Trap Dept] Retooled: ${t.currentTrap()}');
  }

  @override
  Future<void> detach(SessionPluginContext context) async {
    print('  [Trap Dept] Doug has been let go. He takes his lasers.');
  }
}

Future<void> main() async {
  print('=== Setting Up with PluginRuntimeManager ===\n');

  final manager = PluginRuntimeManager();

  manager.addPlugins([
    CafeteriaPlugin(),
    DeathRayPlugin(),
    TrapDepartmentPlugin(),
  ]);

  // settingsStream publishes every reconciled PluginSettings.
  final settingsSub = manager.settingsStream.listen((settings) {
    final enabled = settings.plugins.entries
        .where((e) => e.value.enabled)
        .map((e) => e.key)
        .toList();
    print('\n  [Settings Stream] Active plugins: $enabled');
  });

  // Plugin enablement is set at init (global scope). Service overrides
  // target session plugins, so they flow in at createSession time.
  final initialPluginSettings = RuntimeSettings(
    plugins: {
      PluginId('cafeteria'): PluginConfig(enabled: true),
      PluginId('death_ray'): PluginConfig(enabled: true),
      PluginId('trap_department'): PluginConfig(enabled: true),
    },
  );
  manager.init(initialSettings: initialPluginSettings);

  // Service config targets `pluginId:serviceId` keys. That's how
  // settings reach a PluginService: its `config` field is filled from
  // the matching ServiceSettings on resolve.
  final initialSettings = RuntimeSettings(
    plugins: {
      PluginId('cafeteria'): PluginConfig(enabled: true),
      PluginId('death_ray'): PluginConfig(enabled: true),
      PluginId('trap_department'): PluginConfig(enabled: true),
    },
    services: {
      Pin('cafeteria', ['menu']): ServiceSettings(
        config: {'menu_tier': 'mystery_meat'},
      ),
      Pin('death_ray', ['controller']): ServiceSettings(
        config: {'power_level': 3},
      ),
      Pin('trap_department', ['trap']): ServiceSettings(
        config: {'trap_type': 'net'},
      ),
    },
  );
  // Stage the full settings into the manager before createSession uses them.
  manager.updateSettingsSnapshot(initialSettings);

  print('Creating session: plugins attach and print initial output:');
  final session = await manager.createSession();

  // Helper: reconcile session plugins with new settings, then publish on
  // the settings stream. This routes service config into session plugins
  // without going through the global reconciliation path.
  // `updateSessionSettings` already calls `plugin.detach` on newly-disabled
  // plugins, so no manual pre-detach is needed.
  Future<void> reconcile(RuntimeSettings next) async {
    await manager.runtime.updateSessionSettings(session, newSettings: next);
    manager.updateSettingsSnapshot(next);
  }

  print('\n=== Scenario A: Budget Boost ===');
  // All three plugins stay enabled; each gets a new service config.
  // Reconciliation invokes onPluginSettingsChanged on survivors so they
  // can re-read their config and adjust behavior.
  final boosted = RuntimeSettings(
    plugins: {
      PluginId('cafeteria'): PluginConfig(enabled: true),
      PluginId('death_ray'): PluginConfig(enabled: true),
      PluginId('trap_department'): PluginConfig(enabled: true),
    },
    services: {
      Pin('cafeteria', ['menu']): ServiceSettings(
        config: {'menu_tier': 'premium'},
      ),
      Pin('death_ray', ['controller']): ServiceSettings(
        config: {'power_level': 9},
      ),
      Pin('trap_department', ['trap']): ServiceSettings(
        config: {'trap_type': 'pit'},
      ),
    },
  );
  await reconcile(boosted);

  print('\n=== Scenario B: Budget Cut + Death Ray Disabled ===');
  // Disabling a plugin triggers detach (not onPluginSettingsChanged).
  final cuts = RuntimeSettings(
    plugins: {
      PluginId('cafeteria'): PluginConfig(enabled: true),
      PluginId('death_ray'): PluginConfig(enabled: false),
      PluginId('trap_department'): PluginConfig(enabled: true),
    },
    services: {
      Pin('cafeteria', ['menu']): ServiceSettings(
        config: {'menu_tier': 'decent'},
      ),
      Pin('trap_department', ['trap']): ServiceSettings(
        config: {'trap_type': 'net'},
      ),
    },
  );
  await reconcile(cuts);

  print('\n=== Plugin Status ===');
  print(
    '  Cafeteria enabled: ${manager.isPluginEnabled(const PluginId('cafeteria'))}',
  );
  print(
    '  Death Ray enabled: ${manager.isPluginEnabled(const PluginId('death_ray'))}',
  );
  print(
    '  Trap Dept enabled: ${manager.isPluginEnabled(const PluginId('trap_department'))}',
  );

  print('\n=== Scenario C: updateSettingsSnapshot (No Reconciliation) ===');
  // updateSettingsSnapshot swaps settings on the stream without running
  // attach/detach/onPluginSettingsChanged. The service's config is
  // updated in place; the next resolve or read reflects it.
  manager.updateSettingsSnapshot(
    cuts.copyWith(
      services: {
        Pin('cafeteria', ['menu']): const ServiceSettings(
          config: {'menu_tier': 'mystery_meat'},
        ),
        Pin('trap_department', ['trap']): const ServiceSettings(
          config: {'trap_type': 'net'},
        ),
      },
    ),
  );
  print('  (plugins were NOT notified: no hook fired)');

  print('\n=== Shutdown ===');
  await settingsSub.cancel();
  await manager.dispose();

  print('\nBudget meeting adjourned. Doug is updating his resume.');
  print("Gary offered to do Doug's job for free. Everyone said no.");
}
