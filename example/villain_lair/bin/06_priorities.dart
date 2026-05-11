/// # 06: Priorities (Event Bus and Service Registry, one polarity)
///
/// Both priority systems use the same convention: higher runs first /
/// higher wins. The event bus dispatches the highest-priority handler
/// first so it can mutate or stop the cascade; the registry resolves to
/// the highest-priority registration.
///
/// Covers:
/// - Staggered observers across the named [Priority] bands
/// - A high-priority handler that stops the cascade via `envelope.stop()`
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
/// event flips a closure-local flag that the high-priority Coffee Protocol
/// handler uses to stop the cascade. No plugin fields; all state flows
/// through events.
class PriorityDemoPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('priority_demo');

  @override
  void register(ScopedServiceRegistry registry) {
    // Three trap services competing for the 'trap' slot. In a real system
    // each would come from its own plugin; we use registry.raw here as a
    // teaching shortcut to keep all three registrations in one file.
    // Higher priority wins: Doug's laser grid is the primary.
    registry.raw.registerSingleton<TrapService>(
      pluginId: const PluginId('doug'),
      serviceId: const ServiceId('trap'),
      create: () => LaserGrid(),
      priority: Priority.elevated, // primary
    );
    registry.raw.registerSingleton<TrapService>(
      pluginId: const PluginId('engineering'),
      serviceId: const ServiceId('trap'),
      create: () => TrapdoorFloor(),
      priority: Priority.normal, // mid-stack backup
    );
    registry.raw.registerSingleton<TrapService>(
      pluginId: const PluginId('gary'),
      serviceId: const ServiceId('trap'),
      create: () => GarysTraps(),
      priority: Priority.low, // last-resort
    );
  }

  @override
  void attach(SessionPluginContext context) {
    // Closure state: whether a coffee break is currently active. Toggled by
    // CoffeeBreak events, read by the Coffee Protocol handler. Not a plugin
    // field.
    var coffeeBreakActive = false;

    context.bus.on<CoffeeBreak>((e) {
      coffeeBreakActive = true;
      print('☕ Coffee break started for ${e.event.department}.');
    });

    // High priority: Coffee Protocol stops the cascade before anyone else
    // sees the alert, while a coffee break is active. Higher = runs first.
    context.bus.on<HeroSpotted>((envelope) async {
      if (!coffeeBreakActive) return;
      print(
        '[Priority.high, Coffee Protocol] HOLD EVERYTHING. '
        "It's coffee time. The hero can wait.",
      );
      envelope.stop(envelope.event);
      return;
    }, priority: Priority.high);

    // Elevated: Coffee Machine pings before security/Doug. It only observes;
    // it does not stop.
    context.bus.on<HeroSpotted>((e) {
      print(
        '[Priority.elevated, Coffee Machine] Hero "${e.event.heroName}" '
        'spotted. Is anyone on break?',
      );
    }, priority: Priority.elevated);

    // Normal: Security gets the alert in the mid-stack default slot.
    context.bus.on<HeroSpotted>((e) {
      print(
        '[Priority.normal, Security] Acknowledged: ${e.event.heroName} '
        'is in ${e.event.location}.',
      );
    }, priority: Priority.normal);

    // Low: Doug activates traps after security has logged the sighting.
    context.bus.on<HeroSpotted>((e) {
      print('[Priority.low, Doug] Activating traps in ${e.event.location}!');
    }, priority: Priority.low);

    // Lowest: Gary notices last, when everyone else has already reacted.
    context.bus.on<HeroSpotted>((_) {
      print(
        "[Priority.lowest, Gary] Wait, what's happening? *looks up from phone*",
      );
    }, priority: Priority.lowest);
  }
}

Future<void> main() async {
  final runtime = PluginRuntime(plugins: [PriorityDemoPlugin()])..init();
  final session = await runtime.createSession();

  // Part 1: Event bus priority. Handlers run highest-first: Coffee Machine
  // (elevated) -> Security (normal) -> Doug (low) -> Gary (lowest). Coffee
  // Protocol (high) only fires when a break is active.
  print('=== Part 1: Event Bus Priority (higher runs first) ===\n');
  await session.emit(const HeroSpotted('Captain Valiant', location: 'Lobby'));

  // Part 1b: A CoffeeBreak event puts the Coffee Protocol handler on alert.
  // The next HeroSpotted is stopped at Priority.high, before Coffee Machine,
  // Security, Doug, or Gary see it.
  print('\n=== Part 1b: Coffee Break Stops the Cascade ===\n');
  await session.emit(const CoffeeBreak('Trap Department'));
  final response = await session.emit(
    const HeroSpotted('Captain Valiant', location: 'Control Room'),
  );
  print('Event stopped? ${response.stopped}');
  print('Doug never got the alert. The hero escaped. Again.\n');

  // Part 2: Service registry priority. Same polarity: higher wins.
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
  print('Event bus:  higher priority runs first (intercept early, stop early)');
  print('Registry:   higher priority wins (override late, beat the default)');

  await runtime.dispose();
}
