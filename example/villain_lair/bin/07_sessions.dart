/// # 07: Session Management
///
/// Each session has its own service registry and event bus. Running two
/// sessions in parallel shows that neither's state bleeds into the other,
/// and that sessions can be disposed independently of the runtime.
///
/// Covers:
/// - `runtime.createSession()` and `session.dispose()`
/// - Per-session service instances (lazy singleton scoped to a session)
/// - Emitting events on a session bus
/// - Independent disposal of one session while another keeps running
library;

import 'package:plugin_kit/plugin_kit.dart';

class SchemeStarted {
  final String schemeName;
  final String leadVillain;

  const SchemeStarted(this.schemeName, {required this.leadVillain});
}

class SchemeProgress {
  final String update;
  final double completionPercent;

  const SchemeProgress(this.update, {required this.completionPercent});
}

class SchemeEnded {
  final String result;

  const SchemeEnded(this.result);
}

/// Scoped per session. Fresh instance in each session so isolation is
/// observable from the outside.
class DefaultSchemeTracker {
  String currentScheme = 'none';

  final List<String> log = [];

  void logEvent(String event) {
    log.add(event);
  }
}

class SchemePlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('scheme_ops');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerLazySingleton<DefaultSchemeTracker>(
      const ServiceId('tracker'),
      () => DefaultSchemeTracker(),
      priority: 50,
    );
  }

  @override
  void attach(SessionPluginContext context) {
    context.bus.on<SchemeStarted>((e) {
      final tracker = context.resolve<DefaultSchemeTracker>(
        const ServiceId('tracker'),
      );
      tracker.currentScheme = e.event.schemeName;
      tracker.logEvent(
        'Scheme "${e.event.schemeName}" started by ${e.event.leadVillain}',
      );
    });

    context.bus.on<SchemeProgress>((e) {
      final tracker = context.resolve<DefaultSchemeTracker>(
        const ServiceId('tracker'),
      );
      tracker.logEvent(
        '  [${e.event.completionPercent.toStringAsFixed(0)}%] '
        '${e.event.update}',
      );
    });

    context.bus.on<SchemeEnded>((e) {
      final tracker = context.resolve<DefaultSchemeTracker>(
        const ServiceId('tracker'),
      );
      tracker.logEvent('Result: ${e.event.result}');
    });
  }
}

Future<void> main() async {
  final runtime = PluginRuntime(plugins: [SchemePlugin()])..init();

  print('=== Launching Two Simultaneous Evil Schemes ===\n');

  final moonbeam = await runtime.createSession();
  final staplerHeist = await runtime.createSession();

  // Each session resolves its own tracker. Identity check proves they're
  // separate instances.
  final moonbeamTracker = moonbeam.context.resolve<DefaultSchemeTracker>(
    const ServiceId('tracker'),
  );
  final staplerTracker = staplerHeist.context.resolve<DefaultSchemeTracker>(
    const ServiceId('tracker'),
  );
  print('Same tracker? ${identical(moonbeamTracker, staplerTracker)}');

  print('\n--- Operation Moonbeam ---');
  await moonbeam.emit(
    const SchemeStarted('Operation Moonbeam', leadVillain: 'Dr. Nefarious'),
  );
  await moonbeam.emit(
    const SchemeProgress('Death ray aimed at the moon', completionPercent: 25),
  );
  await moonbeam.emit(
    const SchemeProgress(
      'Gary accidentally unplugged the death ray to charge his phone',
      completionPercent: 10,
    ),
  );
  await moonbeam.emit(
    const SchemeProgress(
      'Death ray re-aimed after Gary was escorted out',
      completionPercent: 50,
    ),
  );
  await moonbeam.emit(
    const SchemeEnded('Moon slightly singed. Dr. Nefarious claims victory.'),
  );

  print('\n--- Operation Stapler Heist ---');
  await staplerHeist.emit(
    const SchemeStarted('Operation Stapler Heist', leadVillain: 'Gary'),
  );
  await staplerHeist.emit(
    const SchemeProgress('Infiltrated OfficeMax', completionPercent: 50),
  );
  await staplerHeist.emit(
    const SchemeProgress(
      'Acquired 47 staplers. Lost 46 on the way out.',
      completionPercent: 90,
    ),
  );
  await staplerHeist.emit(
    const SchemeEnded(
      'Success! One stapler acquired. Gary considers this a win.',
    ),
  );

  print('\n=== Scheme Reports ===\n');

  print('Moonbeam log:');
  for (final entry in moonbeamTracker.log) {
    print('  $entry');
  }

  print('\nStapler Heist log:');
  for (final entry in staplerTracker.log) {
    print('  $entry');
  }

  print('\nMoonbeam entries: ${moonbeamTracker.log.length}');
  print('Stapler Heist entries: ${staplerTracker.log.length}');

  print('\n=== Independent Session Disposal ===\n');
  print('Moonbeam bus disposed? ${moonbeam.bus.isDisposed}');
  print('Stapler Heist bus disposed? ${staplerHeist.bus.isDisposed}');

  await moonbeam.dispose();
  print('Disposed Moonbeam session only.');
  print('Moonbeam bus disposed? ${moonbeam.bus.isDisposed}');
  print('Stapler Heist bus disposed? ${staplerHeist.bus.isDisposed}');

  await staplerHeist.emit(
    const SchemeProgress(
      'Stashed the stapler in Gary\'s backpack and kept moving',
      completionPercent: 95,
    ),
  );
  print('Stapler Heist still processed events after Moonbeam disposal.');
  print('Stapler Heist entries now: ${staplerTracker.log.length}');

  await runtime.dispose();
  print('\nAll schemes concluded. The lair is quiet. For now.');
}
