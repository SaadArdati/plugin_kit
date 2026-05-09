// Tests for the central correctness claim of the per-context bucketing
// refactor: a single Plugin instance shared across multiple sessions must
// keep each session's subscriptions, bindings, and stateful-service
// instances genuinely isolated, so that disposing one session never
// disturbs another.
//
// Also covers the per-service error tolerance in _runAttach / _runDetach:
// peer services and the plugin's own attach/detach run despite a single
// service hook throwing, while the failure still surfaces to the runtime
// for collection into a PluginLifecycleException. The same isolation rule
// applies inside StatefulPluginService._unbindContext, where one throwing
// sub.cancel() must not strand later cancels or leave _context bound.
//
// Each test is designed to fail loudly under realistic regressions: pre-
// commit mutation testing confirmed that reverting per-context bucketing
// to a shared list, removing the per-service try/catch, or removing the
// per-iteration try/catch inside _unbindContext breaks the matching tests.

import 'dart:async';

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

// === Test fixtures ===

class _Tagged {
  final String tag;
  const _Tagged(this.tag);
}

class _Question {
  final String prompt;
  const _Question(this.prompt);
}

/// Session plugin that subscribes via `on(context, ...)` in `attach`. The
/// list is shared across sessions on purpose: each session's subscription
/// adds to it, so the test can read which session contributed which event.
class _OnSubscriberPlugin extends SessionPlugin {
  final List<String> received = [];

  @override
  PluginId get pluginId => const PluginId('on_subscriber');

  @override
  void attach(SessionPluginContext context) {
    on<_Tagged>(context, (envelope) {
      received.add(envelope.event.tag);
    });
  }
}

class _OnRequestPlugin extends SessionPlugin {
  final List<String> handledFor = [];

  @override
  PluginId get pluginId => const PluginId('on_request_plugin');

  @override
  void attach(SessionPluginContext context) {
    onRequest<_Question, String?>(context, (envelope) async {
      handledFor.add('${envelope.event.prompt}|sub-${context.hashCode}');
      return 'answer:${envelope.event.prompt}';
    });
  }
}

class _OnRequestSyncPlugin extends SessionPlugin {
  final List<String> handledFor = [];

  @override
  PluginId get pluginId => const PluginId('on_request_sync_plugin');

  @override
  void attach(SessionPluginContext context) {
    onRequestSync<_Question, String>(context, (envelope) {
      handledFor.add(envelope.event.prompt);
      return 'sync:${envelope.event.prompt}';
    });
  }
}

class _BindObserverPlugin extends SessionPlugin {
  final List<String> seen = [];

  @override
  PluginId get pluginId => const PluginId('bind_observer');

  @override
  void attach(SessionPluginContext context) {
    bind(context, (envelope) {
      final event = envelope.event;
      if (event is _Tagged) {
        seen.add(event.tag);
      }
    });
  }
}

/// StatefulPluginService that records every event it sees. Used to verify
/// each session gets its own instance with its own state.
class _CounterService extends SessionStatefulPluginService {
  final List<String> events = [];

  @override
  void attach() {
    on<_Tagged>((envelope) => events.add(envelope.event.tag));
  }
}

class _CounterPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('counter_plugin');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_CounterService>(
      const ServiceId('counter'),
      _CounterService(),
    );
  }
}

/// Service whose `attach` throws. Used to verify peer services and the
/// plugin's user `attach` still run.
class _ThrowingAttachService extends SessionStatefulPluginService {
  bool attachWasCalled = false;

  @override
  void attach() {
    attachWasCalled = true;
    throw StateError('intentional attach failure');
  }
}

class _HealthyAttachService extends SessionStatefulPluginService {
  bool attachWasCalled = false;

  @override
  void attach() {
    attachWasCalled = true;
  }
}

class _PartialAttachFailurePlugin extends SessionPlugin {
  bool userAttachCalled = false;
  late _ThrowingAttachService throwingService;
  late _HealthyAttachService healthyService;

