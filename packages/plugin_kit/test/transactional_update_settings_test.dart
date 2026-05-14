// TDD test for Codex blind-review Finding #1 (2026-05-13) / Sub-finding B:
// "updateSettings cross-session reconciliation is non-atomic."
//
// updateSettings reconciles global first, then each active session
// sequentially. If session N throws PluginLifecycleException mid-reconcile,
// sessions 1..N-1 are already on the new state, the stored
// _settingsValue is still on the old snapshot, and the runtime is in
// split-brain. With option (b) transactional rollback, a failure must
// walk back: revert every session and the global scope back to the old
// state, leave runtime.settings on the old snapshot, and rethrow.

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

/// A trigger plugin: starts disabled, gets enabled by the new settings.
/// Throws on its FIRST attach AFTER a global flag is set, simulating a
/// plugin whose attach fails on a specific session's reconcile (e.g. its
/// auth fails on that session's credentials).
class _SessionGatedThrower extends SessionPlugin {
  /// When non-null, this plugin throws on attach only when reconciling
  /// a session that has had this many createSession() calls before it.
  /// Test wires this so that the second session's reconcile throws.
  static int? throwOnNthSessionReconcile;
  static int reconcileCount = 0;
  static int attachCount = 0;

  static void reset() {
    throwOnNthSessionReconcile = null;
    reconcileCount = 0;
    attachCount = 0;
  }

  @override
  PluginId get pluginId => const PluginId('session_gated_thrower');

  @override
  List<FeatureFlag> get featureFlags => const [FeatureFlag.experimental];

  @override
  void attach(SessionPluginContext context) {
    attachCount++;
    final currentIndex = reconcileCount++;
    if (currentIndex == throwOnNthSessionReconcile) {
      throw StateError(
        'intentional attach throw on session reconcile index $currentIndex',
      );
    }
  }
}

/// A global plugin that's just a dependency target. Has no behavior;
/// its presence in [PluginRuntime.attachedGlobalPluginIds] is the only
/// thing other plugins care about.
class _GlobalDep extends GlobalPlugin {
  static bool throwFatalOnNextAttach = false;
  static void reset() {
    throwFatalOnNextAttach = false;
  }

  @override
  PluginId get pluginId => const PluginId('global_dep');

  @override
  void attach(GlobalPluginContext context) {
    if (throwFatalOnNextAttach) {
      throwFatalOnNextAttach = false;
      throw OutOfMemoryError();
    }
  }
}

/// A session plugin that depends on [_GlobalDep]. Used to test that
/// rollback restores cross-scope dependency state correctly: if the
/// global plugin's enablement is reverted AFTER session rollback,
/// the session's dep-cascade computation during rollback sees the wrong
/// global state and never re-enables this plugin.
class _SessionDependent extends SessionPlugin {
  static int detachCount = 0;
  static int throwOnNthDetach = -1;
  static void reset() {
    detachCount = 0;
    throwOnNthDetach = -1;
  }

  @override
  PluginId get pluginId => const PluginId('session_dependent');

  @override
  Set<PluginId> get dependencies => const {PluginId('global_dep')};

  @override
  Future<void> detach(SessionPluginContext context) async {
    detachCount++;
    if (throwOnNthDetach >= 0 && detachCount > throwOnNthDetach) {
      throw StateError(
        'intentional detach throw on session_dependent (detachCount=$detachCount)',
      );
    }
  }
}

