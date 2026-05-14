// TDD tests for Codex blind-review Sub-finding A (2026-05-13):
// "init() attach failures leave the runtime in an inconsistent state."
//
// When a plugin's attach() throws during init(), the existing code:
//   1. catches the error and adds it to attachErrors
//   2. KEEPS the plugin's id in _enabledGlobalPluginIds
//   3. KEEPS the plugin's services registered
//   4. throws PluginLifecycleException
//
// Net result: a caller that catches the exception and queries
// runtime.isPluginAttached(failedId) gets `true` even though attach
// threw. The settings-intent set and the actually-attached reality drift.
//
// The same shape applies to PluginSession.init().

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _ThrowingGlobal extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('throwing_global');

  @override
  void attach(GlobalPluginContext context) {
    throw StateError('intentional global attach crash');
  }
}

class _ThrowingRegisterService {
  const _ThrowingRegisterService();
}

class _ThrowingRegisterGlobal extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('throwing_register_global');

  @override
  void register(ScopedServiceRegistry registry) {
    // Register one service successfully, then throw to simulate a plugin
    // whose register pass partially registers before failing (e.g. a
    // configuration check halfway through).
    registry.registerSingleton<_ThrowingRegisterService>(
      const ServiceId('partial'),
      () => const _ThrowingRegisterService(),
    );
    throw StateError('intentional global register crash');
  }
}

class _OkRegisterService {
  const _OkRegisterService();
}

class _OkRegisterGlobal extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('ok_register_global');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_OkRegisterService>(
      const ServiceId('ok_service'),
      () => const _OkRegisterService(),
    );
  }
}

class _OkGlobal extends GlobalPlugin {
  static int attachCalls = 0;
  static void reset() {
    attachCalls = 0;
  }

  @override
  PluginId get pluginId => const PluginId('ok_global');

  @override
  void attach(GlobalPluginContext context) {
    attachCalls++;
  }
}

class _ThrowingSession extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('throwing_session');

  @override
  void attach(SessionPluginContext context) {
    throw StateError('intentional session attach crash');
  }
}

class _OkSession extends SessionPlugin {
  static int attachCalls = 0;
  static int detachCalls = 0;
  static void reset() {
    attachCalls = 0;
    detachCalls = 0;
  }

  @override
  PluginId get pluginId => const PluginId('ok_session');

  @override
  void attach(SessionPluginContext context) {
    attachCalls++;
  }

  @override
  Future<void> detach(SessionPluginContext context) async {
    detachCalls++;
  }
}