  @override
  PluginId get pluginId => const PluginId('partial_attach_failure');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_ThrowingAttachService>(
      const ServiceId('throwing'),
      _ThrowingAttachService(),
    );
    registry.registerSingleton<_HealthyAttachService>(
      const ServiceId('healthy'),
      _HealthyAttachService(),
    );
  }

  @override
  void attach(SessionPluginContext context) {
    userAttachCalled = true;
    throwingService = context.resolve<_ThrowingAttachService>(
      const ServiceId('throwing'),
    );
    healthyService = context.resolve<_HealthyAttachService>(
      const ServiceId('healthy'),
    );
  }
}

/// Service whose `detach` throws. Used to verify the rest of the teardown
/// path still runs.
class _ThrowingDetachService extends SessionStatefulPluginService {
  bool detachWasCalled = false;

  @override
  Future<void> detach() async {
    detachWasCalled = true;
    throw StateError('intentional detach failure');
  }
}

/// Service whose `detach` records that it ran, used to confirm peer services
/// still detach despite a sibling throwing.
class _RecordingDetachService extends SessionStatefulPluginService {
  bool detachWasCalled = false;

  @override
  Future<void> detach() async {
    detachWasCalled = true;
  }
}

class _PartialDetachFailurePlugin extends SessionPlugin {
  bool subscriptionFiredAfterDetachAttempt = false;
  late _ThrowingDetachService throwingService;
  late _RecordingDetachService recordingService;

  @override
  PluginId get pluginId => const PluginId('partial_detach_failure');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_ThrowingDetachService>(
      const ServiceId('throwing'),
      _ThrowingDetachService(),
    );
    registry.registerSingleton<_RecordingDetachService>(
      const ServiceId('recording'),
      _RecordingDetachService(),
    );
  }

  @override
  void attach(SessionPluginContext context) {
    throwingService = context.resolve<_ThrowingDetachService>(
      const ServiceId('throwing'),
    );
    recordingService = context.resolve<_RecordingDetachService>(
      const ServiceId('recording'),
    );
    on<_Tagged>(context, (_) {
      subscriptionFiredAfterDetachAttempt = true;
    });
  }
}

/// Service that registers a real subscription whose `cancel()` throws,
/// alongside a peer subscription that records whether its own `cancel()`
/// ran. Used to verify that one bad cancel inside `_unbindContext` does
/// not strand later cancellations or prevent `_context` from being cleared.
class _SubCancelThrowingService extends SessionStatefulPluginService {
  /// Whether the peer subscription's underlying stream was cancelled. The
  /// stream is wired so that this flips to `true` only when its `cancel()`
  /// actually runs - so it functions as a regression detector.
  bool peerCancelRan = false;

  /// The throwing subscription's stream controller; we read its
  /// `isClosed`/`hasListener` state from the test as a second-channel
  /// check that its cancel was at least *attempted* (and threw).
  late final StreamController<int> throwingController;

  @override
  void attach() {
    throwingController = StreamController<int>();
    throwingController.onCancel = () {
      throw StateError('intentional cancel failure');
    };
    activeSubscriptions.add(throwingController.stream.listen((_) {}));

    final peerController = StreamController<int>();
    peerController.onCancel = () {
      peerCancelRan = true;
    };
    activeSubscriptions.add(peerController.stream.listen((_) {}));
  }
}

class _SubCancelThrowingPlugin extends SessionPlugin {
  late _SubCancelThrowingService cancelService;

  @override
  PluginId get pluginId => const PluginId('sub_cancel_throwing');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_SubCancelThrowingService>(
      const ServiceId('sub_cancel'),
      _SubCancelThrowingService(),
    );
  }

  @override
  void attach(SessionPluginContext context) {
    cancelService = context.resolve<_SubCancelThrowingService>(
      const ServiceId('sub_cancel'),
    );
  }
}

/// Marker event used by `_ReentrantOnCancelService` to drive a re-entrant
/// `on(...)` registration from inside a stream's `onCancel` callback.
class _ReentrantTrigger {
  const _ReentrantTrigger();
}

/// Service whose `onCancel` re-enters the helper to register a NEW
/// subscription mid-detach. Used to prove that `_unbindContext` detects
/// the re-entry and surfaces it as a step failure rather than letting
/// the new subscription leak silently against a still-live bus.
class _ReentrantOnCancelService extends SessionStatefulPluginService {
  late final StreamController<int> primary;
  bool reentrantSubAttempted = false;

