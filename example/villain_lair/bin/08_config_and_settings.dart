/// # 08: Configuration & Settings
///
/// Covers:
/// - `ConfigNode`: type-safe reads with coercion
/// - `RuntimeSettings` / `PluginConfig` / `ServiceSettings` and JSON I/O
/// - Scoped service keys (`pluginId:serviceId`)
/// - Wildcard overrides (`*:serviceId`) targeting the priority winner
/// - Automatic `config` injection into a `PluginService`
/// - `Pin.fromWire`
library;

import 'package:plugin_kit/plugin_kit.dart';

/// A PluginService reads its config from the injected `config` node.
class DeathRayController extends PluginService {
  DeathRayController();

  int get powerLevel => config.getInt('power_level') ?? 5;
  String get target => config.getString('target') ?? 'the moon';
  bool get safetyEnabled => config.getBool('safety') ?? true;
  double get chargeRate => config.getDouble('charge_rate') ?? 1.0;
  List<String>? get authorizedUsers => config.list<String>('authorized_users');

  String status() =>
      'Death Ray Status:\n'
      '  Power Level: $powerLevel/10\n'
      '  Target: $target\n'
      '  Safety: ${safetyEnabled ? "ON (Janet insisted)" : "OFF (uh oh)"}\n'
      '  Charge Rate: ${chargeRate}x\n'
      '  Authorized Users: ${authorizedUsers ?? "(everyone, Gary, no!)"}';
}

class StaplerTracker extends PluginService {
  StaplerTracker();

  int get staplerCount => config.getInt('count') ?? 0;
  String get favoriteColor => config.getString('color') ?? 'red';
  bool get isHappy => (config.getInt('count') ?? 0) > 0;
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
}

class GarysPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('garys_stuff');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerLazySingleton<StaplerTracker>(
      const ServiceId('stapler_tracker'),
      () => StaplerTracker(),
      priority: 50,
    );
  }
}

Future<void> main() async {
  // Part 1: ConfigNode with type coercion.
  print('=== Part 1: ConfigNode Basics ===\n');

  final rawConfig = ConfigNode({
    'power_level': 10,
    'target': 'the moon',
    'safety': false,
    'charge_rate': 2.5,
    'authorized_users': ['Dr. Nefarious', 'Doug'],
    // Coercion demos.
    'string_number': '42',
    'string_bool': 'true',
    'int_as_double': 7,
    'zero_as_bool': 0,
  });

  print('Direct access:');
  print('  power_level (int): ${rawConfig.getInt('power_level')}');
  print('  target (string): ${rawConfig.getString('target')}');
  print('  safety (bool): ${rawConfig.getBool('safety')}');
  print('  charge_rate (double): ${rawConfig.getDouble('charge_rate')}');
  print(
    '  authorized_users (list): ${rawConfig.list<String>('authorized_users')}',
  );

  print('\nType coercion:');
  print('  "42" as int: ${rawConfig.getInt('string_number')}');
  print('  "true" as bool: ${rawConfig.getBool('string_bool')}');
  print('  7 as double: ${rawConfig.getDouble('int_as_double')}');
  print('  0 as bool: ${rawConfig.getBool('zero_as_bool')}');

  print('\nMissing keys:');
  print('  missing key: ${rawConfig.getString('does_not_exist')}'); // null
  print('  has "target": ${rawConfig.has('target')}'); // true
  print('  has "missing": ${rawConfig.has('does_not_exist')}'); // false

  // Part 2: PluginSettings (code form, plus JSON round-trip).
  print('\n=== Part 2: PluginSettings ===\n');

  final settings = RuntimeSettings(
    plugins: {
      PluginId('death_ray'): PluginConfig(enabled: true),
      PluginId('garys_stuff'): PluginConfig(enabled: true),
    },
    services: {
      // Plugin-scoped key format: "pluginId:serviceId".
      Pin('death_ray', ['controller']): ServiceSettings(
        config: {
          'power_level': 10,
          'target': 'the moon',
          'safety': false,
          'charge_rate': 2.5,
          'authorized_users': ['Dr. Nefarious', 'Doug'],
        },
      ),
      Pin('garys_stuff', ['stapler_tracker']): ServiceSettings(
        config: {'count': 1, 'color': 'red'},
      ),
    },
  );

  final json = settings.toJson();
  final restored = RuntimeSettings.fromJson(json);
  print('Settings survive JSON round-trip: ${settings == restored}');

  print(
    'Death ray enabled: ${settings.isPluginEnabled(const PluginId('death_ray'))}',
  );
  print(
    'Gary enabled: ${settings.isPluginEnabled(const PluginId('garys_stuff'))}',
  );
  // Default for unknown plugin ids is true.
  print(
    'Unicorn plugin: ${settings.isPluginEnabled(const PluginId('unicorn'))}',
  );

  // Part 3: settings injection. Resolving a PluginService fills `config`
  // from the matching ServiceSettings.
  print('\n=== Part 3: Settings Injection ===\n');

  final runtime = PluginRuntime(plugins: [DeathRayPlugin(), GarysPlugin()])
    ..init();

  final session = await runtime.createSession(settings: settings);

  final deathRay = session.context.resolve<DeathRayController>(
    const ServiceId('controller'),
  );
  print(deathRay.status());

  print('');

  final staplers = session.context.resolve<StaplerTracker>(
    const ServiceId('stapler_tracker'),
  );
  print('Gary\'s Stapler Report:');
  print('  Count: ${staplers.staplerCount}');
  print('  Favorite Color: ${staplers.favoriteColor}');
  print('  Is Happy: ${staplers.isHappy}');

  // Part 4: wildcard overrides. "*:serviceId" applies to whichever plugin
  // wins the resolution for that service ID.
  print('\n=== Part 4: Wildcard Overrides ===\n');

  final wildcardSettings = RuntimeSettings(
    plugins: {
      PluginId('death_ray'): PluginConfig(enabled: true),
      PluginId('garys_stuff'): PluginConfig(enabled: true),
    },
    services: {
      Pin.wildcard(['controller']): ServiceSettings(
        config: {
          'power_level': 1,
          'target': 'a small rock',
          'safety': true,
          'charge_rate': 0.1,
        },
      ),
    },
  );

  final session2 = await runtime.createSession(settings: wildcardSettings);
  final nerfedRay = session2.context.resolve<DeathRayController>(
    const ServiceId('controller'),
  );
  print('After Janet got involved (wildcard override):');
  print(nerfedRay.status());

  await runtime.dispose();
  print('\nSettings saved. Gary backed up his stapler config three times.');
}