void main() {
  group('Global init() rollback on attach failure', () {
    setUp(() {
      _OkGlobal.reset();
    });

    test('failed plugin is not reported as attached after init throws', () {
      final runtime = PluginRuntime(plugins: [_ThrowingGlobal()]);

      expect(() => runtime.init(), throwsA(isA<PluginLifecycleException>()));

      expect(
        runtime.isPluginAttached(const PluginId('throwing_global')),
        isFalse,
        reason:
            'A plugin whose attach() threw during init must not appear as '
            'attached. Settings-intent and runtime-truth diverge here if '
            'the failed plugin id stays in _enabledGlobalPluginIds.',
      );
      expect(
        runtime.attachedGlobalPluginIds,
        isEmpty,
        reason:
            'attachedGlobalPluginIds must reflect only plugins whose '
            'attach() ran cleanly. A failed init leaves no surviving '
            'attached global plugins when there is only one plugin.',
      );
    });

    test(
      'register() failure rolls back the plugin and its partial registrations',
      () async {
        final runtime = PluginRuntime(plugins: [_ThrowingRegisterGlobal()]);

        expect(
          () => runtime.init(),
          throwsA(isA<PluginLifecycleException>()),
          reason:
              'A register() that throws must surface as a '
              'PluginLifecycleException, the same shape as an attach() '
              'failure, so callers do not see one path bubble raw and '
              'the other path aggregate.',
        );

        expect(
          runtime.isPluginAttached(const PluginId('throwing_register_global')),
          isFalse,
          reason:
              'A plugin whose register() threw must not appear attached. '
              'Without rollback, _enabledGlobalPluginIds still contains '
              'the plugin id, so attached state drifts from reality.',
        );
        expect(
          runtime.globalRegistry.listAllServiceIds(
            const PluginId('throwing_register_global'),
          ),
          isEmpty,
          reason:
              'A plugin whose register() partially registered services '
              'before throwing must have those services unregistered '
              'during rollback. Leaving them resolvable would let '
              'host code use services belonging to a plugin the '
              'runtime claims is not attached.',
        );
      },
    );

    test(
      'register() failure rolls back successful sibling plugins so dispose() '
      'is safe and attached state is honest',
      () async {
        // Setup: one global plugin registers successfully (and ends up
        // with services in the global registry), then a sibling plugin's
        // register throws. Before this rollback, init throws BEFORE
        // globalContext is initialized, leaving the successful sibling
        // in _enabledGlobalPluginIds and its services in the registry.
        // Two visible effects:
        //   1. isPluginAttached(sibling) reports true even though attach()
        //      never ran.
        //   2. dispose() iterates _enabledGlobalPluginIds and calls
        //      _runDetach(globalContext), which is `late` and
        //      uninitialized -> LateInitializationError.
        final runtime = PluginRuntime(
          plugins: [_OkRegisterGlobal(), _ThrowingRegisterGlobal()],
        );

        expect(() => runtime.init(), throwsA(isA<PluginLifecycleException>()));

        expect(
          runtime.isPluginAttached(const PluginId('ok_register_global')),
          isFalse,
          reason:
              'The sibling plugin was register()ed but never attach()ed '
              'because the init aborted before the attach loop. Reporting '
              'it as attached is a settings-intent / runtime-truth drift.',
        );
        expect(
          runtime.attachedGlobalPluginIds,
          isEmpty,
          reason:
              'After a failed init(), no global plugin should claim '
              'attachment. Either every plugin succeeded or the failure '
              'aborted before any attach() ran, in which case nothing is '
              'attached.',
        );

        await expectLater(
          runtime.dispose(),
          completes,
          reason:
              'dispose() must be safe to call after init() throws. With '
              'sibling plugins left in _enabledGlobalPluginIds, dispose '
              'tries _runDetach(globalContext) on a `late` field that '
              'was never assigned, surfacing as LateInitializationError.',
        );
      },
    );

    test('register() failure surfaces as PluginLifecycleException even when '
        'RuntimeSettings pins the failed plugin\'s services', () {
      // Setup: settings include a Pin targeting a service the failing
      // plugin would have registered. After register rollback, that
      // service is unregistered, and the existing pin-validation pass
      // (run AFTER register, BEFORE attach) sees a pin to an unknown
      // service id and throws StateError. Without a fix, the user sees
      // StateError as the surface error and never learns the actual
      // root cause (register threw). The init must throw
      // PluginLifecycleException so the user sees the real failure.
      final runtime = PluginRuntime(plugins: [_ThrowingRegisterGlobal()]);

      expect(
        () => runtime.init(
          settings: RuntimeSettings(
            services: {
              Pin('throwing_register_global', ['partial']):
                  const ServiceSettings(),
            },
          ),
        ),
        throwsA(isA<PluginLifecycleException>()),
        reason:
            'After register rollback unregisters the failed plugin\'s '
            'partial services, the pin-validation pass would throw '
            'StateError on its pin. The init flow must surface the '
            'register failure as PluginLifecycleException instead, so '
            'the user sees the root cause.',
      );
    });

    test(
      'sibling that attached stays attached, failed plugin is unwound',
      () async {
        final runtime = PluginRuntime(
          plugins: [_OkGlobal(), _ThrowingGlobal()],
        );

        expect(() => runtime.init(), throwsA(isA<PluginLifecycleException>()));

        expect(
          _OkGlobal.attachCalls,
          equals(1),
          reason: 'Sibling attached before throwing plugin did its job.',
        );
        // Per-plugin (option a) rollback: the failed plugin is removed from
        // the enabled set and its services unregistered, but successfully-
        // attached siblings remain attached and observable. The runtime is
        // usable in degraded state and accurately reports what is running.
        // See docs/superpowers/plans/2026-05-13-runtime-correctness-followups.md
        // for the option-b follow-up that pursues full atomic rollback at
        // the cost of an async init() API break.
        expect(
          runtime.attachedGlobalPluginIds,
          equals({const PluginId('ok_global')}),
          reason:
              'Failed plugin must not appear attached; sibling that did '
              'attach must continue to appear attached.',
        );
        expect(
          runtime.isPluginAttached(const PluginId('throwing_global')),
          isFalse,
          reason: 'Throwing plugin id is removed from the enabled set.',
        );
      },
    );
  });

  group('Session init() rollback on attach failure', () {
    setUp(() {
      _OkSession.reset();
    });

    test(
      'failed session plugin is not reported as enabled after createSession throws',
      () async {
        final runtime = PluginRuntime(plugins: [_ThrowingSession()])..init();

        try {
          await expectLater(
            runtime.createSession(),
            throwsA(isA<PluginLifecycleException>()),
          );

          // A failed session.init must not leak the failed plugin id into the
          // session's enabled set. createSession either returns a session
          // whose enabled set reflects reality, or throws and registers no
          // session at all.
          expect(
            runtime.attachedPluginIds.contains(
              const PluginId('throwing_session'),
            ),
            isFalse,
            reason:
                'A session plugin whose attach threw must not show up in '
                'attachedPluginIds. Session-level enabled sets must equal '
                'attached reality.',
          );
        } finally {
          await runtime.dispose();
        }
      },
    );

    test(
      'sibling session plugin that attached successfully is rolled back',
      () async {
        final runtime = PluginRuntime(
          plugins: [_OkSession(), _ThrowingSession()],
        )..init();

        try {
          await expectLater(
            runtime.createSession(),
            throwsA(isA<PluginLifecycleException>()),
          );

          expect(
            _OkSession.attachCalls,
            equals(1),
            reason: 'Sibling attached before throwing plugin did its job.',
          );
          expect(
            _OkSession.detachCalls,
            equals(1),
            reason:
                'On session-init failure, the runtime must unwind siblings '
                'so the caller is not left with a session that partially '
                'attached and silently survived.',
          );
        } finally {
          await runtime.dispose();
        }
      },
    );
  });
}