  @override
  void attach() {
    primary = StreamController<int>();
    primary.onCancel = () {
      // Misuse: subscribe again from inside the cancel callback. The new
      // subscription would land in the just-cleared activeSubscriptions
      // list and never be cancelled in this teardown pass without the
      // re-entry detection.
      on<_ReentrantTrigger>((_) {});
      reentrantSubAttempted = true;
    };
    activeSubscriptions.add(primary.stream.listen((_) {}));
  }
}

class _ReentrantOnCancelPlugin extends SessionPlugin {
  late _ReentrantOnCancelService service;

  @override
  PluginId get pluginId => const PluginId('reentrant_on_cancel');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_ReentrantOnCancelService>(
      const ServiceId('reentrant'),
      _ReentrantOnCancelService(),
    );
  }

  @override
  void attach(SessionPluginContext context) {
    service = context.resolve<_ReentrantOnCancelService>(
      const ServiceId('reentrant'),
    );
  }
}

/// Service whose attach throws. Used together with `_TwoStepFailurePlugin`
/// to drive a multi-step failure pass.
class _AttachThrowingMarkerService extends SessionStatefulPluginService {
  @override
  void attach() {
    throw StateError('service attach failure');
  }
}

/// Plugin where BOTH a service attach AND the user attach throw, so a
/// single _runAttach pass produces two step failures and must surface a
/// PluginStepAggregateException rather than only the first error.
class _TwoStepFailurePlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('two_step_failure');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_AttachThrowingMarkerService>(
      const ServiceId('attach_thrower'),
      _AttachThrowingMarkerService(),
    );
  }

  @override
  void attach(SessionPluginContext context) {
    throw StateError('plugin attach failure');
  }
}

/// Service with two subscriptions whose `cancel()` both throw. Used to
/// verify that `_unbindContext` propagates each per-iteration failure as
/// its own outer step entry rather than collapsing them under a single
/// `<serviceId>.unbind` label.
class _TwoThrowingCancelsService extends SessionStatefulPluginService {
  late final StreamController<int> firstThrower;
  late final StreamController<int> secondThrower;

  @override
  void attach() {
    firstThrower = StreamController<int>();
    firstThrower.onCancel = () {
      throw StateError('first cancel failure');
    };
    activeSubscriptions.add(firstThrower.stream.listen((_) {}));
    secondThrower = StreamController<int>();
    secondThrower.onCancel = () {
      throw StateError('second cancel failure');
    };
    activeSubscriptions.add(secondThrower.stream.listen((_) {}));
  }
}

class _TwoThrowingCancelsPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('two_throwing_cancels');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_TwoThrowingCancelsService>(
      const ServiceId('two_throwers'),
      _TwoThrowingCancelsService(),
    );
  }
}

/// Plugin whose user `attach` throws an [OutOfMemoryError]. Used to verify
/// that VM-fatal errors are not caught by the framework's lifecycle
/// isolation - they must propagate uncaught so the process can die.
class _OOMOnAttachPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('oom_on_attach');

  @override
  void attach(SessionPluginContext context) {
    throw OutOfMemoryError();
  }
}

