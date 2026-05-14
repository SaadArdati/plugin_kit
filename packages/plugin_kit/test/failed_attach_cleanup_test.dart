// On a failed attach, the registry was being cleaned up (services
// unregistered, plugin not marked enabled) but the stateful services'
// partial-attach state was being stranded:
//
//   - StatefulPluginServices that had `_bindContext` called but whose
//     subsequent lifecycle threw still had `hasContext == true`.
//   - Subscriptions / bindings registered during the successful
//     prefix of attach were still live on the bus.
//
// `_runAttach` binds every service's context before attempting any
// attach, then calls each service.attach() in a try/catch, then
// plugin.attach() in a try/catch, then throws an aggregate. So even
// when a service registered a handler successfully before throwing,
// that handler remains attached against a "rolled back" plugin.
//
// Fix: on enable failure (global, session, and createSession paths),
// run `_runDetach` to unwind partial state before unregistering the
// plugin's services. Detach failures during the cleanup pass are
// swallowed: the original attach error is what the caller cares about.
import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _MarkerEvent {
  const _MarkerEvent();
}

/// Module-level counter incremented by `_SubscribingServiceBeforeFailure`'s
/// handler. Reset before each test so we can detect leaked subscriptions.
int _markerHandlerCount = 0;

/// Service whose `attach()` succeeds AND subscribes to an event before
/// the OWNING PLUGIN'S `attach()` later throws. Used to prove that
/// failed-attach cleanup detaches the service that already succeeded:
/// a stranded subscription would still fire when the corresponding bus
/// emits, bumping the module-level counter.
class _SubscribingServiceBeforeFailure extends StatefulPluginService {
  @override
  void attach() {
    on<_MarkerEvent>((env) {
      _markerHandlerCount += 1;
    });
  }
}

class _PluginThatAttachesAndThenThrows extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('attach_throws_after_service');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_SubscribingServiceBeforeFailure>(
      const ServiceId('svc'),
      () => _SubscribingServiceBeforeFailure(),
    );
  }

  @override
  void attach(SessionPluginContext context) {
    // The owning service.attach() has already run by the time this
    // hook fires (services are processed before the plugin's own
    // attach in _runAttach). Throwing here leaves the service's
    // attach-time subscription live on the bus.
    throw StateError('plugin.attach() boom');
  }
}

void main() {
  setUp(() => _markerHandlerCount = 0);

  group('failed-attach cleanup unwinds partial state', () {
    test(
      'session enable: after plugin.attach() throws, the service\'s '
      'attach-time subscription is cancelled (no longer fires on emit)',
      () async {
        final plugin = _PluginThatAttachesAndThenThrows();
        // Start with the plugin disabled so the failure surfaces via the
        // off->on transition driven by updateSessionSettings, not on the
        // initial createSession.
        final runtime = PluginRuntime(plugins: [plugin])
          ..init(
            settings: const RuntimeSettings(
              plugins: {
                PluginId('attach_throws_after_service'): PluginConfig(
                  enabled: false,
                ),
              },
            ),
          );
        final session = await runtime.createSession();

        // Trigger the failure path via settings reconciliation.
        await expectLater(
          () => runtime.updateSessionSettings(
            session,
            newSettings: const RuntimeSettings(
              plugins: {
                PluginId('attach_throws_after_service'): PluginConfig(
                  enabled: true,
                ),
              },
            ),
          ),
          throwsA(isA<PluginLifecycleException>()),
        );

        // The service's `attach()` ran successfully and registered an
        // on<_MarkerEvent>(...) handler before plugin.attach() threw.
        // Without cleanup, that handler is still wired to the session
        // bus: emit fires it and the module counter increments.
        await session.bus.emit<_MarkerEvent>(event: const _MarkerEvent());
        expect(
          _markerHandlerCount,
          0,
          reason:
              'attach-time subscription must be cancelled during '
              'failed-attach cleanup; firing on a "rolled back" plugin '
              'is the leak this test pins',
        );

        // The state-consistency invariants from #11b still hold.
        expect(session.isPluginEnabled(plugin.pluginId), isFalse);
        expect(
          () => session.resolve<_SubscribingServiceBeforeFailure>(
            const ServiceId('svc'),
          ),
          throwsA(isA<StateError>()),
        );

        await runtime.dispose();
      },
    );

    test('createSession: after init() throws, the service\'s attach-time '
        'subscription on the failed session\'s bus is cancelled', () async {
      // To cleanly inspect the failed session's bus after the throw,
      // capture a reference to it during plugin.attach. The test
      // emits on that bus and asserts the counter stays at zero.
      final plugin = _CapturingPluginThatThrows();
      final runtime = PluginRuntime(plugins: [plugin])..init();

      await expectLater(
        () => runtime.createSession(),
        throwsA(isA<PluginLifecycleException>()),
      );

      final capturedBus = plugin.capturedBus;
      expect(
        capturedBus,
        isNotNull,
        reason:
            'plugin.attach should have captured the session bus '
            'before throwing',
      );

      // The orphan session's bus is disposed during cleanup so any
      // observer still holding a reference cannot drive it further.
      // Attempting to emit on it throws StateError.
      expect(
        capturedBus!.isDisposed,
        isTrue,
        reason:
            'orphan session bus must be disposed on createSession '
            'failure',
      );

      // And the attach-time subscription was cancelled before the bus
      // was disposed, so the counter stayed at zero throughout
      // cleanup (no late-firing handler).
      expect(
        _markerHandlerCount,
        0,
        reason:
            'failed createSession must cancel attach-time '
            'subscriptions during cleanup',
      );

      expect(runtime.sessions, isEmpty);
      await runtime.dispose();
    });
  });
}

class _CapturingPluginThatThrows extends SessionPlugin {
  EventBus? capturedBus;

  @override
  PluginId get pluginId => const PluginId('capturing_attach_throws');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_SubscribingServiceBeforeFailure>(
      const ServiceId('svc'),
      () => _SubscribingServiceBeforeFailure(),
    );
  }

  @override
  void attach(SessionPluginContext context) {
    capturedBus = context.bus;
    throw StateError('plugin.attach() boom');
  }
}
