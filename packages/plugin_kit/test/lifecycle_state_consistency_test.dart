// Verifies that runtime state queries match reality after a lifecycle
// failure. Three failure paths are tested:
//
//   1. Session enable: register or attach throws during settings
//      reconciliation. The plugin must NOT appear in
//      session.enabledPluginIds.
//
//   2. Global enable: register or attach throws during global settings
//      update. The plugin must NOT appear in
//      runtime.attachedGlobalPluginIds.
//
//   3. createSession: session.init throws because a plugin's attach
//      throws. The half-attached session must NOT leak into
//      runtime.sessions.
//
// Before this fix, state was mutated BEFORE the lifecycle call (session
// enable path) or unconditionally AFTER it (global enable path) or the
// session was pushed into _sessions BEFORE init was awaited. In all
// three cases, a thrown PluginLifecycleException left the runtime's
// queries lying about which plugins actually ran.
import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _ThrowsOnSessionRegister extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('session_register_throw');

  @override
  void register(ScopedServiceRegistry registry) {
    throw StateError('register boom');
  }
}

class _ThrowsOnSessionAttach extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('session_attach_throw');

  @override
  void attach(SessionPluginContext context) {
    throw StateError('attach boom');
  }
}

class _ThrowsOnGlobalRegister extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('global_register_throw');

  @override
  void register(ScopedServiceRegistry registry) {
    throw StateError('global register boom');
  }
}

class _ThrowsOnGlobalAttach extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('global_attach_throw');

  @override
  void attach(GlobalPluginContext context) {
    throw StateError('global attach boom');
  }
}

void main() {
  group('session enable on failure', () {
    test(
      'session-plugin register throw leaves session.isPluginEnabled false',
      () async {
        final runtime = PluginRuntime(plugins: [_ThrowsOnSessionRegister()])
          ..init(defaultEnabledPluginIds: const {});
        final session = await runtime.createSession();

        await expectLater(
          () => runtime.updateSessionSettings(
            session,
            newSettings: const RuntimeSettings(
              plugins: {
                PluginId('session_register_throw'): PluginConfig(enabled: true),
              },
            ),
          ),
          throwsA(isA<PluginLifecycleException>()),
        );

        expect(
          session.isPluginEnabled(const PluginId('session_register_throw')),
          isFalse,
          reason:
              'after a failed register, the plugin must not appear enabled '
              'in the session',
        );

        await runtime.dispose();
      },
    );

    test(
      'session-plugin attach throw leaves session.isPluginEnabled false',
      () async {
        final runtime = PluginRuntime(plugins: [_ThrowsOnSessionAttach()])
          ..init(defaultEnabledPluginIds: const {});
        final session = await runtime.createSession();

        await expectLater(
          () => runtime.updateSessionSettings(
            session,
            newSettings: const RuntimeSettings(
              plugins: {
                PluginId('session_attach_throw'): PluginConfig(enabled: true),
              },
            ),
          ),
          throwsA(isA<PluginLifecycleException>()),
        );

        expect(
          session.isPluginEnabled(const PluginId('session_attach_throw')),
          isFalse,
          reason:
              'after a failed attach, the plugin must not appear enabled '
              'in the session',
        );

        await runtime.dispose();
      },
    );
  });

  group('global enable on failure', () {
    test(
      'global-plugin register throw leaves attachedGlobalPluginIds clean',
      () async {
        final runtime = PluginRuntime(plugins: [_ThrowsOnGlobalRegister()])
          ..init(defaultEnabledPluginIds: const {});

        await expectLater(
          () => runtime.updateSettings(
            const RuntimeSettings(
              plugins: {
                PluginId('global_register_throw'): PluginConfig(enabled: true),
              },
            ),
          ),
          throwsA(isA<PluginLifecycleException>()),
        );

        expect(
          runtime.attachedGlobalPluginIds.contains(
            const PluginId('global_register_throw'),
          ),
          isFalse,
          reason: 'register failed; attached set must not contain the plugin',
        );
        expect(
          runtime.isPluginAttached(const PluginId('global_register_throw')),
          isFalse,
        );

        await runtime.dispose();
      },
    );

    test(
      'global-plugin attach throw leaves attachedGlobalPluginIds clean',
      () async {
        final runtime = PluginRuntime(plugins: [_ThrowsOnGlobalAttach()])
          ..init(defaultEnabledPluginIds: const {});

        await expectLater(
          () => runtime.updateSettings(
            const RuntimeSettings(
              plugins: {
                PluginId('global_attach_throw'): PluginConfig(enabled: true),
              },
            ),
          ),
          throwsA(isA<PluginLifecycleException>()),
        );

        expect(
          runtime.attachedGlobalPluginIds.contains(
            const PluginId('global_attach_throw'),
          ),
          isFalse,
          reason: 'attach failed; attached set must not contain the plugin',
        );

        await runtime.dispose();
      },
    );
  });

  group('createSession on failure', () {
    test(
      'a session whose init throws is not retained in runtime.sessions',
      () async {
        final runtime = PluginRuntime(plugins: [_ThrowsOnSessionAttach()])
          ..init();

        await expectLater(
          () => runtime.createSession(),
          throwsA(isA<PluginLifecycleException>()),
        );

        expect(
          runtime.sessions,
          isEmpty,
          reason: 'failed session must not leak into runtime.sessions',
        );

        await runtime.dispose();
      },
    );
  });
}
