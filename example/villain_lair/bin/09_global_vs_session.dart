/// # 09: Global vs Session Plugins
///
/// Global plugins attach once at `runtime.init()` and live until the runtime
/// is disposed. Session plugins attach per session and detach on
/// `session.dispose()`. The global bus and each session bus are isolated
/// instances: cross-scope communication is always explicit.
///
/// Covers:
/// - `GlobalPlugin` vs `SessionPlugin`
/// - `GlobalPluginContext` vs `SessionPluginContext`
/// - `context.globalBus.emit()` to escalate from a session to the global bus
/// - `runtime.sessions.emit()` to broadcast from global to every live session
library;

import 'package:plugin_kit/plugin_kit.dart';

class WhiskersDecree {
  final String decree;

  const WhiskersDecree(this.decree);
}

class MissionUpdate {
  final String update;

  const MissionUpdate(this.update);
}

class WhiskersPetition {
  final String request;
  final String petitioner;

  const WhiskersPetition(this.request, {required this.petitioner});
}

/// Labels a session with a human-readable name. Emitted once per session
/// right after creation; the Mission Control plugin captures the label in
/// a closure-local variable and uses it in subsequent log prefixes so the
/// two sessions print distinctly in the shared output stream.
class SessionLabelSet {
  final String label;

  const SessionLabelSet(this.label);
}

/// Global plugin. Attaches once at runtime init and outlives all sessions.
class MrWhiskersPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('mr_whiskers');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<String>(
      const ServiceId('species'),
      () => 'Cat (allegedly). Possible elder god.',
      priority: 999,
    );
  }

  @override
  void attach(GlobalPluginContext context) {
    print('🐱 Mr. Whiskers: *judges everyone silently*');

    context.bus.on<WhiskersPetition>((e) {
      print(
        '🐱 Mr. Whiskers considers "${e.event.request}" from '
        '${e.event.petitioner}...',
      );

      final request = e.event.request.toLowerCase();
      if (request.contains('tuna') ||
          request.contains('nap') ||
          request.contains('cat')) {
        print('🐱 Mr. Whiskers: *slow blink of approval*');
      } else {
        print('🐱 Mr. Whiskers: *knocks petition off desk*');
      }
    });
  }
}

class MissionControlPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('mission_control');

  @override
  void attach(SessionPluginContext context) {
    // Closure-local label. A `SessionLabelSet` event emitted on this
    // session's bus right after creation populates it; subsequent handlers
    // use it to disambiguate log lines across concurrent sessions. No
    // plugin fields; per-session state lives in the closure.
    var label = 'unlabeled';
    String prefix() => '[Mission Control / $label]';

    context.bus.on<SessionLabelSet>((e) {
      label = e.event.label;
    });

    context.bus.on<MissionUpdate>((e) {
      print('  ${prefix()} ${e.event.update}');
    });

    // `runtime.sessions.emit<WhiskersDecree>(...)` broadcasts the event
    // onto every active session's bus, so a session handler can listen here
    // without touching the global bus directly.
    context.bus.on<WhiskersDecree>((e) {
      print(
        '  ${prefix()} Received decree from Mr. Whiskers: '
        '"${e.event.decree}"',
      );
    });
  }
}

/// Session plugin that escalates session events to the global bus.
class PetitionPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('petitioner');

  @override
  void attach(SessionPluginContext context) {
    context.bus.on<MissionUpdate>((e) async {
      if (e.event.update.contains('tuna')) {
        await context.globalBus.emit<WhiskersPetition>(
          event: const WhiskersPetition(
            'Mission involves tuna, requesting Mr. Whiskers blessing',
            petitioner: 'Gary',
          ),
        );
      }
    });
  }
}

Future<void> main() async {
  final runtime = PluginRuntime(
    plugins: [MrWhiskersPlugin(), MissionControlPlugin(), PetitionPlugin()],
  )..init();

  // init() attaches global plugins. They live until runtime.dispose().
  print('=== Initializing the Lair ===\n');

  print('\n=== Session A: Operation Tuna Heist ===\n');
  final sessionA = await runtime.createSession();
  // Label the session before emitting domain events so Mission Control's
  // log prefix is populated for the first MissionUpdate.
  await sessionA.emit(const SessionLabelSet('Tuna Heist'));

  await sessionA.emit(const MissionUpdate('Operation Tuna Heist begins'));
  await sessionA.emit(const MissionUpdate('Acquired tuna from the docks'));

  print('\n=== Session B: Operation Moon Laser ===\n');
  final sessionB = await runtime.createSession();
  await sessionB.emit(const SessionLabelSet('Moon Laser'));

  await sessionB.emit(const MissionUpdate('Operation Moon Laser begins'));
  await sessionB.emit(const MissionUpdate('Gary forgot the power cable'));

  // `runtime.sessions` is the SessionBroadcast extension on
  // List<PluginSession>: it emits on every live session's bus in one call.
  // Global→session messages always go through this (or an equivalent loop).
  // A plain `globalBus.emit(...)` would NOT reach session handlers.
  print('\n=== Global Decree (broadcast to all sessions) ===\n');
  await runtime.sessions.emit<WhiskersDecree>(
    const WhiskersDecree('Nap time is now mandatory. 2pm-4pm.'),
  );

  print('\n=== Session Broadcast: mission update ===\n');
  await runtime.sessions.emit<MissionUpdate>(
    const MissionUpdate(
      'ALERT: Mr. Whiskers has decreed nap time. '
      'All operations paused.',
    ),
  );

  // Sessions can be disposed while the global plugin keeps running. Keeping
  // the explicit pair here is the pedagogical point of this example: the
  // global plugin survives both session teardowns.
  print('\n=== Disposing Sessions ===\n');
  await sessionA.dispose();
  print('Session A (Tuna Heist) disposed.');
  await sessionB.dispose();
  print('Session B (Moon Laser) disposed.');

  print('\nMr. Whiskers is still here:');
  final species = runtime.globalContext.resolve<String>(
    const ServiceId('species'),
  );
  print('  Species: $species');

  await runtime.globalBus.emit<WhiskersPetition>(
    event: const WhiskersPetition(
      'Can we get more cat food?',
      petitioner: 'Dr. Nefarious',
    ),
  );

  print('\n=== Shutdown ===\n');
  await runtime.dispose();
  print('Runtime disposed. Mr. Whiskers allows it. This time.');
}
