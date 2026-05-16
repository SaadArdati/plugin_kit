/// # 12: Plugin Dependencies
///
/// A plugin can declare a `dependencies` set of plugin ids. The runtime
/// disables a plugin at session creation if any dependency is missing or
/// itself disabled. This cascades through transitive chains.
///
/// Covers:
/// - `Plugin.dependencies`: declaring required plugin ids
/// - Auto-disable when a dependency is missing or disabled
/// - Transitive disable through a chain (A depends on B depends on C)
/// - `FeatureFlag.experimental`: opt-in enabling
/// - `FeatureFlag.locked`: cannot be disabled
library;

import 'package:plugin_kit/plugin_kit.dart';

class GetawayCarPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('getaway_car');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<String>(
      const ServiceId('vehicle'),
      () => '1997 Minivan (painted black, poorly)',
      priority: 50,
    );
  }
}

/// Depends on `getaway_car`. Auto-disabled if that plugin isn't available.
class VaultCrackerPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('vault_cracker');

  @override
  Set<PluginId> get dependencies => {const PluginId('getaway_car')};

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<String>(
      const ServiceId('vault_tool'),
      () => 'Industrial Drill (disguised as a large thermos)',
      priority: 50,
    );
  }
}

/// Transitive chain: heist_coordinator -> vault_cracker -> getaway_car.
/// Disable getaway_car and the whole chain collapses.
class HeistCoordinatorPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('heist_coordinator');

  @override
  Set<PluginId> get dependencies => {
    const PluginId('vault_cracker'),
    const PluginId('getaway_car'),
  };

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<String>(
      const ServiceId('plan'),
      () =>
          'Step 1: Arrive. '
          'Step 2: Crack vault. '
          'Step 3: Leave. '
          'Step 4: Gary ruins everything.',
      priority: 50,
    );
  }
}

/// Feature-flagged as experimental. Disabled by default; must be explicitly
/// enabled in `PluginSettings`.
class GarysTeleporterPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('garys_teleporter');

  @override
  List<FeatureFlag> get featureFlags => const [.experimental];

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<String>(
      const ServiceId('device'),
      () => 'Teleporter (made of staplers and duct tape)',
      priority: 50,
    );
  }
}

/// Feature-flagged as locked. Cannot be disabled by settings.
class LairCorePlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('lair_core');

  @override
  List<FeatureFlag> get featureFlags => const [.locked];

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<String>(
      const ServiceId('power'),
      () => 'Nuclear Fusion Reactor (Mr. Whiskers naps on it)',
      priority: 100,
    );
  }
}

Future<void> main() async {
  // Scenario 1: full chain enabled. Experimental plugin omitted, so it's
  // off by default.
  print('=== Scenario 1: All Dependencies Met ===\n');

  var runtime = PluginRuntime(
    plugins: [
      LairCorePlugin(),
      GetawayCarPlugin(),
      VaultCrackerPlugin(),
      HeistCoordinatorPlugin(),
      GarysTeleporterPlugin(),
    ],
  )..init();

  var session = await runtime.createSession(
    settings: RuntimeSettings(
      plugins: {
        PluginId('lair_core'): PluginConfig(enabled: true),
        PluginId('getaway_car'): PluginConfig(enabled: true),
        PluginId('vault_cracker'): PluginConfig(enabled: true),
        PluginId('heist_coordinator'): PluginConfig(enabled: true),
      },
    ),
  );

  print(
    'Heist plan: ${session.context.resolve<String>(const ServiceId('plan'))}',
  );
  print(
    'Vault tool: '
    '${session.context.resolve<String>(const ServiceId('vault_tool'))}',
  );
  print(
    'Vehicle: ${session.context.resolve<String>(const ServiceId('vehicle'))}',
  );
  print('Power: ${session.context.resolve<String>(const ServiceId('power'))}');
  print(
    "Gary's teleporter: "
    '${session.context.maybeResolve<String>(const ServiceId('device')) ?? "(experimental, not enabled)"}',
  );

  await runtime.dispose();

  // Scenario 2: disable getaway_car. vault_cracker and heist_coordinator
  // auto-disable because their dependency chain is broken.
  print('\n=== Scenario 2: Getaway Car Disabled ===\n');

  runtime = PluginRuntime(
    plugins: [
      LairCorePlugin(),
      GetawayCarPlugin(),
      VaultCrackerPlugin(),
      HeistCoordinatorPlugin(),
    ],
  )..init();

  session = await runtime.createSession(
    settings: RuntimeSettings(
      plugins: {
        PluginId('getaway_car'): PluginConfig(enabled: false),
        PluginId('vault_cracker'): PluginConfig(enabled: true),
        PluginId('heist_coordinator'): PluginConfig(enabled: true),
      },
    ),
  );

  final plan = session.context.maybeResolve<String>(const ServiceId('plan'));
  final tool = session.context.maybeResolve<String>(
    const ServiceId('vault_tool'),
  );
  final car = session.context.maybeResolve<String>(const ServiceId('vehicle'));

  print('Plan: ${plan ?? "(no plan; coordinator auto-disabled)"}');
  print('Vault tool: ${tool ?? "(no tool; vault cracker auto-disabled)"}');
  print('Vehicle: ${car ?? "(no car; Janet cut the fuel budget)"}');
  print('\nThe heist is off. Gary suggests taking the bus.');

  await runtime.dispose();

  // Scenario 3: opt into the experimental plugin.
  print('\n=== Scenario 3: Enabling Gary\'s Experimental Teleporter ===\n');

  runtime = PluginRuntime(plugins: [LairCorePlugin(), GarysTeleporterPlugin()])
    ..init();

  session = await runtime.createSession(
    settings: RuntimeSettings(
      plugins: {PluginId('garys_teleporter'): PluginConfig(enabled: true)},
    ),
  );

  final device = session.context.maybeResolve<String>(
    const ServiceId('device'),
  );
  print('Teleporter: ${device ?? "(not found)"}');
  print("It's made of staplers. What could go wrong?");

  await runtime.dispose();

  print(
    '\nDependency lesson: Always have a getaway car before starting a heist.',
  );
  print("Gary's lesson: Don't make teleporters from staplers.");
}
