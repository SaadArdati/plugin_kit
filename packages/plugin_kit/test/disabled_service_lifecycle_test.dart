// TDD red test for Codex blind-review Finding #5 (2026-05-13):
// "Disabled services may still receive `attach` calls."
//
// Codex's claim: a service registered with `enabled: false` in
// RuntimeSettings.services is correctly hidden from resolve(), but the
// runtime still calls attach() on it during plugin lifecycle. The
// effect would be: a "disabled" service still wires subscriptions,
// opens connections, allocates resources — just nobody can resolve it.
//
// Seven tests below cover the original Codex finding plus the edge cases
// raised in the Opus review: start-disabled, mid-session disable, mid-
// session re-enable (with and without an attach() that throws), plugin-
// AND-service-both-disabled, wildcard disable, and resolve/maybeResolve
// shape on a disabled slot. They GREEN-expect what the runtime should do;
// failures point to drift in the disabled-service lifecycle or the
// service-level diff inside _updateSessionSettingsInternal.

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _SneakyService extends SessionStatefulPluginService {
  static int attachCalls = 0;
  static int detachCalls = 0;
  static bool throwOnAttach = false;

  static void reset() {
    attachCalls = 0;
    detachCalls = 0;
    throwOnAttach = false;
  }

  @override
  void attach() {
    attachCalls++;
    if (throwOnAttach) {
      throw StateError('intentional attach throw');
    }
  }

  @override
  Future<void> detach() async {
    detachCalls++;
  }
}

class _SneakyPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('sneaky');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_SneakyService>(
      const ServiceId('sneaky'),
      () => _SneakyService(),
    );
  }
}