void main() {
  // === Per-context bucket isolation ===

  group('Plugin per-context subscription bucketing', () {
    test('on(context,...) handlers stay alive on session B after session A '
        'disposes', () async {
      final plugin = _OnSubscriberPlugin();
      final runtime = PluginRuntime(plugins: [plugin])
        ..init(settings: RuntimeSettings.empty());
      addTearDown(runtime.dispose);

      final sessionA = await runtime.createSession();
      final sessionB = await runtime.createSession();

      // Sanity: both buckets are wired.
      await sessionA.bus.emit<_Tagged>(event: const _Tagged('A1'));
      await sessionB.bus.emit<_Tagged>(event: const _Tagged('B1'));
      expect(plugin.received, equals(['A1', 'B1']));

      await sessionA.dispose();

      // The load-bearing assertion: B's bucket survived A's teardown.
      await sessionB.bus.emit<_Tagged>(event: const _Tagged('B2'));
      expect(plugin.received, equals(['A1', 'B1', 'B2']));
    });

    test(
      'symmetric: disposing session B leaves session A unaffected',
      () async {
        final plugin = _OnSubscriberPlugin();
        final runtime = PluginRuntime(plugins: [plugin])
          ..init(settings: RuntimeSettings.empty());
        addTearDown(runtime.dispose);

        final sessionA = await runtime.createSession();
        final sessionB = await runtime.createSession();

        await sessionA.bus.emit<_Tagged>(event: const _Tagged('A1'));
        await sessionB.bus.emit<_Tagged>(event: const _Tagged('B1'));
        expect(plugin.received, equals(['A1', 'B1']));

        await sessionB.dispose();

        await sessionA.bus.emit<_Tagged>(event: const _Tagged('A2'));
        expect(plugin.received, equals(['A1', 'B1', 'A2']));
      },
    );

    test('onRequest(context,...) handler on session B still answers after '
        'session A disposes', () async {
      final plugin = _OnRequestPlugin();
      final runtime = PluginRuntime(plugins: [plugin])
        ..init(settings: RuntimeSettings.empty());
      addTearDown(runtime.dispose);

      final sessionA = await runtime.createSession();
      final sessionB = await runtime.createSession();

      final answerA = await sessionA.bus.request<_Question, String?>(
        const _Question('alpha'),
      );
      final answerB = await sessionB.bus.request<_Question, String?>(
        const _Question('beta'),
      );
      expect(answerA, equals('answer:alpha'));
      expect(answerB, equals('answer:beta'));

      await sessionA.dispose();

      final answerB2 = await sessionB.bus.request<_Question, String?>(
        const _Question('gamma'),
      );
      expect(answerB2, equals('answer:gamma'));
    });

    test('onRequestSync(context,...) handler on session B still answers '
        'after session A disposes', () async {
      final plugin = _OnRequestSyncPlugin();
      final runtime = PluginRuntime(plugins: [plugin])
        ..init(settings: RuntimeSettings.empty());
      addTearDown(runtime.dispose);

      final sessionA = await runtime.createSession();
      final sessionB = await runtime.createSession();

      expect(
        sessionA.bus.requestSync<_Question, String>(const _Question('alpha')),
        equals('sync:alpha'),
      );
      expect(
        sessionB.bus.requestSync<_Question, String>(const _Question('beta')),
        equals('sync:beta'),
      );

      await sessionA.dispose();

      expect(
        sessionB.bus.requestSync<_Question, String>(const _Question('gamma')),
        equals('sync:gamma'),
      );
    });

    test('bind(context,...) callback on session B still fires after '
        'session A disposes', () async {
      final plugin = _BindObserverPlugin();
      final runtime = PluginRuntime(plugins: [plugin])
        ..init(settings: RuntimeSettings.empty());
      addTearDown(runtime.dispose);

      final sessionA = await runtime.createSession();
      final sessionB = await runtime.createSession();

      await sessionA.bus.emit<_Tagged>(event: const _Tagged('A1'));
      await sessionB.bus.emit<_Tagged>(event: const _Tagged('B1'));
      expect(plugin.seen, equals(['A1', 'B1']));

      await sessionA.dispose();

      await sessionB.bus.emit<_Tagged>(event: const _Tagged('B2'));
      expect(plugin.seen, equals(['A1', 'B1', 'B2']));
    });
  });

  // === StatefulPluginService per-session instance isolation ===

  group('StatefulPluginService per-session isolation', () {
    test('each session resolves a distinct service instance', () async {
      final runtime = PluginRuntime(plugins: [_CounterPlugin()])
        ..init(settings: RuntimeSettings.empty());
      addTearDown(runtime.dispose);

      final sessionA = await runtime.createSession();
      final sessionB = await runtime.createSession();

      final serviceA = sessionA.context.resolve<_CounterService>(
        const ServiceId('counter'),
      );
      final serviceB = sessionB.context.resolve<_CounterService>(
        const ServiceId('counter'),
      );

      expect(identical(serviceA, serviceB), isFalse);
    });

    test('events on session A only update session A\'s service', () async {
      final runtime = PluginRuntime(plugins: [_CounterPlugin()])
        ..init(settings: RuntimeSettings.empty());
      addTearDown(runtime.dispose);

      final sessionA = await runtime.createSession();
      final sessionB = await runtime.createSession();
      final serviceA = sessionA.context.resolve<_CounterService>(
        const ServiceId('counter'),
      );
      final serviceB = sessionB.context.resolve<_CounterService>(
        const ServiceId('counter'),
      );

      await sessionA.bus.emit<_Tagged>(event: const _Tagged('a-only'));
      await sessionB.bus.emit<_Tagged>(event: const _Tagged('b-only'));

      expect(serviceA.events, equals(['a-only']));
      expect(serviceB.events, equals(['b-only']));
    });

    test(
      'disposing session A leaves session B\'s service receiving events',
      () async {
        final runtime = PluginRuntime(plugins: [_CounterPlugin()])
          ..init(settings: RuntimeSettings.empty());
        addTearDown(runtime.dispose);

        final sessionA = await runtime.createSession();
        final sessionB = await runtime.createSession();
        final serviceB = sessionB.context.resolve<_CounterService>(
          const ServiceId('counter'),
        );

        await sessionA.dispose();

        await sessionB.bus.emit<_Tagged>(event: const _Tagged('after-A-gone'));
        expect(serviceB.events, equals(['after-A-gone']));
      },
    );
  });

  // === Per-service error tolerance ===

  group('_runAttach error tolerance', () {
    test('a service whose attach() throws does not block peer service attach() '
        'or plugin attach(); failure still surfaces to runtime', () async {
      final plugin = _PartialAttachFailurePlugin();
      final runtime = PluginRuntime(plugins: [plugin])
        ..init(settings: RuntimeSettings.empty());
      addTearDown(runtime.dispose);

      // Runtime collects the failure and surfaces it. Without this, a failing
      // plugin would be silently swallowed by the framework.
      await expectLater(
        runtime.createSession(),
        throwsA(isA<PluginLifecycleException>()),
      );

      // Despite the throw, isolation kept the rest of the lifecycle running:
      // throwing service's attach was invoked, peer service's attach also ran,
      // and the plugin's own attach also ran.
      expect(plugin.throwingService.attachWasCalled, isTrue);
      expect(plugin.healthyService.attachWasCalled, isTrue);
      expect(plugin.userAttachCalled, isTrue);
    });
  });

  group('_runDetach error tolerance', () {
    test('a service whose detach() throws does not block peer service '
        'detach; failure still surfaces to runtime', () async {
      final plugin = _PartialDetachFailurePlugin();
      final runtime = PluginRuntime(plugins: [plugin])
        ..init(settings: RuntimeSettings.empty());
      // Session is disposed manually below; runtime.dispose with no remaining
      // sessions is a clean no-op for cleanup.
      addTearDown(runtime.dispose);

      final session = await runtime.createSession();

      // Sanity: subscription wired during attach.
      await session.bus.emit<_Tagged>(event: const _Tagged('pre-dispose'));
      expect(plugin.subscriptionFiredAfterDetachAttempt, isTrue);

      // Runtime surfaces the detach failure for collection. Without the
      // rethrow at the end of _runDetach, plugin failures would be silently
      // swallowed instead of bubbling up to PluginLifecycleException.
      await expectLater(
        session.dispose(),
        throwsA(isA<PluginLifecycleException>()),
      );

      // Despite the throwing service raising mid-detach, isolation kept the
      // rest of the lifecycle running: both the throwing service's detach
      // and the peer service's detach were invoked.
      expect(plugin.throwingService.detachWasCalled, isTrue);
      expect(plugin.recordingService.detachWasCalled, isTrue);
    });
  });

  // === StatefulPluginService._unbindContext internal isolation ===

  group('StatefulPluginService _unbindContext isolation', () {
    test('a throwing sub.cancel() does not strand later cancels and still '
        'clears the bound context', () async {
      final plugin = _SubCancelThrowingPlugin();
      final runtime = PluginRuntime(plugins: [plugin])
        ..init(settings: RuntimeSettings.empty());
      addTearDown(runtime.dispose);

      final session = await runtime.createSession();

      // The framework's plugin-level isolation rethrows the throwing cancel
      // as a PluginLifecycleException; we expect that, but the assertions
      // afterward verify the per-iteration isolation INSIDE _unbindContext.
      await expectLater(
        session.dispose(),
        throwsA(isA<PluginLifecycleException>()),
      );

      // The peer subscription's cancel ran despite the earlier throw.
      // Without the per-iteration try/catch in _unbindContext, the loop
      // would have aborted on the first cancel and this would be false.
      expect(plugin.cancelService.peerCancelRan, isTrue);

      // _context was cleared despite the throw. Without the always-runs
      // ordering in _unbindContext, hasContext would still be true.
      expect(plugin.cancelService.hasContext, isFalse);

      // activeSubscriptions was drained (no leaked entries to a re-attach).
      expect(plugin.cancelService.activeSubscriptions, isEmpty);
    });

    test('a re-entrant on(...) inside an onCancel callback surfaces as a '
        '<serviceId>.subscription.leak step entry, and the leaked '
        'subscription is dropped from activeSubscriptions', () async {
      final plugin = _ReentrantOnCancelPlugin();
      final runtime = PluginRuntime(plugins: [plugin])
        ..init(settings: RuntimeSettings.empty());
      addTearDown(runtime.dispose);

      final session = await runtime.createSession();

      late PluginLifecycleException caught;
      try {
        await session.dispose();
        fail('Expected PluginLifecycleException, but dispose returned');
      } on PluginLifecycleException catch (e) {
        caught = e;
      }

      // The re-entry actually happened (sanity check on the fixture).
      expect(plugin.service.reentrantSubAttempted, isTrue);

      // The framework detected the leak and surfaced it as a step entry
      // with the documented stable name. Without the post-cancel-loop
      // re-entry check, the new subscription would silently survive in
      // activeSubscriptions and this would be hasLength(0).
      expect(caught.failures, hasLength(1));
      final (_, error, _) = caught.failures.single;
      expect(error, isA<StateError>());
      // Single-step failure path: the StateError surfaces directly, no
      // PluginStepAggregateException wrapping. (If the framework
      // produced multiple step failures here, this would be an aggregate.)
      expect(
        (error as StateError).message,
        contains(
          'subscription(s) were registered on reentrant during '
          '_unbindContext',
        ),
      );

      // The leaked entry was dropped from activeSubscriptions (we report
      // the misuse but do not try to recover by cancelling the new sub).
      expect(plugin.service.activeSubscriptions, isEmpty);
    });
  });

  // === Single-failure passthrough preserves original exception type ===

  group('Single-failure passthrough', () {
    test('one failing step rethrows the original exception type unchanged '
        '(not wrapped in PluginStepAggregateException)', () async {
      // _PartialAttachFailurePlugin's only failure is the throwing service's
      // attach - the user attach succeeds. So _throwAggregated takes the
      // single-failure branch and rethrows the raw StateError. The runtime
      // catches it and stores it as one failure entry. Consumers must be
      // able to pattern-match on the concrete exception type without an
      // extra unwrap step.
      final plugin = _PartialAttachFailurePlugin();
      final runtime = PluginRuntime(plugins: [plugin])
        ..init(settings: RuntimeSettings.empty());
      addTearDown(runtime.dispose);

      late PluginLifecycleException caught;
      try {
        await runtime.createSession();
        fail('Expected PluginLifecycleException, but createSession returned');
      } on PluginLifecycleException catch (e) {
        caught = e;
      }

      expect(caught.failures, hasLength(1));
      final (_, error, stack) = caught.failures.single;

      // Must be the raw StateError, NOT wrapped in PluginStepAggregateException.
      expect(error, isA<StateError>());
      expect(error, isNot(isA<PluginStepAggregateException>()));
      expect(
        (error as StateError).message,
        equals('intentional attach failure'),
      );

      // Stack trace was preserved through the Error.throwWithStackTrace
      // path: the trace contains a frame from the original throw site,
      // not just frames from the framework's rethrow. If _throwAggregated
      // ever forgets to use throwWithStackTrace, this regresses.
      expect(stack.toString(), contains('_ThrowingAttachService'));
    });
  });

  // === Multi-step aggregate failure ===

  group('Multi-step aggregate', () {
    test('two failing steps in one _runAttach surface as a '
        'PluginStepAggregateException with both step entries', () async {
      final plugin = _TwoStepFailurePlugin();
      final runtime = PluginRuntime(plugins: [plugin])
        ..init(settings: RuntimeSettings.empty());
      addTearDown(runtime.dispose);

      late PluginLifecycleException caught;
      try {
        await runtime.createSession();
        fail('Expected PluginLifecycleException, but createSession returned');
      } on PluginLifecycleException catch (e) {
        caught = e;
      }

      expect(caught.failures, hasLength(1));
      final (failedPluginId, error, _) = caught.failures.single;
      expect(failedPluginId, equals(const PluginId('two_step_failure')));

      // With two failures, the runtime sees an aggregate, not the raw
      // first error. Single-failure passes (covered above) keep the raw
      // exception type for pattern-matching; this case proves the
      // aggregation triggers when - and only when - >1 step fails.
      expect(error, isA<PluginStepAggregateException>());
      final aggregate = error as PluginStepAggregateException;
      expect(aggregate.pluginId, equals(const PluginId('two_step_failure')));
      expect(aggregate.hook, equals('attach'));
      expect(aggregate.stepFailures, hasLength(2));
      expect(
        aggregate.stepFailures.map((f) => f.$1).toList(),
        equals(['attach_thrower.attach', 'attach']),
      );
      expect(
        aggregate.stepFailures
            .map((f) => (f.$2 as StateError).message)
            .toList(),
        equals(['service attach failure', 'plugin attach failure']),
      );
    });

    test('two failing sub.cancel() inside _unbindContext surface as TWO '
        'distinct outer step entries (not collapsed)', () async {
      // _unbindContext used to collapse all internal failures into a single
      // <serviceId>.unbind step in the outer aggregate. Now each failed
      // cancel propagates as its own entry tagged
      // <serviceId>.subscription.cancel, so consumers can see EVERY error,
      // not just the first.
      final plugin = _TwoThrowingCancelsPlugin();
      final runtime = PluginRuntime(plugins: [plugin])
        ..init(settings: RuntimeSettings.empty());
      addTearDown(runtime.dispose);

      final session = await runtime.createSession();

      late PluginLifecycleException caught;
      try {
        await session.dispose();
        fail('Expected PluginLifecycleException, but dispose returned');
      } on PluginLifecycleException catch (e) {
        caught = e;
      }

      expect(caught.failures, hasLength(1));
      final (_, error, _) = caught.failures.single;
      expect(error, isA<PluginStepAggregateException>());
      final aggregate = error as PluginStepAggregateException;

      // Both cancels appear as their own step entries with the serviceId-
      // prefixed step name. If _unbindContext compressed them into a single
      // 'two_throwers.unbind' entry (its old behavior), this would be
      // hasLength(1) and the assertion below would fail.
      expect(aggregate.stepFailures, hasLength(2));
      expect(
        aggregate.stepFailures.map((f) => f.$1).toList(),
        equals([
          'two_throwers.subscription.cancel',
          'two_throwers.subscription.cancel',
        ]),
      );
      expect(
        aggregate.stepFailures
            .map((f) => (f.$2 as StateError).message)
            .toList(),
        equals(['first cancel failure', 'second cancel failure']),
      );
    });
  });

  // === VM-fatal error propagation ===

  group('VM-fatal error propagation', () {
    test('OutOfMemoryError in plugin attach() is not caught by the '
        'framework and propagates uncaught past the runtime', () async {
      final runtime = PluginRuntime(plugins: [_OOMOnAttachPlugin()])
        ..init(settings: RuntimeSettings.empty());
      addTearDown(() async {
        // Best-effort cleanup; runtime never reached a stable state.
        try {
          await runtime.dispose();
        } catch (_) {}
      });

      // The fatal error must NOT be wrapped in PluginLifecycleException.
      // It must surface as the original OutOfMemoryError type so process-
      // level handlers can act on it (typically: die).
      await expectLater(
        runtime.createSession(),
        throwsA(isA<OutOfMemoryError>()),
      );
    });
  });
}
