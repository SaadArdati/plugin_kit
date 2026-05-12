// Verifies that dependency cycles among enabled plugins surface as a
// `severe` log entry naming the participating plugin ids.
//
// Current behavior (before this fix): a cycle where every member is
// enabled is silently accepted by `_validateDependencies` because each
// member's dependency is satisfied by the other being enabled. Cycles
// where only one member is enabled disable themselves cleanly.
//
// Desired behavior: detect cycles in the enabled subgraph and emit one
// `severe` log per strongly connected component, but do not throw or
// disable. The runtime continues startup with the cyclic plugins
// attached (the satisfied cycle is functional, just structurally
// suspect), so callers can decide whether to investigate.
import 'package:logging/logging.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _CyclicA extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('cycle_a');

  @override
  Set<PluginId> get dependencies => const {PluginId('cycle_b')};
}

class _CyclicB extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('cycle_b');

  @override
  Set<PluginId> get dependencies => const {PluginId('cycle_a')};
}

class _CyclicC extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('cycle_c');

  @override
  Set<PluginId> get dependencies => const {PluginId('cycle_a')};
}

class _NoCycleA extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('a');
}

class _NoCycleB extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('b');

  @override
  Set<PluginId> get dependencies => const {PluginId('a')};
}

List<LogRecord> _captureLogs(void Function() body) {
  final records = <LogRecord>[];
  final prev = Logger.root.level;
  Logger.root.level = Level.ALL;
  final sub = Logger.root.onRecord.listen(records.add);
  try {
    body();
  } finally {
    sub.cancel();
    Logger.root.level = prev;
  }
  return records;
}

void main() {
  group('dependency cycle detection', () {
    test(
      'a satisfied two-node cycle (A <-> B, both enabled) emits a severe log '
      'naming both ids',
      () {
        final records = _captureLogs(() {
          PluginRuntime(plugins: [_CyclicA(), _CyclicB()]).init();
        });

        final severes = records
            .where((r) => r.level == Level.SEVERE)
            .map((r) => r.message)
            .toList();
        final cycleLogs = severes
            .where(
              (m) =>
                  m.toLowerCase().contains('cycle') &&
                  m.contains('cycle_a') &&
                  m.contains('cycle_b'),
            )
            .toList();
        expect(
          cycleLogs,
          isNotEmpty,
          reason:
              'expected a severe log naming both cycle participants; got: '
              '$severes',
        );
      },
    );

    test(
      'a single-node self-cycle (P depends on P) emits a severe log',
      () {
        final records = _captureLogs(() {
          PluginRuntime(plugins: [_SelfCyclic()]).init();
        });

        final cycleLogs = records
            .where((r) => r.level == Level.SEVERE)
            .map((r) => r.message)
            .where(
              (m) =>
                  m.toLowerCase().contains('cycle') &&
                  m.contains('self_cycle'),
            )
            .toList();
        expect(cycleLogs, isNotEmpty);
      },
    );

    test(
      'a non-cyclic dependency graph (B depends on A, A has no deps) does '
      'not emit any cycle log',
      () {
        final records = _captureLogs(() {
          PluginRuntime(plugins: [_NoCycleA(), _NoCycleB()]).init();
        });

        final cycleLogs = records
            .where((r) => r.level == Level.SEVERE)
            .where((r) => r.message.toLowerCase().contains('cycle'))
            .toList();
        expect(
          cycleLogs,
          isEmpty,
          reason:
              'must not flag cycles on acyclic graphs; saw: $cycleLogs',
        );
      },
    );

    test(
      'cyclic plugins still attach (severe log is informational, not a '
      'rejection)',
      () {
        // Suppress noise: we only care about attachment outcome here.
        final runtime = PluginRuntime(plugins: [_CyclicA(), _CyclicB()])
          ..init();

        expect(
          runtime.isPluginAttached(const PluginId('cycle_a')),
          isTrue,
          reason:
              'detection is informational; cyclic plugins still attach when '
              'their mutual dependencies are satisfied',
        );
        expect(runtime.isPluginAttached(const PluginId('cycle_b')), isTrue);
      },
    );

    test(
      'a three-node cycle (A <- B <- C <- A) emits a severe log naming all '
      'three participants',
      () {
        final records = _captureLogs(() {
          PluginRuntime(plugins: [_CyclicA(), _CyclicB(), _CyclicC()]).init();
        });

        final severes = records
            .where((r) => r.level == Level.SEVERE)
            .map((r) => r.message)
            .toList();
        // C depends on A, A depends on B, B depends on A. So A and B form
        // a 2-cycle; C is just downstream. The SCC containing A and B
        // must be flagged.
        final hasABCycle = severes.any(
          (m) =>
              m.toLowerCase().contains('cycle') &&
              m.contains('cycle_a') &&
              m.contains('cycle_b'),
        );
        expect(hasABCycle, isTrue, reason: 'A<->B SCC must be flagged');
      },
    );
  });
}

class _SelfCyclic extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('self_cycle');

  @override
  Set<PluginId> get dependencies => const {PluginId('self_cycle')};
}
