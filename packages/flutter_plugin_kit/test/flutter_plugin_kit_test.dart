import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_plugin_kit/flutter_plugin_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

class _Ping {
  const _Ping(this.value);
  final int value;
}

class _Pong {
  const _Pong();
}

class _NoopPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('flutter_plugin_kit.test.noop');

  @override
  void register(ScopedServiceRegistry registry) {}
}

class _ThrowOnDetachService extends SessionStatefulPluginService {
  @override
  void attach() {}

  @override
  Future<void> detach() async {
    throw StateError('intentional detach failure');
  }
}

class _ThrowOnDetachPlugin extends SessionPlugin {
  @override
  PluginId get pluginId =>
      const PluginId('flutter_plugin_kit.test.throw_on_detach');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_ThrowOnDetachService>(
      const ServiceId('throw_on_detach_service'),
      () => _ThrowOnDetachService(),
    );
  }
}

PluginRuntime _newThrowingRuntime() {
  final runtime = PluginRuntime(plugins: [_ThrowOnDetachPlugin()]);
  runtime.init();
  return runtime;
}

class _ThrowOnDetachWithStateError extends SessionStatefulPluginService {
  @override
  void attach() {}

  @override
  Future<void> detach() async {
    throw StateError('intentional non-PluginLifecycleException failure');
  }
}

class _ThrowStateErrorPlugin extends SessionPlugin {
  @override
  PluginId get pluginId =>
      const PluginId('flutter_plugin_kit.test.throw_state_error');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_ThrowOnDetachWithStateError>(
      const ServiceId('throw_state_error_service'),
      () => _ThrowOnDetachWithStateError(),
    );
  }
}

PluginRuntime _newStateErrorRuntime() {
  final runtime = PluginRuntime(plugins: [_ThrowStateErrorPlugin()]);
  runtime.init();
  return runtime;
}

PluginRuntime _newRuntime() {
  final runtime = PluginRuntime(plugins: [_NoopPlugin()]);
  runtime.init();
  return runtime;
}

class _PendingRuntime implements PluginRuntime {
  _PendingRuntime(this._real);

  final PluginRuntime _real;
  Completer<PluginSession>? _pending;

  /// Hold the next [createSession] call pending. Resolve it manually via
  /// [resolvePending].
  void holdNextCreate() {
    _pending = Completer<PluginSession>();
  }

  Future<void> resolvePending() async {
    final completer = _pending!;
    _pending = null;
    completer.complete(await _real.createSession());
  }

  @override
  Future<PluginSession> createSession({
    RuntimeSettings? settings,
    dynamic contextFactory,
  }) async {
    final pending = _pending;
    if (pending != null) {
      return pending.future;
    }
    return _real.createSession();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Function.apply(_real.noSuchMethod, [invocation]);
}

class _ThrowingRuntime implements PluginRuntime {
  _ThrowingRuntime(this._real, this.error);

  final PluginRuntime _real;
  final Object error;
  bool _throwed = false;

