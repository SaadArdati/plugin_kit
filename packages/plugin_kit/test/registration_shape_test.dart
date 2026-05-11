// Pins the SessionPlugin singleton-shape contract.
//
//   registry.registerSingleton<S>(id, () => S());     // fresh per session
//   registry.registerSingleton<S>(id, () => _shared); // shared (closure
//                                                     // captures a long-lived
//                                                     // value)
//
// The factory runs once per register() call. SessionPlugin re-runs register()
// per session, so the closure body decides whether each session gets its own
// instance or shares.

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

// === Fixtures =============================================================

/// Service whose identity we can observe (default reference equality) and
/// which carries mutable state.
class CounterService {
  int count = 0;

  void bump() => count += 1;
}

const _counterServiceId = ServiceId('counter');

/// SessionPlugin whose factory closure constructs a fresh service every time
/// it runs. patterns.md #3 shape; intended per-session isolation.
class InlineFactoryCounterPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('inline_factory_counter_plugin');

  @override
  void register(ScopedServiceRegistry registry) {
    // The factory expression `() => CounterService()` constructs a NEW
    // CounterService each time the factory runs. The framework runs the
    // factory once at registration time, and `register()` runs once per
    // session, so each session gets its own instance.
    registry.registerSingleton<CounterService>(
      _counterServiceId,
      () => CounterService(),
    );
  }
}

/// SessionPlugin whose factory closure visibly captures a plugin-level
/// field. Sharing is now expressed by what the closure references, not by
/// the absence of a constructor call.
class SharedFactoryCounterPlugin extends SessionPlugin {
  /// One CounterService for the lifetime of the plugin instance, which
  /// PluginRuntime shares across sessions.
  final CounterService _shared = CounterService();

  @override
  PluginId get pluginId => const PluginId('shared_factory_counter_plugin');

  @override
  void register(ScopedServiceRegistry registry) {
    // The closure `() => _shared` visibly captures the plugin-level field.
    // Sharing across sessions is now legible at the call site instead of
    // hidden in the difference between `T()` and `_field`.
    registry.registerSingleton<CounterService>(
      _counterServiceId,
      () => _shared,
    );
  }
}

// === Tests ================================================================

void main() {
  group('SessionPlugin singleton factory contract', () {
    test(
      'inline factory `() => T()` yields a FRESH instance per session',
      () async {
        final runtime = PluginRuntime(plugins: [InlineFactoryCounterPlugin()])
          ..init();
        final sessionA = await runtime.createSession();
        final sessionB = await runtime.createSession();

        final svcA = sessionA.context.resolve<CounterService>(
          _counterServiceId,
        );
        final svcB = sessionB.context.resolve<CounterService>(
          _counterServiceId,
        );

        expect(
          identical(svcA, svcB),
          isFalse,
          reason:
              'Each session should resolve its own CounterService '
              'instance when the factory closure constructs inline.',
        );

        svcA.bump();
        svcA.bump();
        svcA.bump();

        expect(svcA.count, 3);
        expect(
          svcB.count,
          0,
          reason:
              'Bumping session A must NOT be visible to session B '
              'under per-session inline construction.',
        );
      },
    );

    test('factory closing over a field `() => _shared` SHARES one instance '
        'across sessions (intentional, visible at the call site)', () async {
      final runtime = PluginRuntime(plugins: [SharedFactoryCounterPlugin()])
        ..init();
      final sessionA = await runtime.createSession();
      final sessionB = await runtime.createSession();

      final svcA = sessionA.context.resolve<CounterService>(_counterServiceId);
      final svcB = sessionB.context.resolve<CounterService>(_counterServiceId);

      expect(
        identical(svcA, svcB),
        isTrue,
        reason:
            'Both sessions must resolve THE SAME CounterService '
            'instance when the factory closes over a plugin-level field. '
            'This is now the explicit way to share state across sessions; '
            'the closure capture is visible at the call site.',
      );

      svcA.bump();
      svcA.bump();
      svcA.bump();

      expect(svcA.count, 3);
      expect(
        svcB.count,
        3,
        reason:
            'Intentional cross-session sharing: session B sees '
            'mutations made by session A because both resolve the same '
            'instance behind the shared-factory closure.',
      );
    });

    test('identity is preserved across many sessions when the factory closes '
        'over a field', () async {
      // Stronger identity-only assertion to catch any future regression
      // that accidentally constructs fresh instances despite the closure
      // capturing `_shared`.
      final runtime = PluginRuntime(plugins: [SharedFactoryCounterPlugin()])
        ..init();
      final s1 = await runtime.createSession();
      final s2 = await runtime.createSession();
      final s3 = await runtime.createSession();

      final a = s1.context.resolve<CounterService>(_counterServiceId);
      final b = s2.context.resolve<CounterService>(_counterServiceId);
      final c = s3.context.resolve<CounterService>(_counterServiceId);

      expect(identical(a, b), isTrue);
      expect(identical(b, c), isTrue);
    });

    test('both plugin shapes compile and init without diagnostic', () {
      // Acceptance proof: both factory shapes route through the same
      // `registerSingleton(Factory<T>)` signature. The ONLY observable
      // discriminator is what the closure body references; the type
      // system sees `Factory<T>` in both cases.
      expect(
        () => PluginRuntime(plugins: [InlineFactoryCounterPlugin()])..init(),
        returnsNormally,
      );
      expect(
        () => PluginRuntime(plugins: [SharedFactoryCounterPlugin()])..init(),
        returnsNormally,
      );
    });

    test(
      'the factory runs EAGERLY at registration time (not lazily on resolve)',
      () async {
        // Ensures `registerSingleton` is genuinely the eager-singleton
        // variant. If this regresses to lazy semantics, the count below
        // would be zero before the first resolve.
        var factoryRuns = 0;
        final plugin = _CountingFactoryPlugin(() {
          factoryRuns += 1;
          return CounterService();
        });
        final runtime = PluginRuntime(plugins: [plugin])..init();
        final session = await runtime.createSession();

        expect(
          factoryRuns,
          1,
          reason:
              'Factory must run at registration time (one session = '
              'one factory call), not on first resolve.',
        );

        // Resolving does not run the factory again.
        session.context.resolve<CounterService>(_counterServiceId);
        expect(factoryRuns, 1);
      },
    );
  });
}

class _CountingFactoryPlugin extends SessionPlugin {
  _CountingFactoryPlugin(this.factory);

  final CounterService Function() factory;

  @override
  PluginId get pluginId => const PluginId('counting_factory_plugin');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<CounterService>(_counterServiceId, factory);
  }
}
