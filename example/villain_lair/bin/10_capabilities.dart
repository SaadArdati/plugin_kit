/// # 10: Capabilities
///
/// A service can carry a set of `Capability` objects. Capabilities are
/// readable from the registry wrapper without instantiating the service,
/// which makes them useful for UI listings, routing, and feature detection.
///
/// Covers:
/// - Defining custom `Capability` subclasses
/// - Attaching capabilities at registration via `capabilities: {...}`
/// - `resolveRaw()`: inspect a wrapper without building the service
/// - `CapabilityLookup.hasType<T>()` and `getOfType<T>()`
/// - `listCapabilitiesOfNamespace()`: aggregate across a namespace
library;

import 'package:plugin_kit/plugin_kit.dart';

class HeavyMachineryCapability extends Capability {
  final String machineType;
  final int requiredClearanceLevel;

  const HeavyMachineryCapability(
    this.machineType, {
    this.requiredClearanceLevel = 1,
  });
}

class StealthCapability extends Capability {
  final double stealthRating; // 0.0 = Gary, 1.0 = ninja
  const StealthCapability(this.stealthRating);
}

class CoffeeCapability extends Capability {
  final List<String> specialties;

  const CoffeeCapability(this.specialties);
}

class Minion extends PluginService {
  final String name;

  Minion(this.name);
}

/// Owns Doug: heavy machinery certified, passable stealth.
class TrapDepartmentPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('trap_department');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerFactory<Minion>(
      const Namespace('field_ops')('doug'),
      () => Minion('Doug'),
      priority: 80,
      capabilities: {
        const HeavyMachineryCapability('Death Ray', requiredClearanceLevel: 3),
        const StealthCapability(0.6),
      },
    );
  }
}

/// Owns Gary: can technically make coffee, visible from orbit.
class InternProgramPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('intern_program');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerFactory<Minion>(
      const Namespace('field_ops')('gary'),
      () => Minion('Gary'),
      priority: 10,
      capabilities: {
        const CoffeeCapability(['Vanilla Latte', 'Spilled Everything']),
        const StealthCapability(0.0),
      },
    );
  }
}

/// Owns Mr. Whiskers: top priority, certified for all machinery, perfect stealth.
class WhiskersPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('mr_whiskers');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerFactory<Minion>(
      const Namespace('field_ops')('whiskers'),
      () => Minion('Mr. Whiskers'),
      priority: 999,
      capabilities: {
        const HeavyMachineryCapability(
          'All of them',
          requiredClearanceLevel: 99,
        ),
        const StealthCapability(1.0),
      },
    );
  }
}

Future<void> main() async {
  final runtime = PluginRuntime(
    plugins: [TrapDepartmentPlugin(), InternProgramPlugin(), WhiskersPlugin()],
  )..init();
  final session = await runtime.createSession();
  final registry = session.registry;

  // Part 1: query capabilities via resolveRaw, no instantiation.
  print('=== Skill Assessment (No Instantiation) ===\n');

  for (final slot in ['doug', 'gary', 'whiskers']) {
    final wrapper = registry.resolveRaw<Minion>(ServiceId('field_ops.$slot'));
    print(
      '$slot (pluginId: ${wrapper.pluginId}, priority: ${wrapper.priority}):',
    );
    print(
      '  HeavyMachinery: ${wrapper.capabilities.hasType<HeavyMachineryCapability>()}',
    );
    print(
      '  Stealth:       ${wrapper.capabilities.hasType<StealthCapability>()}',
    );
    print(
      '  Coffee:        ${wrapper.capabilities.hasType<CoffeeCapability>()}',
    );

    final machinery = wrapper.capabilities
        .getOfType<HeavyMachineryCapability>();
    if (machinery != null) {
      print(
        '    → machine: ${machinery.machineType}, '
        'clearance: ${machinery.requiredClearanceLevel}',
      );
    }
    final stealth = wrapper.capabilities.getOfType<StealthCapability>();
    if (stealth != null) {
      print('    → stealth rating: ${stealth.stealthRating}');
    }
    final coffee = wrapper.capabilities.getOfType<CoffeeCapability>();
    if (coffee != null) {
      print('    → coffee specialties: ${coffee.specialties}');
    }
    print('');
  }

  // Part 2: aggregate capabilities across the namespace.
  print('=== Field Ops: Combined Team Capabilities ===\n');

  final teamCaps = registry.listCapabilitiesOfNamespace(
    const Namespace('field_ops'),
  );
  print('Total capabilities in field_ops: ${teamCaps.length}');
  print(
    '  Heavy machinery experts: '
    '${teamCaps.whereType<HeavyMachineryCapability>().length}',
  );
  print(
    '  Stealth agents:         '
    '${teamCaps.whereType<StealthCapability>().length}',
  );
  print(
    '  Coffee makers:          '
    '${teamCaps.whereType<CoffeeCapability>().length}',
  );

  await runtime.dispose();
}