void main() {
  group('updateSettings is transactional across sessions', () {
    setUp(() {
      _SessionGatedThrower.reset();
      _SessionDependent.reset();
      _GlobalDep.reset();
    });

    test(
      'mid-loop attach failure leaves all sessions on the old state',
      () async {
        // Three sessions with the same starter plugin set. Then call
        // updateSettings with a config that enables an experimental
        // plugin in every session; the plugin's attach throws on the
        // second session's reconcile (index 1 if 0-indexed). With
        // transactional semantics:
        //   - all three sessions stay on the OLD state (the plugin is NOT
        //     enabled there)
        //   - runtime.settings stays at the OLD snapshot
        //   - PluginLifecycleException is raised
        final runtime = PluginRuntime(plugins: [_SessionGatedThrower()])
          ..init();

        try {
          final session1 = await runtime.createSession();
          final session2 = await runtime.createSession();
          final session3 = await runtime.createSession();

          // Sanity: experimental plugin starts off (no opt-in), so attach
          // has not been called on any session yet.
          expect(_SessionGatedThrower.attachCount, equals(0));
          expect(
            session1.isPluginEnabled(_SessionGatedThrower().pluginId),
            isFalse,
          );
          expect(
            session2.isPluginEnabled(_SessionGatedThrower().pluginId),
            isFalse,
          );
          expect(
            session3.isPluginEnabled(_SessionGatedThrower().pluginId),
            isFalse,
          );

          // Arm: the second session's reconcile (index 1) throws.
          _SessionGatedThrower.throwOnNthSessionReconcile = 1;

          const newSettings = RuntimeSettings(
            plugins: {
              PluginId('session_gated_thrower'): PluginConfig(enabled: true),
            },
          );

          await expectLater(
            runtime.updateSettings(newSettings),
            throwsA(isA<PluginLifecycleException>()),
          );

          // Post-condition: transactional rollback (option b) must leave
          // every session on the OLD state, and the runtime's stored
          // settings snapshot must also be the old one. Anything else is
          // split-brain.
          expect(
            session1.isPluginEnabled(_SessionGatedThrower().pluginId),
            isFalse,
            reason:
                'Session 1 was reconciled to newSettings before session 2 '
                'threw. Transactional rollback must revert it back to the '
                'old state.',
          );
          expect(
            session3.isPluginEnabled(_SessionGatedThrower().pluginId),
            isFalse,
            reason:
                'Session 3 was never reconciled (the loop aborted before '
                'reaching it). It should remain on the old state.',
          );
          expect(
            runtime.settings.plugins,
            isEmpty,
            reason:
                'The stored RuntimeSettings snapshot must remain at the '
                'old value. Reporting the new value when sessions are '
                'still on the old one is the split-brain we are trying '
                'to eliminate.',
          );
        } finally {
          await runtime.dispose();
        }
      },
    );

    test(
      'rollback restores cross-scope dependency state in the right order',
      () async {
        // Setup: a session plugin S depends on a global plugin G. Both
        // start enabled. updateSettings disables G; sessions cascade-
        // disable S; on the SECOND session's detach we inject a throw to
        // force rollback. Without ordering global-first in the rollback,
        // session 1 is re-reconciled while _enabledGlobalPluginIds still
        // reflects post-new state (G missing), so dep cascade keeps S
        // disabled, never restoring oldSettings on session 1.
        final runtime = PluginRuntime(
          plugins: [_GlobalDep(), _SessionDependent()],
        )..init();

        try {
          final session1 = await runtime.createSession();
          await runtime.createSession();

          // Sanity: G and S are enabled in both sessions.
          expect(
            runtime.isPluginAttached(const PluginId('global_dep')),
            isTrue,
            reason: 'Sanity: global dep is attached at runtime scope.',
          );
          expect(
            session1.isPluginEnabled(const PluginId('session_dependent')),
            isTrue,
            reason:
                'Sanity: session_dependent is enabled in session 1 '
                'before the update.',
          );

          // Arm: the SECOND session_dependent.detach() throws. Session 1
          // reconciles successfully (detach 1, no throw), then session 2
          // tries to reconcile and throws on its detach (detach 2).
          _SessionDependent.throwOnNthDetach = 1;

          const newSettings = RuntimeSettings(
            plugins: {PluginId('global_dep'): PluginConfig(enabled: false)},
          );

          await expectLater(
            runtime.updateSettings(newSettings),
            throwsA(isA<PluginLifecycleException>()),
          );

          // Post-condition: session 1 must be back on oldSettings, which
          // had session_dependent ENABLED via cascade-from-global_dep.
          // The bug Codex flagged: rollback walks sessions BEFORE global,
          // so session 1's rollback sees _enabledGlobalPluginIds without
          // global_dep, dep cascade fails, and session_dependent stays
          // disabled even after global rollback completes.
          expect(
            session1.isPluginEnabled(const PluginId('session_dependent')),
            isTrue,
            reason:
                'After rollback, session 1 must be back on oldSettings: '
                'session_dependent depends on global_dep, both were '
                'enabled, the rollback must restore both. If this fails '
                'with isFalse, the rollback reverted sessions before '
                'restoring global_dep, so dep cascade kept the session '
                'plugin disabled during session-rollback.',
          );
          // Disarm so dispose's detach pass does not re-throw and shadow
          // the actual assertion outcome with a teardown-time error.
          _SessionDependent.throwOnNthDetach = -1;
        } finally {
          await runtime.dispose();
        }
      },
    );

    test(
      'rollback also reverts the in-flight session that threw mid-reconcile',
      () async {
        // Same setup as the rollback-order test. Session 1 reconciles
        // successfully; session 2 reconciles partway and throws.
        // _reconcilePluginsOnSettingsUpdate handles per-plugin failures
        // inside session 2, but any session-2 plugin that fully
        // transitioned BEFORE the throw is left on newSettings state.
        // The updateSettings catch must also revert that in-flight
        // session, not just the ones already in reconciledSessions.
        final runtime = PluginRuntime(
          plugins: [_GlobalDep(), _SessionDependent()],
        )..init();

        try {
          await runtime.createSession();
          final session2 = await runtime.createSession();

          // Sanity: session_dependent is enabled in session 2.
          expect(
            session2.isPluginEnabled(const PluginId('session_dependent')),
            isTrue,
          );

          // Arm: second detach throws (i.e. session 2's reconcile fails
          // mid-loop, after session 2 already markPluginDisabled'd S).
          _SessionDependent.throwOnNthDetach = 1;

          const newSettings = RuntimeSettings(
            plugins: {PluginId('global_dep'): PluginConfig(enabled: false)},
          );

          await expectLater(
            runtime.updateSettings(newSettings),
            throwsA(isA<PluginLifecycleException>()),
          );

          // Post-condition: session 2's state must also be reverted to
          // oldSettings, even though it never reached reconciledSessions.
          // _reconcilePluginsOnSettingsUpdate already called
          // session2.markPluginDisabled before the throw, so session 2
          // currently shows S disabled. Transactional rollback must
          // restore S to enabled.
          expect(
            session2.isPluginEnabled(const PluginId('session_dependent')),
            isTrue,
            reason:
                'The session that threw partway through its reconcile '
                'is just as partially-mutated as the sessions that '
                'completed successfully. Rollback must include it. '
                'Without this, the failing session is left in a half-'
                'applied state while every other session is on the old '
                'snapshot.',
          );
        } finally {
          // Disarm in finally so a RED expect() does not leak the arming
          // into runtime.dispose()'s detach pass.
          _SessionDependent.throwOnNthDetach = -1;
          await runtime.dispose();
        }
      },
    );

    test(
      'fatal error during rollback propagates and is not swallowed',
      () async {
        // Setup mirrors the rollback-order test: a primary failure
        // triggers rollback, but the global rollback re-attaches a global
        // plugin whose attach throws OutOfMemoryError. The rollback catch
        // must rethrow per `_isFatalError`, surfacing the fatal error to
        // the caller instead of logging-and-swallowing it. The original
        // PluginLifecycleException is superseded by the fatal error,
        // matching how every other lifecycle catch in this file behaves.
        final runtime = PluginRuntime(
          plugins: [_GlobalDep(), _SessionDependent()],
        )..init();

        try {
          await runtime.createSession();
          await runtime.createSession();

          // Arm the primary failure (session 2's detach throws), then arm
          // the rollback failure (global_dep.attach throws OOM when
          // re-attached during global rollback).
          _SessionDependent.throwOnNthDetach = 1;
          _GlobalDep.throwFatalOnNextAttach = true;

          const newSettings = RuntimeSettings(
            plugins: {PluginId('global_dep'): PluginConfig(enabled: false)},
          );

          await expectLater(
            runtime.updateSettings(newSettings),
            throwsA(isA<OutOfMemoryError>()),
            reason:
                'A fatal error raised inside the rollback path must NOT '
                'be caught and logged. Per `_isFatalError` convention '
                'used everywhere else in runtime.dart, fatal errors '
                'propagate, superseding any primary lifecycle exception.',
          );

          // Disarm before dispose so cleanup does not throw.
          _SessionDependent.throwOnNthDetach = -1;
          _GlobalDep.throwFatalOnNextAttach = false;
        } finally {
          await runtime.dispose();
        }
      },
    );
  });
}
