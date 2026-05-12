// Verifies that `SessionBroadcast.emit` (the `List<PluginSession>`
// extension global plugins use to fan an event out across sessions)
// dispatches to every session in PARALLEL rather than awaiting each
// session's full handler chain before starting the next one.
//
// Sequential dispatch (the original behavior) blocks a slow handler in
// session N from delaying session N+1's dispatch start. With parallel
// dispatch via Future.wait, all sessions' handlers start as soon as
// the cascade runs the synchronous prefix of each handler, and the
// extension completes when every session has finished.
//
// Deterministic test design: each session's handler hits a Completer to
// signal "I started," then awaits another Completer to control when it
// finishes. No wall-clock waits or timeouts.
import 'dart:async';

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _Ping {
  const _Ping();
}

void main() {
  test(
    'SessionBroadcast.emit dispatches to all sessions in parallel',
    () async {
      // Two sessions, each with a handler that blocks on its own
      // Completer. If dispatch is sequential, session2's handler is
      // never reached until session1's handler resolves. If parallel,
      // both handlers begin executing before either completes.
      final runtime = PluginRuntime(plugins: [_MarkerPlugin()])..init();
      final session1 = await runtime.createSession();
      final session2 = await runtime.createSession();

      final s1Started = Completer<void>();
      final s2Started = Completer<void>();
      final s1Done = Completer<void>();
      final s2Done = Completer<void>();

      session1.bus.on<_Ping>((env) async {
        s1Started.complete();
        await s1Done.future;
      });
      session2.bus.on<_Ping>((env) async {
        s2Started.complete();
        await s2Done.future;
      });

      // Fire the broadcast but do NOT await. Both handlers should kick
      // off concurrently.
      final broadcast =
          [session1, session2].emit<_Ping>(const _Ping());

      // Drain microtasks so handlers reach their first `await`.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Under sequential dispatch: only s1 has started.
      // Under parallel dispatch: both have started.
      expect(
        s1Started.isCompleted,
        isTrue,
        reason: 'session1 handler should have started',
      );
      expect(
        s2Started.isCompleted,
        isTrue,
        reason: 'session2 handler should have started in parallel with '
            'session1 (this fails with sequential dispatch)',
      );

      // Release both handlers and await the broadcast.
      s1Done.complete();
      s2Done.complete();
      await broadcast;

      await runtime.dispose();
    },
  );

  test(
    'SessionBroadcast.emit awaits every session before resolving',
    () async {
      // Parallel dispatch must still wait for all handlers to settle
      // before the returned Future completes. A naive Future-and-forget
      // refactor would break this invariant.
      final runtime = PluginRuntime(plugins: [_MarkerPlugin()])..init();
      final session1 = await runtime.createSession();
      final session2 = await runtime.createSession();

      var s1Finished = false;
      var s2Finished = false;
      final s1Gate = Completer<void>();
      final s2Gate = Completer<void>();

      session1.bus.on<_Ping>((env) async {
        await s1Gate.future;
        s1Finished = true;
      });
      session2.bus.on<_Ping>((env) async {
        await s2Gate.future;
        s2Finished = true;
      });

      final broadcast =
          [session1, session2].emit<_Ping>(const _Ping());

      // Release after a delay; both should finish before broadcast does.
      Future<void>.delayed(Duration.zero, () {
        s1Gate.complete();
        s2Gate.complete();
      });

      await broadcast;
      expect(s1Finished, isTrue);
      expect(s2Finished, isTrue);

      await runtime.dispose();
    },
  );

  test(
    'SessionBroadcast.emit propagates the first error and still waits for '
    'other sessions to settle',
    () async {
      // Mirrors Future.wait's behavior: the first thrown error surfaces
      // on the broadcast Future, but the other sessions are not
      // abandoned mid-dispatch. This pins the error-handling shape so a
      // future refactor doesn't silently drop errors or strand
      // sessions.
      final runtime = PluginRuntime(plugins: [_MarkerPlugin()])..init();
      final session1 = await runtime.createSession();
      final session2 = await runtime.createSession();

      var s2Finished = false;
      session1.bus.on<_Ping>((env) async {
        throw StateError('session1 boom');
      });
      session2.bus.on<_Ping>((env) async {
        await Future<void>.delayed(Duration.zero);
        s2Finished = true;
      });

      await expectLater(
        () => [session1, session2].emit<_Ping>(const _Ping()),
        throwsA(isA<StateError>()),
      );
      // session2's handler should have run to completion even though
      // session1's threw. (Future.wait with eagerError: false ensures
      // this; the default eagerError: true would short-circuit. Pin the
      // intended shape here.)
      expect(s2Finished, isTrue);

      await runtime.dispose();
    },
  );
}

class _MarkerPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('marker');
}
