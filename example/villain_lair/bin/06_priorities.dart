/// # 06: Priorities (Event Bus vs Service Registry)
///
/// Two priority systems that go in opposite directions:
/// - Event bus: lower number runs earlier in the cascade
/// - Service registry: higher number wins resolution
///
/// Covers:
/// - Staggered observers at priorities 0 / 5 / 10 / 99
/// - A priority-3 handler that stops the cascade via `envelope.stop()`
/// - Inspecting `EventEnvelope.stopped` on the return of `emit()`
/// - Competing `registerSingleton` entries resolved by priority
/// - `resolveAfter` for chain-of-responsibility fallback
library;

import 'package:plugin_kit/plugin_kit.dart';

class HeroSpotted {
  final String heroName;
  final String location;

  const HeroSpotted(this.heroName, {required this.location});
}

class ActivateTrap {
  final String trapName;
  final String target;

  const ActivateTrap(this.trapName, {required this.target});
}

/// Starts a coffee break. The priority-3 handler listens for this and, while
/// a break is active, short-circuits any `HeroSpotted` cascade.
class CoffeeBreak {
  final String department;

  const CoffeeBreak(this.department);
}

abstract class TrapService {
  String activate(String heroName);
}

class LaserGrid implements TrapService {
  @override
  String activate(String heroName) =>
      '🔴 Laser grid activated! $heroName walks through it because '
      "it's decorative at this point.";
}

class TrapdoorFloor implements TrapService {
  @override
  String activate(String heroName) =>
      '🕳️ Trapdoor opened! $heroName saw the welcome mat that says '
      '"DEFINITELY NOT A TRAP" and avoided it.';
}

class GarysTraps implements TrapService {
  @override
  String activate(String heroName) =>
      '📎 Gary deployed a tripwire made of paper clips and string. '
      "Against all odds... it actually worked. $heroName is confused.";
}

/// Registers three competing trap services (registry priority) and wires
/// four `HeroSpotted` handlers at staggered bus priorities. A `CoffeeBreak`
/// event flips a closure-local flag that the priority-3 handler uses to stop
/// the cascade. No plugin fields; all state flows through events.
class PriorityDemoPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('priority_demo');

  @override
  void register(ScopedServiceRegistry registry) {
    // Three trap services competing for the 'trap' slot. In a real system
    // each would come from its own plugin; we use registry.raw here as a
    // teaching shortcut to keep all three registrations in one file.
    registry.raw.registerSingleton<TrapService>(
      pluginId: const PluginId('doug'),
      serviceId: const ServiceId('trap'),
      instance: LaserGrid(),
      priority: 100,
    );
    registry.raw.registerSingleton<TrapService>(
      pluginId: const PluginId('engineering'),
      serviceId: const ServiceId('trap'),
      instance: TrapdoorFloor(),
      priority: 50,
    );
    registry.raw.registerSingleton<TrapService>(
      pluginId: const PluginId('gary'),
      serviceId: const ServiceId('trap'),
      instance: GarysTraps(),
      priority: 10,
    );
  }

  @override
  void attach(SessionPluginContext context) {
    // Closure state: whether a coffee break is currently active. Toggled by
    // CoffeeBreak events, read by the priority-3 handler. Not a plugin field.
    var coffeeBreakActive = false;

    context.bus.on<CoffeeBreak>((e) {
      coffeeBreakActive = true;
      print('☕ Coffee break started for ${e.event.department}.');
    });

    // Priority 0: coffee machine runs first.
    context.bus.on<HeroSpotted>((e) {
      print(
        '[Priority 0, Coffee Machine] Hero "${e.event.heroName}" '
        'spotted. Is anyone on break?',
      );
    }, priority: 0);

    // Priority 3: coffee protocol handler. Stops the cascade while a break is
    // active so security/Doug/Gary never see the alert.
    context.bus.on<HeroSpotted>((envelope) async {
      if (!coffeeBreakActive) return;
      print(
        '[Priority 3, Coffee Protocol] HOLD EVERYTHING. '
        "It's coffee time. The hero can wait.",
      );
      envelope.stop(envelope.event);
      return;
    }, priority: 3);

    // Priority 5: security.
    context.bus.on<HeroSpotted>((e) {
      print(
        '[Priority 5, Security] Acknowledged: ${e.event.heroName} '
        'is in ${e.event.location}.',
      );
    }, priority: 5);

    // Priority 10: Doug activates traps.
    context.bus.on<HeroSpotted>((e) {
      print('[Priority 10, Doug] Activating traps in ${e.event.location}!');
    }, priority: 10);

    // Priority 99: Gary, eventually.
    context.bus.on<HeroSpotted>((_) {
      print(
        "[Priority 99, Gary] Wait, what's happening? *looks up from phone*",
      );
    }, priority: 99);
  }
}

Future<void> main() async {
  final runtime = PluginRuntime(plugins: [PriorityDemoPlugin()])..init();
  final session = await runtime.createSession();

  // Part 1: Event bus priority. Handlers at 0/5/10/99 all run in order.
  print('=== Part 1: Event Bus Priority (lower runs first) ===\n');
  await session.emit(const HeroSpotted('Captain Valiant', location: 'Lobby'));

  // Part 1b: A CoffeeBreak event puts the coffee protocol handler on alert.
  // The next HeroSpotted is stopped at priority 3, before the priority-5 or
  // priority-10 handlers see it.
  print('\n=== Part 1b: Coffee Break Stops the Cascade ===\n');
  await session.emit(const CoffeeBreak('Trap Department'));
  final response = await session.emit(
    const HeroSpotted('Captain Valiant', location: 'Control Room'),
  );
  print('Event stopped? ${response.stopped}');
  print('Doug never got the alert. The hero escaped. Again.\n');

  // Part 2: Service registry priority. Opposite direction: higher wins.
  print('=== Part 2: Service Registry Priority (higher wins) ===\n');
  final registry = session.registry;

  final mainTrap = registry.resolve<TrapService>(const ServiceId('trap'));
  print('Primary trap: ${mainTrap.activate("Captain Valiant")}');

  // resolveAfter: skip the current winner, take the next-highest.
  final backupTrap = registry.resolveAfter<TrapService>(
    pluginId: const PluginId('doug'),
    serviceId: const ServiceId('trap'),
  );
  print('Backup trap: ${backupTrap.activate("Captain Valiant")}');

  final garysContribution = registry.resolveAfter<TrapService>(
    pluginId: const PluginId('engineering'),
    serviceId: const ServiceId('trap'),
  );
  print("Gary's trap: ${garysContribution.activate("Captain Valiant")}");

  print('\n=== Summary ===');
  print('Event bus:    lower number = runs earlier (pipeline)');
  print('Registry:     higher number = wins (competition)');

  await runtime.dispose();
}