  @override
  Future<PluginSession> createSession({
    RuntimeSettings? settings,
    dynamic contextFactory,
  }) async {
    if (!_throwed) {
      _throwed = true;
      throw error;
    }
    return _real.createSession();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Function.apply(_real.noSuchMethod, [invocation]);
}

void main() {
  group('PluginRuntimeScope', () {
    testWidgets('exposes an externally-owned runtime via .of', (tester) async {
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);

      PluginRuntime? captured;
      await tester.pumpWidget(
        PluginRuntimeScope.value(
          runtime: runtime,
          child: Builder(
            builder: (context) {
              captured = PluginRuntimeScope.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(captured, same(runtime));
    });

    testWidgets('auto-creates and disposes a runtime from plugins', (
      tester,
    ) async {
      PluginRuntime? captured;
      await tester.pumpWidget(
        PluginRuntimeScope(
          plugins: [_NoopPlugin()],
          child: Builder(
            builder: (context) {
              captured = PluginRuntimeScope.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(captured, isNotNull);

      // Tear down by replacing the widget. The owned runtime should be
      // disposed without an error.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });

    testWidgets('maybeOf returns null without a scope', (tester) async {
      PluginRuntime? captured = _newRuntime();
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            captured = PluginRuntimeScope.maybeOf(context);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(captured, isNull);
    });
  });

  group('PluginSessionScope', () {
    testWidgets(
      'asserts in debug when both session: and runtime: are supplied',
      (tester) async {
        // Regression C1: the docstring says "at most one of session or
        // runtime"; the constructor now enforces it via assert. A misuse
        // that supplies both would previously silently prefer session,
        // which is rarely what the caller intends.
        final runtime = _newRuntime();
        addTearDown(runtime.dispose);
        final session = await runtime.createSession();
        addTearDown(session.dispose);

        expect(
          () => PluginSessionScope(
            session: session,
            runtime: runtime,
            child: const SizedBox.shrink(),
          ),
          throwsA(isA<AssertionError>()),
        );
      },
    );

    testWidgets('uses an explicit session without auto-creating', (
      tester,
    ) async {
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);
      final session = await runtime.createSession();
      addTearDown(session.dispose);

      PluginSession? captured;
      await tester.pumpWidget(
        PluginSessionScope(
          session: session,
          child: Builder(
            builder: (context) {
              captured = PluginSessionScope.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(captured, same(session));
    });

    testWidgets('auto-creates from explicit runtime and disposes session', (
      tester,
    ) async {
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            runtime: runtime,
            child: Builder(
              builder: (context) {
                final session = PluginSessionScope.maybeOf(context);
                return Text(session == null ? 'no-session' : 'has-session');
              },
            ),
          ),
        ),
      );

      // Initially the session future is pending; default loading shown.
      // Pump until the async createSession resolves.
      await tester.pumpAndSettle();

      expect(find.text('has-session'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });

    testWidgets('derives runtime from ambient PluginRuntimeScope', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginRuntimeScope(
            plugins: [_NoopPlugin()],
            child: PluginSessionScope(
              child: Builder(
                builder: (context) {
                  final session = PluginSessionScope.maybeOf(context);
                  return Text(session == null ? 'no-session' : 'has-session');
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('has-session'), findsOneWidget);
    });

    testWidgets('null → external swap disposes the auto-created session', (
      tester,
    ) async {
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);

      // Mount with widget.session: null so the scope auto-creates.
      late PluginSession autoCreated;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            runtime: runtime,
            child: Builder(
              builder: (context) {
                final session = PluginSessionScope.maybeOf(context);
                if (session != null) autoCreated = session;
                return Text(session == null ? 'no-session' : 'auto');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('auto'), findsOneWidget);
      expect(
        autoCreated.bus.isDisposed,
        isFalse,
        reason: 'auto-created session is live before the swap',
      );

      // Now swap to an external session.
      final external = await runtime.createSession();
      addTearDown(external.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            session: external,
            child: Builder(
              builder: (context) {
                final session = PluginSessionScope.maybeOf(context);
                return Text(
                  session == null
                      ? 'no-session'
                      : (identical(session, external) ? 'external' : 'auto'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('external'), findsOneWidget);

      // The auto-created session must have been disposed by the scope.
      // Post-dispose, its bus throws on any mutating call. Probing
      // isDisposed avoids materializing a thrown exception.
      expect(
        autoCreated.bus.isDisposed,
        isTrue,
        reason: 'scope-owned auto-created session must be disposed on swap',
      );

      // The external session must NOT have been disposed by the swap.
      // A regression that disposed both sessions during swap would still
      // satisfy the previous assertion alone; this guard catches it.
      expect(
        external.bus.isDisposed,
        isFalse,
        reason: 'externally-owned session must remain live across the swap',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });

    testWidgets('external → null swap kicks off auto-create', (tester) async {
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);

      final external = await runtime.createSession();
      addTearDown(external.dispose);

      // Mount with explicit external session.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            session: external,
            child: Builder(
              builder: (context) {
                final session = PluginSessionScope.maybeOf(context);
                return Text(
                  session == null
                      ? 'no-session'
                      : (identical(session, external) ? 'external' : 'auto'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('external'), findsOneWidget);

      // Swap to widget.session: null → scope must auto-create.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            runtime: runtime,
            child: Builder(
              builder: (context) {
                final session = PluginSessionScope.maybeOf(context);
                return Text(
                  session == null
                      ? 'no-session'
                      : (identical(session, external) ? 'external' : 'auto'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Must NOT be stuck on no-session, and must NOT still be 'external'.
      expect(find.text('auto'), findsOneWidget);
    });

    testWidgets('widget.runtime swap re-creates session in auto-create mode', (
      tester,
    ) async {
      final runtimeA = _newRuntime();
      addTearDown(runtimeA.dispose);
      final runtimeB = _newRuntime();
      addTearDown(runtimeB.dispose);

      Widget tree(PluginRuntime r) => Directionality(
        textDirection: TextDirection.ltr,
        child: PluginSessionScope(
          runtime: r,
          child: Builder(
            builder: (context) {
              final session = PluginSessionScope.maybeOf(context);
              return Text(session == null ? 'no-session' : 'session');
            },
          ),
        ),
      );

      await tester.pumpWidget(tree(runtimeA));
      await tester.pumpAndSettle();
      final session1 = PluginSessionScope.of(
        tester.element(find.text('session')),
      );
      expect(session1.bus.isDisposed, isFalse);

      // Swap the runtime. Scope must dispose its session-from-A and
      // create a new one from B.
      await tester.pumpWidget(tree(runtimeB));
      await tester.pumpAndSettle();
      final session2 = PluginSessionScope.of(
        tester.element(find.text('session')),
      );

      expect(
        identical(session1, session2),
        isFalse,
        reason: 'session must be re-created when widget.runtime swaps',
      );
      expect(
        session1.bus.isDisposed,
        isTrue,
        reason: 'scope-owned session-from-A must be disposed on swap',
      );
      expect(
        session2.bus.isDisposed,
        isFalse,
        reason: 'newly created session-from-B must be live',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'does not dispose owned session when promoted to widget.session',
      (tester) async {
        final runtime = _newRuntime();
        addTearDown(runtime.dispose);

        // Container widget that promotes the auto-created session to
        // widget.session on the second build. Demonstrates the user-side
        // pattern of "grab the auto-created session and pass it back."
        late PluginSession captured;

        // First mount: auto-create.
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: PluginSessionScope(
              runtime: runtime,
              child: Builder(
                builder: (context) {
                  captured = PluginSessionScope.of(context);
                  return const Text('mounted');
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Second mount: pass the captured session back as widget.session.
        // The scope should treat this as a no-op for disposal purposes;
        // the session must remain usable.
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: PluginSessionScope(
              session: captured,
              child: Builder(
                builder: (context) {
                  final s = PluginSessionScope.maybeOf(context);
                  return Text(identical(s, captured) ? 'same' : 'different');
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('same'), findsOneWidget);

        // Critically: the captured session must still be usable. If the
        // scope disposed it, attempting to emit would throw.
        await captured.emit(const _Ping(1));
        // (handler probe is not present here; the assertion is that emit
        // does not throw.)
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('in-flight createSession does not overwrite explicit session', (
      tester,
    ) async {
      final realRuntime = _newRuntime();
      addTearDown(realRuntime.dispose);
      final pendingRuntime = _PendingRuntime(realRuntime);
      pendingRuntime.holdNextCreate();

      // Mount with auto-create. The first createSession is now pending
      // forever (until we resolve it manually).
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            runtime: pendingRuntime,
            loading: (_) => const Text('loading'),
            child: Builder(
              builder: (context) {
                final session = PluginSessionScope.maybeOf(context);
                return Text(session == null ? 'no-session' : 'has-session');
              },
            ),
          ),
        ),
      );
      await tester.pump();
      // Confirm the scope is still in loading state; create is pending.
      expect(find.text('loading'), findsOneWidget);

      // Swap to an explicit session WHILE the first create is in flight.
      final external = await realRuntime.createSession();
      addTearDown(external.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            session: external,
            child: Builder(
              builder: (context) {
                final s = PluginSessionScope.maybeOf(context);
                return Text(
                  s == null
                      ? 'no-session'
                      : (identical(s, external) ? 'external' : 'auto'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('external'), findsOneWidget);

      // Now resolve the pending create. The stale future SHOULD see a
      // gen-counter mismatch and dispose its session without exposing it.
      await pendingRuntime.resolvePending();
      await tester.pumpAndSettle();
      expect(find.text('external'), findsOneWidget);
    });

    testWidgets('ambient runtime swap re-creates session in auto-create mode', (
      tester,
    ) async {
      final runtimeA = _newRuntime();
      addTearDown(runtimeA.dispose);
      final runtimeB = _newRuntime();
      addTearDown(runtimeB.dispose);

      // Tree shape: PluginRuntimeScope.value(runtime: ...) wraps a
      // PluginSessionScope with NO explicit runtime. The session scope
      // resolves its runtime from the ambient PluginRuntimeScope.
      Widget tree(PluginRuntime r) => Directionality(
        textDirection: TextDirection.ltr,
        child: PluginRuntimeScope.value(
          runtime: r,
          child: PluginSessionScope(
            child: Builder(
              builder: (context) {
                final session = PluginSessionScope.maybeOf(context);
                return Text(session == null ? 'no-session' : 'session');
              },
            ),
          ),
        ),
      );

      await tester.pumpWidget(tree(runtimeA));
      await tester.pumpAndSettle();
      final session1 = PluginSessionScope.of(
        tester.element(find.text('session')),
      );
      expect(session1.bus.isDisposed, isFalse);

      // Swap the AMBIENT runtime (the PluginRuntimeScope ancestor).
      // didChangeDependencies fires on the descendant PluginSessionScope.
      // Scope must dispose its session-from-A and re-create from B.
      await tester.pumpWidget(tree(runtimeB));
      await tester.pumpAndSettle();
      final session2 = PluginSessionScope.of(
        tester.element(find.text('session')),
      );

      expect(
        identical(session1, session2),
        isFalse,
        reason: 'session must be re-created when ambient runtime swaps',
      );
      expect(
        session1.bus.isDisposed,
        isTrue,
        reason: 'scope-owned session-from-A must be disposed on swap',
      );
      expect(
        session2.bus.isDisposed,
        isFalse,
        reason: 'newly created session-from-B must be live',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });

    testWidgets('error → external swap clears error and shows session', (
      tester,
    ) async {
      final realRuntime = _newRuntime();
      addTearDown(realRuntime.dispose);
      final throwing = _ThrowingRuntime(realRuntime, StateError('boom'));

      Object? capturedError;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            runtime: throwing,
            error: (context, e) {
              capturedError = e;
              return const Text('error');
            },
            child: Builder(
              builder: (context) {
                final s = PluginSessionScope.maybeOf(context);
                return Text(s == null ? 'no-session' : 'session');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('error'), findsOneWidget);
      expect(capturedError, isA<StateError>());

      // Swap to an explicit session; error UI must clear.
      final external = await realRuntime.createSession();
      addTearDown(external.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            session: external,
            error: (context, e) => const Text('error'),
            child: Builder(
              builder: (context) {
                final s = PluginSessionScope.maybeOf(context);
                return Text(s == null ? 'no-session' : 'session');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('session'), findsOneWidget);
      expect(find.text('error'), findsNothing);
    });

    testWidgets(
      'A → C transition: external session swapped for ambient runtime',
      (tester) async {
        final runtime = _newRuntime();
        addTearDown(runtime.dispose);
        final external = await runtime.createSession();
        addTearDown(external.dispose);

        Widget tree({required bool useExternal}) => Directionality(
          textDirection: TextDirection.ltr,
          child: PluginRuntimeScope.value(
            runtime: runtime,
            child: PluginSessionScope(
              session: useExternal ? external : null,
              child: Builder(
                builder: (context) {
                  final s = PluginSessionScope.maybeOf(context);
                  return Text(
                    s == null
                        ? 'no-session'
                        : (identical(s, external) ? 'external' : 'auto'),
                  );
                },
              ),
            ),
          ),
        );

        // Mode A: explicit session.
        await tester.pumpWidget(tree(useExternal: true));
        await tester.pumpAndSettle();
        expect(find.text('external'), findsOneWidget);

        // Swap to mode C: drop explicit session, fall back to ambient runtime.
        await tester.pumpWidget(tree(useExternal: false));
        await tester.pumpAndSettle();
        expect(find.text('auto'), findsOneWidget);
      },
    );

    testWidgets(
      'B → C transition: explicit runtime swapped for ambient runtime',
      (tester) async {
        final runtimeExplicit = _newRuntime();
        addTearDown(runtimeExplicit.dispose);
        final runtimeAmbient = _newRuntime();
        addTearDown(runtimeAmbient.dispose);

        Widget tree({required bool useExplicit}) => Directionality(
          textDirection: TextDirection.ltr,
          child: PluginRuntimeScope.value(
            runtime: runtimeAmbient,
            child: PluginSessionScope(
              runtime: useExplicit ? runtimeExplicit : null,
              child: Builder(
                builder: (context) {
                  final s = PluginSessionScope.maybeOf(context);
                  return Text(s == null ? 'no-session' : 'session');
                },
              ),
            ),
          ),
        );

        // Mode B: explicit runtime.
        await tester.pumpWidget(tree(useExplicit: true));
        await tester.pumpAndSettle();
        final session1 = PluginSessionScope.of(
          tester.element(find.text('session')),
        );

        // Swap to mode C: drop widget.runtime, fall back to ambient.
        await tester.pumpWidget(tree(useExplicit: false));
        await tester.pumpAndSettle();
        final session2 = PluginSessionScope.of(
          tester.element(find.text('session')),
        );

        // session must be re-created from the ambient runtime, not reused.
        expect(
          identical(session1, session2),
          isFalse,
          reason: 'B→C must re-create session from ambient runtime',
        );
      },
    );

    testWidgets('C → A transition: ambient session promoted to explicit', (
      tester,
    ) async {
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);
      final external = await runtime.createSession();
      addTearDown(external.dispose);

      Widget tree({required bool useExternal}) => Directionality(
        textDirection: TextDirection.ltr,
        child: PluginRuntimeScope.value(
          runtime: runtime,
          child: PluginSessionScope(
            session: useExternal ? external : null,
            child: Builder(
              builder: (context) {
                final s = PluginSessionScope.maybeOf(context);
                return Text(
                  s == null
                      ? 'no-session'
                      : (identical(s, external) ? 'external' : 'auto'),
                );
              },
            ),
          ),
        ),
      );

      // Mode C: ambient auto-create.
      await tester.pumpWidget(tree(useExternal: false));
      await tester.pumpAndSettle();
      expect(find.text('auto'), findsOneWidget);

      // Swap to mode A: supply explicit session.
      await tester.pumpWidget(tree(useExternal: true));
      await tester.pumpAndSettle();
      expect(find.text('external'), findsOneWidget);
    });

    testWidgets('C → B transition: ambient supplanted by explicit runtime', (
      tester,
    ) async {
      final runtimeAmbient = _newRuntime();
      addTearDown(runtimeAmbient.dispose);
      final runtimeExplicit = _newRuntime();
      addTearDown(runtimeExplicit.dispose);

      Widget tree({required bool useExplicit}) => Directionality(
        textDirection: TextDirection.ltr,
        child: PluginRuntimeScope.value(
          runtime: runtimeAmbient,
          child: PluginSessionScope(
            runtime: useExplicit ? runtimeExplicit : null,
            child: Builder(
              builder: (context) {
                final s = PluginSessionScope.maybeOf(context);
                return Text(s == null ? 'no-session' : 'session');
              },
            ),
          ),
        ),
      );

      // Mode C: ambient auto-create.
      await tester.pumpWidget(tree(useExplicit: false));
      await tester.pumpAndSettle();
      final session1 = PluginSessionScope.of(
        tester.element(find.text('session')),
      );

      // Swap to mode B: supply explicit runtime.
      await tester.pumpWidget(tree(useExplicit: true));
      await tester.pumpAndSettle();
      final session2 = PluginSessionScope.of(
        tester.element(find.text('session')),
      );

      expect(
        identical(session1, session2),
        isFalse,
        reason: 'C→B must re-create session from explicit runtime',
      );
    });

    testWidgets(
      'missing PluginRuntimeScope ancestor surfaces via error builder',
      (tester) async {
        Object? capturedError;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: PluginSessionScope(
              error: (context, e) {
                capturedError = e;
                return const Text('error');
              },
              child: const SizedBox.shrink(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('error'), findsOneWidget);
        expect(
          capturedError,
          isA<FlutterError>(),
          reason:
              'PluginRuntimeScope.of throws FlutterError when no '
              'ancestor exists; the scope must route this through the '
              'error builder, not let it escape as a zone error.',
        );
      },
    );

    testWidgets('reports session dispose errors via FlutterError', (
      tester,
    ) async {
      final runtime = _newThrowingRuntime();
      addTearDown(runtime.dispose);

      // Mount with auto-create; scope owns the session.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            runtime: runtime,
            child: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Unmount; this triggers _session.dispose() which will throw.
      await tester.pumpWidget(const SizedBox.shrink());
      // Drain any pending microtasks from the async dispose.
      await tester.pumpAndSettle();

      final error = tester.takeException();
      expect(
        error,
        isA<PluginLifecycleException>(),
        reason:
            'PluginSession.dispose error must be reported via '
            'FlutterError.reportError, not swallowed',
      );
    });

    testWidgets('reports the underlying error type from a non-PluginLifecycle '
        'dispose failure', (tester) async {
      final runtime = _newStateErrorRuntime();
      addTearDown(runtime.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            runtime: runtime,
            child: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Unmount → triggers dispose → triggers the StateError detach throw.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      final error = tester.takeException();

      // The runtime wraps any plugin-side throw from detach in a
      // PluginLifecycleException. The .catchError site catches Object, so
      // ANY error type still flows through to FlutterError.reportError,
      // but to prove the original cause survives the trip (and isn't
      // swallowed/replaced by an unrelated exception), assert that the
      // wrapped failure list carries the StateError this fixture threw.
      expect(error, isA<PluginLifecycleException>());
      final lifecycle = error as PluginLifecycleException;
      expect(lifecycle.failures, hasLength(1));
      final (_, cause, _) = lifecycle.failures.single;
      expect(
        cause,
        isA<StateError>(),
        reason: 'underlying cause must be the plugin-thrown StateError',
      );
      expect(
        (cause as StateError).message,
        contains('intentional non-PluginLifecycleException failure'),
      );
    });
  });

  group('disposeAndReport helper', () {
    testWidgets(
      'routes synchronous throws from the closure through FlutterError.reportError',
      (tester) async {
        // Regression A1: previously the helper invoked the closure outside
        // any try, so a throw before dispose returned a Future bypassed
        // .catchError and escaped into the calling zone. Future.sync()
        // catches sync throws and converts them to async errors.
        disposeAndReport(
          () => throw StateError('intentional sync throw before future'),
          contextDescription: 'unit test sync-throw escape',
        );
        await tester.pumpAndSettle();

        final error = tester.takeException();
        expect(error, isA<StateError>());
        expect(
          (error as StateError).message,
          contains('intentional sync throw before future'),
        );
      },
    );

    testWidgets(
      'routes asynchronous throws from the returned future through FlutterError.reportError',
      (tester) async {
        disposeAndReport(
          () async => throw StateError('intentional async throw'),
          contextDescription: 'unit test async-throw',
        );
        await tester.pumpAndSettle();

        final error = tester.takeException();
        expect(error, isA<StateError>());
        expect(
          (error as StateError).message,
          contains('intentional async throw'),
        );
      },
    );

    testWidgets(
      'reported FlutterErrorDetails carry the helper library and context',
      (tester) async {
        // Regression D7: catching exception type alone does not protect
        // the FlutterErrorDetails metadata. Library and context fields
        // are part of the helper's contract and need their own assertion.
        final captured = <FlutterErrorDetails>[];
        final original = FlutterError.onError;
        FlutterError.onError = (details) {
          captured.add(details);
          original?.call(details);
        };

        try {
          disposeAndReport(
            () => throw StateError('any error'),
            contextDescription: 'unique context description for assertion',
          );
          await tester.pumpAndSettle();

          expect(captured, hasLength(1));
          expect(captured.single.library, equals('flutter_plugin_kit'));
          expect(
            captured.single.context.toString(),
            contains('unique context description for assertion'),
          );
        } finally {
          FlutterError.onError = original;
        }

        // Drain so the framework doesn't flag the captured exception as
        // an unhandled error at test teardown.
        tester.takeException();
      },
    );

    testWidgets(
      'async-path failures preserve helper library and context metadata',
      (tester) async {
        // The sync-throw test above catches the error before the future
        // resolves; the async path goes through .catchError on the
        // returned Future. The metadata contract has to hold for both.
        final captured = <FlutterErrorDetails>[];
        final original = FlutterError.onError;
        FlutterError.onError = (details) {
          captured.add(details);
          original?.call(details);
        };

        try {
          disposeAndReport(
            () async => throw StateError('async-path error'),
            contextDescription: 'async-path context marker',
          );
          await tester.pumpAndSettle();

          expect(captured, hasLength(1));
          expect(captured.single.library, equals('flutter_plugin_kit'));
          expect(
            captured.single.context.toString(),
            contains('async-path context marker'),
          );
        } finally {
          FlutterError.onError = original;
        }

        tester.takeException();
      },
    );
  });

  group('PluginSessionStateListener mixin', () {
    testWidgets('listen handlers fire and cancel on dispose', (tester) async {
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);
      final session = await runtime.createSession();
      addTearDown(session.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            session: session,
            child: const _ListenerProbe(),
          ),
        ),
      );

      await session.emit(const _Ping(1));
      await tester.pump();
      expect(find.text('seen: 1'), findsOneWidget);

      await session.emit(const _Ping(2));
      await tester.pump();
      expect(find.text('seen: 2'), findsOneWidget);

      // Detach the probe; subsequent emits should not throw.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            session: session,
            child: const SizedBox.shrink(),
          ),
        ),
      );
      await session.emit(const _Ping(3));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('default session getter throws without an ambient scope', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: _ListenerProbe(),
        ),
      );
      // didChangeDependencies on the probe calls _swapSessionIfChanged,
      // which reads the default `session` getter; with no PluginSessionScope
      // ancestor in the tree, the getter throws a FlutterError.
      expect(tester.takeException(), isA<FlutterError>());
    });

    testWidgets('rebuildOn triggers rebuilds on each event', (tester) async {
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);
      final session = await runtime.createSession();
      addTearDown(session.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            session: session,
            child: const _RebuildOnProbe(),
          ),
        ),
      );

      expect(find.text('builds: 1'), findsOneWidget);
      await session.emit(const _Pong());
      await tester.pump();
      expect(find.text('builds: 2'), findsOneWidget);
    });

    testWidgets('PluginSessionScope session swap re-attaches bindings', (
      tester,
    ) async {
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);
      final sessionA = await runtime.createSession();
      addTearDown(sessionA.dispose);
      final sessionB = await runtime.createSession();
      addTearDown(sessionB.dispose);

      final probeKey = GlobalKey<_ListenerProbeState>();

      Widget tree(PluginSession s) => Directionality(
        textDirection: TextDirection.ltr,
        child: PluginSessionScope(
          session: s,
          child: _ListenerProbe(key: probeKey),
        ),
      );

      await tester.pumpWidget(tree(sessionA));
      await sessionA.emit(const _Ping(1));
      await tester.pump();
      expect(find.text('seen: 1'), findsOneWidget);

      // Re-pump with a different session under the same scope position.
      // The mixin's didChangeDependencies should re-attach to sessionB.
      await tester.pumpWidget(tree(sessionB));
      await tester.pumpAndSettle();
      // sessionA emits should no longer reach the probe.
      await sessionA.emit(const _Ping(99));
      await tester.pump();
      expect(find.text('seen: 1'), findsOneWidget);

      // sessionB emits should reach the probe.
      await sessionB.emit(const _Ping(2));
      await tester.pump();
      expect(find.text('seen: 2'), findsOneWidget);
    });

    testWidgets('widget.session swap re-attaches via didUpdateWidget', (
      tester,
    ) async {
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);
      final sessionA = await runtime.createSession();
      addTearDown(sessionA.dispose);
      final sessionB = await runtime.createSession();
      addTearDown(sessionB.dispose);

      Widget tree(PluginSession s) => Directionality(
        textDirection: TextDirection.ltr,
        child: _WidgetSessionProbe(session: s),
      );

      await tester.pumpWidget(tree(sessionA));
      await sessionA.emit(const _Ping(1));
      await tester.pump();
      expect(find.text('seen: 1'), findsOneWidget);

      // Re-pump with the same probe widget type but a different session.
      // Flutter reuses the State and calls didUpdateWidget; the mixin
      // must re-attach to sessionB.
      await tester.pumpWidget(tree(sessionB));
      await sessionA.emit(const _Ping(99));
      await tester.pump();
      expect(find.text('seen: 1'), findsOneWidget);

      await sessionB.emit(const _Ping(2));
      await tester.pump();
      expect(find.text('seen: 2'), findsOneWidget);
    });

    testWidgets('listen attaches after async session creation resolves', (
      tester,
    ) async {
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);

      // Mount listener under a scope that auto-creates its session.
      // The listener should attach once creation resolves.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            runtime: runtime,
            child: const _ListenerProbe(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Now grab the live session from the scope so we can emit on it.
      final BuildContext context = tester.element(find.byType(_ListenerProbe));
      final session = PluginSessionScope.of(context);

      await session.emit(const _Ping(7));
      await tester.pump();
      expect(find.text('seen: 7'), findsOneWidget);
    });

    testWidgets(
      'rebuildOn does not rebuild when the when-predicate returns false',
      (tester) async {
        final runtime = _newRuntime();
        addTearDown(runtime.dispose);
        final session = await runtime.createSession();
        addTearDown(session.dispose);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: PluginSessionScope(
              session: session,
              child: const _RebuildOnFilteredProbe(),
            ),
          ),
        );

        expect(find.text('builds: 1'), findsOneWidget);
        // The predicate returns false for every event, so emit should not
        // trigger a rebuild.
        await session.emit(const _Pong());
        await tester.pump();
        expect(find.text('builds: 1'), findsOneWidget);
      },
    );

    testWidgets('handler fires exactly once per emit after a session swap', (
      tester,
    ) async {
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);
      final sessionA = await runtime.createSession();
      addTearDown(sessionA.dispose);
      final sessionB = await runtime.createSession();
      addTearDown(sessionB.dispose);

      final probeKey = GlobalKey<_CountingProbeState>();

      Widget tree(PluginSession s) => Directionality(
        textDirection: TextDirection.ltr,
        child: PluginSessionScope(
          session: s,
          child: _CountingProbe(key: probeKey),
        ),
      );

      await tester.pumpWidget(tree(sessionA));
      await sessionA.emit(const _Ping(1));
      await tester.pump();
      expect(find.text('hits: 1'), findsOneWidget);

      await tester.pumpWidget(tree(sessionB));
      // After swap: only ONE active subscription should remain. Emit once
      // and assert exactly one hit (would be two if sessionA's sub leaked).
      await sessionB.emit(const _Ping(2));
      await tester.pump();
      expect(find.text('hits: 2'), findsOneWidget);
    });

    testWidgets(
      'multi-fire didChangeDependencies on same session does not double-subscribe',
      (tester) async {
        final runtime = _newRuntime();
        addTearDown(runtime.dispose);
        final session = await runtime.createSession();
        addTearDown(session.dispose);

        final brightnessNotifier = ValueNotifier(Brightness.light);
        addTearDown(brightnessNotifier.dispose);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: ValueListenableBuilder<Brightness>(
              valueListenable: brightnessNotifier,
              builder: (context, b, _) => MediaQuery(
                data: MediaQueryData(platformBrightness: b),
                child: PluginSessionScope(
                  session: session,
                  child: const _MediaQueryDependentProbe(),
                ),
              ),
            ),
          ),
        );

        // Cause MediaQuery to change → didChangeDependencies fires on probe.
        brightnessNotifier.value = Brightness.dark;
        await tester.pump();
        brightnessNotifier.value = Brightness.light;
        await tester.pump();

        // The brightness flips trigger MediaQuery dependency changes,
        // which forces didChangeDependencies to fire AT LEAST 3 times
        // (initial mount + 2 brightness changes). If it doesn't fire,
        // we're not actually testing what we claim.
        // Single emit → if double-subscribed, hits would be 2.
        await session.emit(const _Ping(1));
        await tester.pump();

        expect(find.textContaining('hits: 1'), findsOneWidget);
        expect(
          find.textContaining('deps: 3'),
          findsOneWidget,
          reason:
              'didChangeDependencies must have fired at least 3 times '
              '(initial + 2 brightness flips) for this test to be meaningful',
        );
      },
    );
  });

  group('PluginEventNotifier', () {
    testWidgets('value updates and dispose cancels subscription', (
      tester,
    ) async {
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);
      final session = await runtime.createSession();
      addTearDown(session.dispose);

      final notifier = PluginEventNotifier<_Ping>(session);
      expect(notifier.value, isNull);

      var notifications = 0;
      notifier.addListener(() => notifications++);

      await session.emit(const _Ping(7));
      await tester.pump();
      expect(notifier.value?.value, 7);
      expect(notifications, 1);

      notifier.dispose();
      // After dispose the notifier should not throw or update on new events.
      await session.emit(const _Ping(99));
      await tester.pump();
      expect(notifier.value?.value, 7);
    });
  });

  group('BuildContext.watchEvent / readEvent', () {
    testWidgets('watchEvent rebuilds on matching events', (tester) async {
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);
      final session = await runtime.createSession();
      addTearDown(session.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            session: session,
            child: Builder(
              builder: (context) {
                final ping = context.watchEvent<_Ping>();
                return Text('val: ${ping?.value ?? 'none'}');
              },
            ),
          ),
        ),
      );

      expect(find.text('val: none'), findsOneWidget);
      await session.emit(const _Ping(42));
      await tester.pump();
      expect(find.text('val: 42'), findsOneWidget);
    });

    testWidgets('readEvent does not subscribe the calling element', (
      tester,
    ) async {
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);
      final session = await runtime.createSession();
      addTearDown(session.dispose);

      var builds = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            session: session,
            child: Builder(
              builder: (context) {
                builds++;
                final ping = context.readEvent<_Ping>();
                return Text('seen: ${ping?.value ?? 'none'}');
              },
            ),
          ),
        ),
      );

      expect(builds, 1);
      await session.emit(const _Ping(1));
      await tester.pump();
      // Element did not subscribe via readEvent; builds count must be unchanged.
      expect(builds, 1);
    });

    testWidgets('throws when called outside a scope', (tester) async {
      Object? captured;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              try {
                context.watchEvent<_Ping>();
              } catch (e) {
                captured = e;
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(captured, isA<FlutterError>());
    });

    testWidgets('session swap clears the cached latest event for new session', (
      tester,
    ) async {
      // Regression: PluginSessionEvents tracks the latest event per type
      // for the active session. After a session swap, the cache must
      // start empty for the new session; otherwise the first build
      // against session B would surface a stale value emitted on session A.
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);
      final sessionA = await runtime.createSession();
      addTearDown(sessionA.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            session: sessionA,
            child: Builder(
              builder: (context) {
                final ping = context.watchEvent<_Ping>();
                return Text('val: ${ping?.value ?? 'none'}');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('val: none'), findsOneWidget);

      // Emit on session A.
      await sessionA.emit(const _Ping(7));
      await tester.pump();
      expect(find.text('val: 7'), findsOneWidget);

      // Swap to session B. The watchEvent cache must reset; first paint
      // against B must show 'none', not the stale '7' from A.
      final sessionB = await runtime.createSession();
      addTearDown(sessionB.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PluginSessionScope(
            session: sessionB,
            child: Builder(
              builder: (context) {
                final ping = context.watchEvent<_Ping>();
                return Text('val: ${ping?.value ?? 'none'}');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('val: none'),
        findsOneWidget,
        reason: 'cache must reset on session swap',
      );

      // Emit on session B and verify the cache picks it up.
      await sessionB.emit(const _Ping(99));
      await tester.pump();
      expect(find.text('val: 99'), findsOneWidget);

      // Cross-check: late emit on the (now-disposed-by-swap-or-not?)
      // session A must NOT update the watching element. Use the still-
      // valid sessionA reference (it's externally owned in this test)
      // and confirm the watcher stays on B's value.
      await sessionA.emit(const _Ping(1));
      await tester.pump();
      expect(
        find.text('val: 99'),
        findsOneWidget,
        reason: 'session A emissions must not affect session B watcher',
      );
    });
  });
}

class _ListenerProbe extends StatefulWidget {
  const _ListenerProbe({super.key});

  @override
  State<_ListenerProbe> createState() => _ListenerProbeState();
}

class _ListenerProbeState extends State<_ListenerProbe>
    with PluginSessionStateListener<_ListenerProbe> {
  int? _value;

  @override
  void initState() {
    super.initState();
    listen<_Ping>((envelope) => setState(() => _value = envelope.event.value));
  }

  @override
  Widget build(BuildContext context) {
    return Text(_value == null ? 'idle' : 'seen: $_value');
  }
}

class _RebuildOnProbe extends StatefulWidget {
  const _RebuildOnProbe();

  @override
  State<_RebuildOnProbe> createState() => _RebuildOnProbeState();
}

class _RebuildOnProbeState extends State<_RebuildOnProbe>
    with PluginSessionStateListener<_RebuildOnProbe> {
  int _builds = 0;

  @override
  void initState() {
    super.initState();
    rebuildOn<_Pong>();
  }

  @override
  Widget build(BuildContext context) {
    _builds++;
    return Text('builds: $_builds');
  }
}

class _WidgetSessionProbe extends StatefulWidget {
  const _WidgetSessionProbe({required this.session});

  final PluginSession session;

  @override
  State<_WidgetSessionProbe> createState() => _WidgetSessionProbeState();
}

class _WidgetSessionProbeState extends State<_WidgetSessionProbe>
    with PluginSessionStateListener<_WidgetSessionProbe> {
  @override
  PluginSession? get session => widget.session;

  int? _value;

  @override
  void initState() {
    super.initState();
    listen<_Ping>((envelope) => setState(() => _value = envelope.event.value));
  }

  @override
  Widget build(BuildContext context) {
    return Text(_value == null ? 'idle' : 'seen: $_value');
  }
}

class _RebuildOnFilteredProbe extends StatefulWidget {
  const _RebuildOnFilteredProbe();

  @override
  State<_RebuildOnFilteredProbe> createState() =>
      _RebuildOnFilteredProbeState();
}

class _RebuildOnFilteredProbeState extends State<_RebuildOnFilteredProbe>
    with PluginSessionStateListener<_RebuildOnFilteredProbe> {
  int _builds = 0;

  @override
  void initState() {
    super.initState();
    rebuildOn<_Pong>((_) => false); // never permits rebuild
  }

  @override
  Widget build(BuildContext context) {
    _builds++;
    return Text('builds: $_builds');
  }
}

class _CountingProbe extends StatefulWidget {
  const _CountingProbe({super.key});

  @override
  State<_CountingProbe> createState() => _CountingProbeState();
}

class _CountingProbeState extends State<_CountingProbe>
    with PluginSessionStateListener<_CountingProbe> {
  int _hits = 0;

  @override
  void initState() {
    super.initState();
    listen<_Ping>((_) => setState(() => _hits++));
  }

  @override
  Widget build(BuildContext context) => Text('hits: $_hits');
}

class _MediaQueryDependentProbe extends StatefulWidget {
  const _MediaQueryDependentProbe();

  @override
  State<_MediaQueryDependentProbe> createState() =>
      _MediaQueryDependentProbeState();
}

class _MediaQueryDependentProbeState extends State<_MediaQueryDependentProbe>
    with PluginSessionStateListener<_MediaQueryDependentProbe> {
  int _hits = 0;
  int _depChanges = 0;

  @override
  void initState() {
    super.initState();
    listen<_Ping>((_) => setState(() => _hits++));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _depChanges++;
  }

  @override
  Widget build(BuildContext context) {
    // Establish a dependency on MediaQuery so didChangeDependencies fires
    // when MediaQuery changes upstream.
    MediaQuery.of(context);
    return Text('hits: $_hits / deps: $_depChanges');
  }
}