void main() {
  group('Disabled services do not run lifecycle side effects', () {
    setUp(_SneakyService.reset);

    test(
      'service with enabled:false at session start does not run attach()',
      () async {
        final runtime = PluginRuntime(plugins: [_SneakyPlugin()])..init();

        try {
          await runtime.createSession(
            settings: RuntimeSettings(
              services: {
                Pin('sneaky', ['sneaky']): const ServiceSettings(
                  enabled: false,
                ),
              },
            ),
          );

          // GREEN expectation: disabled service should not be attached.
          // If this fails (attachCalls == 1), Codex Finding #5 is confirmed.
          expect(
            _SneakyService.attachCalls,
            equals(0),
            reason:
                'A service with enabled:false should not have attach() '
                'called. Failure here confirms Codex Finding #5 (2026-05-13): '
                'lifecycle attach runs for services that are hidden from '
                'resolve(). The fix likely lives in '
                'service_registry.dart\'s getPluginServices.',
          );
        } finally {
          await runtime.dispose();
        }
      },
    );

    test(
      'flipping a service to enabled:false mid-session runs detach()',
      () async {
        final runtime = PluginRuntime(plugins: [_SneakyPlugin()])..init();

        try {
          await runtime.createSession();

          // Sanity: enabled at start, so attach() should have run once.
          expect(
            _SneakyService.attachCalls,
            equals(1),
            reason:
                'Sanity check: enabled service should have attach() called '
                'on session create.',
          );
          expect(_SneakyService.detachCalls, equals(0));

          await runtime.updateSettings(
            RuntimeSettings(
              services: {
                Pin('sneaky', ['sneaky']): const ServiceSettings(
                  enabled: false,
                ),
              },
            ),
          );

          // GREEN expectation: disable should run detach() symmetrically.
          // If this fails (detachCalls == 0), the disable path is leaking
          // lifecycle state: the service remains attached, its
          // subscriptions remain live, its resources remain held.
          expect(
            _SneakyService.detachCalls,
            equals(1),
            reason:
                'Disabling a service mid-session should run detach() '
                'symmetrically with the disable. Failure here means '
                'disabled services remain attached and continue to receive '
                'events / hold resources.',
          );
        } finally {
          await runtime.dispose();
        }
      },
    );

    test(
      'flipping a service from disabled back to enabled mid-session runs attach()',
      () async {
        final runtime = PluginRuntime(plugins: [_SneakyPlugin()])..init();

        try {
          await runtime.createSession(
            settings: RuntimeSettings(
              services: {
                Pin('sneaky', ['sneaky']): const ServiceSettings(
                  enabled: false,
                ),
              },
            ),
          );

          expect(
            _SneakyService.attachCalls,
            equals(0),
            reason: 'Sanity check: disabled at start, so attach has not run.',
          );

          await runtime.updateSettings(
            RuntimeSettings(
              services: {
                Pin('sneaky', ['sneaky']): const ServiceSettings(),
              },
            ),
          );

          expect(
            _SneakyService.attachCalls,
            equals(1),
            reason:
                'Re-enabling a service mid-session should run attach() '
                'symmetrically with the enable. Failure here means re-enable '
                'leaves the service in the registry but never wires it up.',
          );
        } finally {
          await runtime.dispose();
        }
      },
    );

    test(
      'plugin disabled AND service disabled is a no-op (no exception, no attach)',
      () async {
        final runtime = PluginRuntime(plugins: [_SneakyPlugin()])
          ..init(unknownReferencePolicy: UnknownReferencePolicy.logAndSkip);

        try {
          await runtime.createSession(
            settings: RuntimeSettings(
              plugins: const {PluginId('sneaky'): PluginConfig(enabled: false)},
              services: {
                Pin('sneaky', ['sneaky']): const ServiceSettings(
                  enabled: false,
                ),
              },
            ),
          );

          expect(
            _SneakyService.attachCalls,
            equals(0),
            reason:
                'Plugin disabled means register never ran; nothing to attach.',
          );
          expect(
            _SneakyService.detachCalls,
            equals(0),
            reason: 'Nothing was attached, nothing to detach.',
          );
        } finally {
          await runtime.dispose();
        }
      },
    );

    test(
      'wildcard disable suppresses attach() for the winning service',
      () async {
        final runtime = PluginRuntime(plugins: [_SneakyPlugin()])..init();

        try {
          await runtime.createSession(
            settings: RuntimeSettings(
              services: {
                Pin.wildcard(['sneaky']): const ServiceSettings(enabled: false),
              },
            ),
          );

          expect(
            _SneakyService.attachCalls,
            equals(0),
            reason:
                'A wildcard override that disables the slot should hide '
                'the winning service from lifecycle, regardless of which '
                'plugin wins resolution.',
          );
        } finally {
          await runtime.dispose();
        }
      },
    );

    test(
      're-enable attach() failure surfaces the error AND restores session state',
      () async {
        final runtime = PluginRuntime(plugins: [_SneakyPlugin()])..init();

        try {
          final session = await runtime.createSession(
            settings: RuntimeSettings(
              services: {
                Pin('sneaky', ['sneaky']): const ServiceSettings(
                  enabled: false,
                ),
              },
            ),
          );

          // Arm: the upcoming re-enable attach() will throw.
          _SneakyService.throwOnAttach = true;
          final attachCallsBefore = _SneakyService.attachCalls;

          await expectLater(
            runtime.updateSettings(
              RuntimeSettings(
                services: {
                  Pin('sneaky', ['sneaky']): const ServiceSettings(),
                },
              ),
            ),
            throwsA(isA<PluginLifecycleException>()),
            reason:
                'A throwing attach() during the re-enable diff must surface '
                'as a PluginLifecycleException, not be silently swallowed.',
          );

          expect(
            _SneakyService.attachCalls,
            greaterThan(attachCallsBefore),
            reason:
                'The runtime attempted attach() during the diff before the '
                'throw; the failed attach attempt itself is observable.',
          );

          // updateSettings rolls back to the session's pre-update state,
          // which had the `sneaky` service explicitly disabled via per-
          // session override. Resolving therefore throws, consistent with
          // the documented LocalPluginOverride.disable contract.
          expect(
            () => session.resolve<_SneakyService>(
              const ServiceId('sneaky'),
            ),
            throwsA(isA<StateError>()),
            reason:
                'After rollback the session is restored to its pre-update '
                'state: the `sneaky` override (enabled: false) is back in '
                'place, so resolve throws as documented for disabled slots.',
          );
        } finally {
          await runtime.dispose();
        }
      },
    );

    test(
      'disabled service is unresolvable: resolve() throws, maybeResolve() returns null',
      () async {
        final runtime = PluginRuntime(plugins: [_SneakyPlugin()])..init();

        try {
          final session = await runtime.createSession(
            settings: RuntimeSettings(
              services: {
                Pin('sneaky', ['sneaky']): const ServiceSettings(
                  enabled: false,
                ),
              },
            ),
          );

          expect(
            () => session.resolve<_SneakyService>(const ServiceId('sneaky')),
            throwsA(isA<StateError>()),
            reason:
                'resolve() on a disabled service should surface the '
                'standard not-found shape rather than returning a hidden '
                'instance.',
          );
          expect(
            session.maybeResolve<_SneakyService>(const ServiceId('sneaky')),
            isNull,
            reason: 'maybeResolve() on a disabled service should return null.',
          );
        } finally {
          await runtime.dispose();
        }
      },
    );
  });
}
