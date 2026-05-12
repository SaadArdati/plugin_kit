import 'dart:async';

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

// --- Test event types ---

class EventA {
  final String value;

  EventA(this.value);
}

class EventB {
  final int count;

  EventB(this.count);
}

class SearchQuery {
  final String query;

  SearchQuery(this.query);

  SearchQuery.named({required this.query});
}

class SearchResults {
  final List<String> results;

  SearchResults(this.results);

  SearchResults.named({required this.results});
}

void main() {
  late EventBus bus;

  setUp(() {
    bus = EventBus();
  });

  tearDown(() {
    if (!bus.isDisposed) bus.dispose();
  });

  // ===========================================================================
  // PluginEventResponse
  // ===========================================================================
  group('PluginEventResponse', () {
    test('stores event and identifier', () {
      final envelope = EventEnvelope<String>(event: 'hello', identifier: 'id1');
      expect(envelope.event, 'hello');
      expect(envelope.identifier, 'id1');
      expect(envelope.stopped, isFalse);
    });

    test('stop() sets event and marks stopped', () {
      final envelope = EventEnvelope<String>(
        event: 'original',
        identifier: null,
      );
      envelope.stop('replaced');
      expect(envelope.event, 'replaced');
      expect(envelope.stopped, isTrue);
    });

    test('identifier can be null', () {
      final envelope = EventEnvelope<int>(event: 42, identifier: null);
      expect(envelope.identifier, isNull);
    });
  });

  // ===========================================================================
  // dispose
  // ===========================================================================
  group('dispose()', () {
    test('sets isDisposed to true', () {
      expect(bus.isDisposed, isFalse);
      bus.dispose();
      expect(bus.isDisposed, isTrue);
    });

    test('clears all handlers', () async {
      var callCount = 0;
      bus.on<String>((event) {
        callCount++;
      });

      await bus.emit<String>(event: 'test');
      expect(callCount, 1);

      bus.dispose();
      // After dispose, emit throws StateError — the handler is gone.
      expect(() => bus.emit<String>(event: 'test'), throwsA(isA<StateError>()));
      expect(callCount, 1);
    });

    test('clears all bindings', () async {
      var called = false;
      bus.bind((e) => called = true);
      bus.dispose();
      // After dispose, emit throws StateError — no silent no-op.
      expect(() => bus.emit<String>(event: 'test'), throwsA(isA<StateError>()));
      expect(called, isFalse);
    });
  });

  // ===========================================================================
  // on(): basic subscription and priority ordering
  // ===========================================================================
  group('on(): basic subscription', () {
    test('handler receives emitted event', () async {
      String? received;
      bus.on<String>((event) {
        received = event.event;
      });

      await bus.emit<String>(event: 'hello');
      expect(received, 'hello');
    });

    test('handler receives typed events only', () async {
      var stringCalled = false;
      var intCalled = false;

      bus.on<String>((event) {
        stringCalled = true;
      });
      bus.on<int>((event) {
        intCalled = true;
      });

      await bus.emit<String>(event: 'hello');
      expect(stringCalled, isTrue);
      expect(intCalled, isFalse);
    });

    test('custom event types are dispatched by type', () async {
      EventA? receivedA;
      EventB? receivedB;

      bus.on<EventA>((event) {
        receivedA = event.event;
      });
      bus.on<EventB>((event) {
        receivedB = event.event;
      });

      await bus.emit<EventA>(event: EventA('test'));
      expect(receivedA?.value, 'test');
      expect(receivedB, isNull);
    });

    test('multiple handlers for the same type all get called', () async {
      final calls = <int>[];
      bus.on<String>((event) {
        calls.add(1);
      });
      bus.on<String>((event) {
        calls.add(2);
      });

      await bus.emit<String>(event: 'hello');
      expect(calls, [1, 2]);
    });
  });

  // ===========================================================================
  // on(): priority ordering
  // ===========================================================================
  group('on(): priority ordering', () {
    test(
      'handlers execute in descending priority order (higher first)',
      () async {
        final order = <int>[];

        bus.on<String>((event) {
          order.add(3);
        }, priority: 30);
        bus.on<String>((event) {
          order.add(1);
        }, priority: 10);
        bus.on<String>((event) {
          order.add(2);
        }, priority: 20);

        await bus.emit<String>(event: 'test');
        expect(order, [3, 2, 1]);
      },
    );

    test('same-priority handlers maintain insertion order', () async {
      final order = <String>[];

      bus.on<String>((event) {
        order.add('first');
      }, priority: 0);
      bus.on<String>((event) {
        order.add('second');
      }, priority: 0);
      bus.on<String>((event) {
        order.add('third');
      }, priority: 0);

      await bus.emit<String>(event: 'test');
      expect(order, ['first', 'second', 'third']);
    });

    test('negative priorities run after zero (they are lower)', () async {
      final order = <String>[];

      bus.on<String>((event) {
        order.add('zero');
      }, priority: 0);
      bus.on<String>((event) {
        order.add('negative');
      }, priority: -10);

      await bus.emit<String>(event: 'test');
      expect(order, ['zero', 'negative']);
    });
  });

  group('on() observer', () {
    test(
      'on registers an observer that receives the raw event value',
      () async {
        final received = <String>[];
        bus.on<String>((event) {
          received.add(event.event);
        });
        await bus.emit<String>(event: 'payload');
        expect(received, ['payload']);
      },
    );

    test(
      'on observer cannot stop the cascade; later handler runs after',
      () async {
        var observerRan = false;
        var hookRan = false;
        bus.on<String>((event) {
          observerRan = true;
        });
        bus.on<String>((e) {
          hookRan = true;
        }, priority: 10);
        await bus.emit<String>(event: 'payload');
        expect(observerRan, isTrue);
        expect(hookRan, isTrue);
      },
    );

    test('on accepts async void callbacks', () async {
      var awaited = false;
      bus.on<String>((event) async {
        await Future<void>.delayed(Duration.zero);
        awaited = true;
      });
      await bus.emit<String>(event: 'payload');
      expect(awaited, isTrue);
    });
  });

  // ===========================================================================
  // on(): early termination
  // ===========================================================================
  group('on(): early termination', () {
    test('on supports early termination via event.stop()', () async {
      bus.on<String>((e) {
        e.stop('stopped-value');
      });
      final res = await bus.emit<String>(event: 'original');
      expect(res.event, 'stopped-value');
      expect(res.stopped, isTrue);
    });

    test('calling stop() halts propagation', () async {
      final order = <int>[];

      // Higher priority runs first; if it stops, the lower one never runs.
      bus.on<String>((e) {
        order.add(1);
        e.stop('stopped-value');
      }, priority: 10);
      bus.on<String>((e) {
        order.add(2);
      }, priority: 0);

      final result = await bus.emit<String>(event: 'original');
      expect(order, [1]);
      expect(result.stopped, isTrue);
      expect(result.event, 'stopped-value');
    });

    test('event payload can be mutated by handlers', () async {
      // Higher-priority handler mutates first; lower-priority handler
      // observes the mutated value downstream.
      bus.on<EventA>((e) {
        e.event = EventA('${e.event.value}-modified');
      }, priority: 10);

      String? downstream;
      bus.on<EventA>((e) {
        downstream = e.event.value;
      }, priority: 0);

      await bus.emit<EventA>(event: EventA('original'));
      expect(downstream, 'original-modified');
    });
  });

  // ===========================================================================
  // on(): identifier scoping
  // ===========================================================================
  group('on(): identifier scoping', () {
    test(
      'identifier-scoped handler is called when emitting with matching identifier',
      () async {
        var called = false;
        bus.on<String>((event) {
          called = true;
        }, identifier: 'agent1');

        await bus.emit<String>(event: 'test', identifier: 'agent1');
        expect(called, isTrue);
      },
    );

    test(
      'identifier-scoped handler is NOT called when emitting without identifier',
      () async {
        var called = false;
        bus.on<String>((event) {
          called = true;
        }, identifier: 'agent1');

        await bus.emit<String>(event: 'test');
        expect(called, isFalse);
      },
    );

    test(
      'identifier-scoped handler is NOT called for different identifier',
      () async {
        var called = false;
        bus.on<String>((event) {
          called = true;
        }, identifier: 'agent1');

        await bus.emit<String>(event: 'test', identifier: 'agent2');
        expect(called, isFalse);
      },
    );

    test('general and identifier handlers are merged by priority', () async {
      final order = <String>[];

      bus.on<String>((event) {
        order.add('general-p10');
      }, priority: 10);
      bus.on<String>(
        (event) {
          order.add('scoped-p5');
        },
        priority: 5,
        identifier: 'agent1',
      );
      bus.on<String>((event) {
        order.add('general-p0');
      }, priority: 0);

      await bus.emit<String>(event: 'test', identifier: 'agent1');
      // Higher priority runs first across merged general + scoped lists.
      expect(order, ['general-p10', 'scoped-p5', 'general-p0']);
    });

    test('emitting with identifier still runs general handlers', () async {
      var generalCalled = false;
      bus.on<String>((event) {
        generalCalled = true;
      });

      await bus.emit<String>(event: 'test', identifier: 'agent1');
      expect(generalCalled, isTrue);
    });
  });

  // ===========================================================================
  // on(): subscription cancellation
  // ===========================================================================
  group('on(): subscription cancellation', () {
    test('cancel removes the handler', () async {
      var callCount = 0;
      final sub = bus.on<String>((event) {
        callCount++;
      });

      await bus.emit<String>(event: 'first');
      expect(callCount, 1);

      await sub.cancel();

      await bus.emit<String>(event: 'second');
      expect(callCount, 1);
    });

    test('cancel removes identifier-scoped handler', () async {
      var callCount = 0;
      final sub = bus.on<String>((event) {
        callCount++;
      }, identifier: 'agent1');

      await bus.emit<String>(event: 'first', identifier: 'agent1');
      expect(callCount, 1);

      await sub.cancel();

      await bus.emit<String>(event: 'second', identifier: 'agent1');
      expect(callCount, 1);
    });

    test('cancelling one handler does not affect others', () async {
      var count1 = 0, count2 = 0;
      final sub1 = bus.on<String>((event) {
        count1++;
      });
      bus.on<String>((event) {
        count2++;
      });

      await sub1.cancel();
      await bus.emit<String>(event: 'test');
      expect(count1, 0);
      expect(count2, 1);
    });

    test(
      'cancelling last general handler cleans up type bucket if no id handlers',
      () async {
        var callCount = 0;
        final sub = bus.on<EventA>((event) {
          callCount++;
        });

        await bus.emit<EventA>(event: EventA('before-cancel'));
        expect(callCount, 1);

        await sub.cancel();

        var replacementCalled = false;
        final replacementSub = bus.on<EventA>((event) {
          replacementCalled = true;
        });
        await bus.emit<EventA>(event: EventA('after-reregister'));

        expect(callCount, 1);
        expect(replacementCalled, isTrue);

        await replacementSub.cancel();

        // After both subscriptions are canceled, emit should be a no-op.
        final result = await bus.emit<EventA>(event: EventA('x'));
        expect(result.stopped, isFalse);
        expect(callCount, 1);
      },
    );

    test(
      'cancelling last id handler preserves type bucket if general handlers exist',
      () async {
        var generalCalled = false;
        bus.on<String>((event) {
          generalCalled = true;
        });
        final idSub = bus.on<String>((event) {}, identifier: 'agent1');

        await idSub.cancel();

        await bus.emit<String>(event: 'test');
        expect(generalCalled, isTrue);
      },
    );

    test(
      'cancelling last general handler preserves type bucket if id handlers exist',
      () async {
        var idCalled = false;
        bus.on<String>((event) {
          idCalled = true;
        }, identifier: 'agent1');
        final generalSub = bus.on<String>((event) {});

        await generalSub.cancel();

        await bus.emit<String>(event: 'test', identifier: 'agent1');
        expect(idCalled, isTrue);
      },
    );

    test(
      'handler that cancels itself during dispatch does not throw',
      () async {
        // Regression: emit/emitSync must iterate a snapshot, not the live
        // bucket. Self-cancel during dispatch otherwise hits
        // ConcurrentModificationError because cancel() removes the handler
        // from the same list emit is iterating over.
        var firstCount = 0;
        var secondCount = 0;
        late EventSubscription first;
        first = bus.on<EventA>((event) {
          firstCount++;
          first.cancel();
        });
        bus.on<EventA>((event) {
          secondCount++;
        });

        await bus.emit<EventA>(event: EventA('one'));
        expect(firstCount, 1);
        expect(secondCount, 1, reason: 'second handler must still run');

        await bus.emit<EventA>(event: EventA('two'));
        expect(
          firstCount,
          1,
          reason: 'self-cancelled handler must not re-fire',
        );
        expect(secondCount, 2);
      },
    );

    test(
      'sync handler that cancels another handler during dispatch does not throw',
      () {
        // Same regression as above but via emitSync.
        late EventSubscription victim;
        var aRan = false;
        var bRan = false;
        bus.on<EventA>((event) {
          aRan = true;
          victim.cancel();
        });
        victim = bus.on<EventA>((event) {
          bRan = true;
        });

        bus.emitSync<EventA>(event: EventA('x'));
        expect(aRan, isTrue);
        // The victim was already enqueued in the snapshot for THIS dispatch,
        // so it still runs once. The next emit will skip it.
        expect(bRan, isTrue);

        bRan = false;
        bus.emitSync<EventA>(event: EventA('y'));
        expect(bRan, isFalse, reason: 'cancelled handler must not re-fire');
      },
    );

    test(
      'bind callback that cancels itself during dispatch does not throw',
      () async {
        // Regression A2: emit/emitSync iterate _eventBindings directly. A
        // bind callback whose body invokes its own cancel closure mid-cascade
        // must not ConcurrentModificationError. Snapshot iteration is the
        // fix.
        var sawCount = 0;
        late void Function() cancel;
        cancel = bus.bind((_) {
          sawCount++;
          cancel();
        });
        bus.bind((_) {
          sawCount++;
        });

        await bus.emit<EventA>(event: EventA('async'));
        // The self-cancelling bind ran once; the second bind ran once.
        expect(sawCount, 2);

        sawCount = 0;
        bus.emitSync<EventA>(event: EventA('sync'));
        // Self-cancelled bind is gone; second bind still fires.
        expect(sawCount, 1);
      },
    );

    test(
      'handler that cancels itself during identifier-scoped dispatch does not throw',
      () async {
        // Identifier-scoped path goes through _mergePrioritized's other
        // empty-input branch (a.isEmpty + non-empty b). Same regression.
        var count = 0;
        late EventSubscription sub;
        sub = bus.on<EventA>((event) {
          count++;
          sub.cancel();
        }, identifier: 'agent1');

        await bus.emit<EventA>(event: EventA('first'), identifier: 'agent1');
        expect(count, 1);

        await bus.emit<EventA>(event: EventA('second'), identifier: 'agent1');
        expect(count, 1, reason: 'cancelled handler must not re-fire');
      },
    );
  });

  // ===========================================================================
  // EventSubscription: cancel-only handle returned by every on* method
  // ===========================================================================
  group('EventSubscription', () {
    test('cancel() removes the handler from the bus', () async {
      var count = 0;
      final sub = bus.on<String>((event) => count++);
      await bus.emit<String>(event: 'a');
      expect(count, 1);
      await sub.cancel();
      await bus.emit<String>(event: 'b');
      expect(count, 1, reason: 'cancelled handler must not fire');
    });

    test('cancel() is idempotent', () async {
      final sub = bus.on<String>((event) {});
      await sub.cancel();
      await sub.cancel(); // must not throw or double-remove
    });
  });

  // ===========================================================================
  // emit(): general behavior
  // ===========================================================================
  group('emit()', () {
    test('returns wrapped event when no handlers registered', () async {
      final result = await bus.emit<String>(event: 'test');
      expect(result.event, 'test');
      expect(result.stopped, isFalse);
    });

    test('passes identifier through to response', () async {
      final result = await bus.emit<String>(event: 'test', identifier: 'my-id');
      expect(result.identifier, 'my-id');
    });

    test('wraps event in an EventEnvelope', () async {
      EventEnvelope? captured;
      bus.on<String>((e) {
        captured = e;
      });
      await bus.emit<String>(event: 'test');
      expect(captured, isA<EventEnvelope<String>>());
    });
  });

  // ===========================================================================
  // emitInternal()
  // ===========================================================================
  group('emitInternal()', () {
    test('does NOT trigger bind callbacks', () async {
      var bindCalled = false;
      bus.bind((e) => bindCalled = true);
      bus.on<String>((event) {});

      await bus.emitInternal<String>(event: 'secret');
      expect(bindCalled, isFalse);
    });

    test('still dispatches to on() handlers', () async {
      var handlerCalled = false;
      bus.on<String>((event) {
        handlerCalled = true;
      });

      await bus.emitInternal<String>(event: 'internal');
      expect(handlerCalled, isTrue);
    });
  });

  // ===========================================================================
  // bind()
  // ===========================================================================
  group('bind()', () {
    test('callback receives all non-internal events', () async {
      final seen = <String>[];
      bus.bind((e) => seen.add(e.event as String));
      bus.on<String>((event) {});

      await bus.emit<String>(event: 'first');
      await bus.emit<String>(event: 'second');
      expect(seen, ['first', 'second']);
    });

    test('multiple bind callbacks all get called', () async {
      var count1 = 0, count2 = 0;
      bus.bind((_) => count1++);
      bus.bind((_) => count2++);
      bus.on<String>((event) {});

      await bus.emit<String>(event: 'test');
      expect(count1, 1);
      expect(count2, 1);
    });

    test('unbind removes the callback', () async {
      var callCount = 0;
      final unbind = bus.bind((_) => callCount++);
      bus.on<String>((event) {});

      await bus.emit<String>(event: 'first');
      expect(callCount, 1);

      unbind();
      await bus.emit<String>(event: 'second');
      expect(callCount, 1);
    });

    test('bind is called before handlers', () async {
      final order = <String>[];
      bus.bind((_) => order.add('bind'));
      bus.on<String>((event) {
        order.add('handler');
      });

      await bus.emit<String>(event: 'test');
      expect(order, ['bind', 'handler']);
    });
  });

  // ===========================================================================
  // onRequest / request: async request/response
  // ===========================================================================
  group('onRequest / request', () {
    test('handler receives request and returns response', () async {
      bus.onRequest<SearchQuery, SearchResults>((req) async {
        return SearchResults(['result for ${req.event.query}']);
      });

      final results = await bus.request<SearchQuery, SearchResults>(
        SearchQuery('dart'),
      );
      expect(results.results, ['result for dart']);
    });

    test('throws when no handler is registered', () async {
      expect(
        () => bus.request<SearchQuery, SearchResults>(SearchQuery('x')),
        throwsA(isA<RequestUnavailableException>()),
      );
    });

    test(
      'throws when handlers exist for identifier but merged list is empty for different identifier',
      () async {
        // Register a handler scoped to 'agent1' only
        bus.onRequest<String, String>(
          (req) async => 'ok',
          identifier: 'agent1',
        );

        // Request with 'agent2': same type key exists in _handlers, but
        // merged list for 'agent2' is empty (no general, no agent2-scoped)
        expect(
          () => bus.request<String, String>('query', identifier: 'agent2'),
          throwsA(isA<RequestUnavailableException>()),
        );
      },
    );

    test('priority ordering works for request handlers', () async {
      bus.onRequest<String, String>((req) async {
        return 'low-priority';
      }, priority: 0);
      bus.onRequest<String, String>((req) async {
        return 'high-priority';
      }, priority: 10);

      final result = await bus.request<String, String>('query');
      // Priority 10 runs first under descending dispatch, returns non-null,
      // so it wins.
      expect(result, 'high-priority');
    });

    test('identifier-scoped request handler works', () async {
      bus.onRequest<String, String>((req) async {
        return 'scoped-result';
      }, identifier: 'agent1');

      final result = await bus.request<String, String>(
        'query',
        identifier: 'agent1',
      );
      expect(result, 'scoped-result');
    });

    test('request cancellation removes handler', () async {
      final sub = bus.onRequest<String, String>((req) async => 'result');
      await sub.cancel();

      expect(
        () => bus.request<String, String>('query'),
        throwsA(isA<RequestUnavailableException>()),
      );
    });

    test(
      'handler cascade: first non-null return wins, lower-priority not called',
      () async {
        var handler2Called = false;
        bus.onRequest<String, String>(
          (req) async => 'handler1-wins',
          priority: 10,
        );
        bus.onRequest<String, String>((req) async {
          handler2Called = true;
          return 'handler2';
        }, priority: 0);

        final result = await bus.request<String, String>('query');
        expect(result, 'handler1-wins');
        expect(handler2Called, isFalse);
      },
    );

    test('type mismatch: no matching generic types throws', () async {
      // Register an int->int handler but query string->string
      bus.onRequest<int, int>((req) async => 42);
      expect(
        () => bus.request<String, String>('query'),
        throwsA(isA<RequestUnavailableException>()),
      );
    });

    test(
      'nullable Response with all handlers returning null returns null',
      () async {
        bus.onRequest<String, String?>((req) async => null, priority: 0);
        bus.onRequest<String, String?>((req) async => null, priority: 10);

        final result = await bus.request<String, String?>('query');
        expect(result, isNull);
      },
    );
  });

  // ===========================================================================
  // onRequestSync / requestSync
  // ===========================================================================
  group('onRequestSync / requestSync', () {
    test('sync handler returns immediately', () {
      bus.onRequestSync<String, int>((req) {
        return req.event.length;
      });

      final result = bus.requestSync<String, int>('hello');
      expect(result, 5);
    });

    test('throws RequestUnavailableException when no handler registered', () {
      expect(
        () => bus.requestSync<String, int>('hello'),
        throwsA(isA<RequestUnavailableException>()),
      );
    });

    test(
      'throws RequestUnavailableException when handlers exist but merged list is empty for identifier',
      () {
        // Register a handler scoped to 'agent1' only
        bus.onRequestSync<String, int>((req) => 42, identifier: 'agent1');

        // Request with 'agent2': same type key exists in _handlers, but
        // merged list for 'agent2' is empty (no general, no agent2-scoped)
        expect(
          () => bus.requestSync<String, int>('hello', identifier: 'agent2'),
          throwsA(isA<RequestUnavailableException>()),
        );
      },
    );

    test('throws StateError if handler returns a Future', () {
      // Register an async handler via onRequest (not onRequestSync)
      bus.onRequest<String, String>((req) async => 'async-result');

      expect(() => bus.requestSync<String, String>('hello'), throwsStateError);
    });

    test('priority ordering works', () {
      bus.onRequestSync<String, String>((req) => 'low', priority: 0);
      bus.onRequestSync<String, String>((req) => 'high', priority: 10);

      // Descending dispatch: priority 10 runs first, returns non-null, wins.
      expect(bus.requestSync<String, String>('query'), 'high');
    });

    test('identifier scoping works', () {
      bus.onRequestSync<String, String>(
        (req) => 'scoped',
        identifier: 'agent1',
      );

      expect(
        bus.requestSync<String, String>('query', identifier: 'agent1'),
        'scoped',
      );
    });

    test('type mismatch throws RequestUnavailableException', () {
      bus.onRequestSync<int, int>((req) => 42);

      expect(
        () => bus.requestSync<String, String>('query'),
        throwsA(isA<RequestUnavailableException>()),
      );
    });

    test('nullable Response with all null returns works', () {
      bus.onRequestSync<String, String?>((req) => null);

      final result = bus.requestSync<String, String?>('query');
      expect(result, isNull);
    });
  });

  // ===========================================================================
  // maybeRequest
  // ===========================================================================
  group('maybeRequest()', () {
    test('returns result on success', () async {
      bus.onRequest<String, String>((req) async => 'ok');

      final result = await bus.maybeRequest<String, String>('query');
      expect(result, 'ok');
    });

    test('returns null when no handler registered', () async {
      final result = await bus.maybeRequest<String, String>('query');
      expect(result, isNull);
    });

    test('propagates handler error', () async {
      bus.onRequest<String, String>((req) async => throw Exception('boom'));

      await expectLater(
        bus.maybeRequest<String, String>('query'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ===========================================================================
  // maybeRequestSync
  // ===========================================================================
  group('maybeRequestSync()', () {
    test('returns result on success', () {
      bus.onRequestSync<String, int>((req) => 42);

      final result = bus.maybeRequestSync<String, int>('query');
      expect(result, 42);
    });

    test('returns null when no handler registered', () {
      final result = bus.maybeRequestSync<String, int>('query');
      expect(result, isNull);
    });

    test('propagates handler error', () {
      bus.onRequestSync<String, int>((req) => throw Exception('boom'));

      expect(
        () => bus.maybeRequestSync<String, int>('query'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ===========================================================================
  // hasRequestHandler
  // ===========================================================================
  group('hasRequestHandler()', () {
    test('returns false when nothing registered', () {
      expect(bus.hasRequestHandler<String, int>(), isFalse);
    });

    test('returns true when handler registered', () {
      bus.onRequest<String, int>((req) async => 42);
      expect(bus.hasRequestHandler<String, int>(), isTrue);
    });

    test('returns false after handler cancelled', () {
      final sub = bus.onRequest<String, int>((req) async => 42);
      sub.cancel();
      expect(bus.hasRequestHandler<String, int>(), isFalse);
    });

    test('identifier-scoped check', () {
      bus.onRequest<String, int>((req) async => 42, identifier: 'agent1');

      expect(bus.hasRequestHandler<String, int>(), isFalse);
      expect(bus.hasRequestHandler<String, int>(identifier: 'agent1'), isTrue);
    });

    test('returns false for wrong type pair', () {
      bus.onRequest<String, int>((req) async => 42);
      expect(bus.hasRequestHandler<int, String>(), isFalse);
    });
  });

  // ===========================================================================
  // _mergedHandlers: merge sort behavior
  // ===========================================================================
  group('merged handler ordering', () {
    test('interleaves general and scoped handlers by priority', () async {
      final order = <String>[];

      bus.on<String>((event) {
        order.add('g-0');
      }, priority: 0);
      bus.on<String>(
        (event) {
          order.add('s-5');
        },
        priority: 5,
        identifier: 'a',
      );
      bus.on<String>((event) {
        order.add('g-10');
      }, priority: 10);
      bus.on<String>(
        (event) {
          order.add('s-15');
        },
        priority: 15,
        identifier: 'a',
      );
      bus.on<String>((event) {
        order.add('g-20');
      }, priority: 20);

      await bus.emit<String>(event: 'test', identifier: 'a');
      // Descending: higher priority runs first across both buckets.
      expect(order, ['g-20', 's-15', 'g-10', 's-5', 'g-0']);
    });

    test('only general handlers run when no identifier provided', () async {
      final order = <String>[];

      bus.on<String>((event) {
        order.add('general');
      });
      bus.on<String>((event) {
        order.add('scoped');
      }, identifier: 'agent1');

      await bus.emit<String>(event: 'test');
      expect(order, ['general']);
    });

    test('only scoped handlers when no general handlers exist', () async {
      var called = false;
      bus.on<String>((event) {
        called = true;
      }, identifier: 'agent1');

      await bus.emit<String>(event: 'test', identifier: 'agent1');
      expect(called, isTrue);
    });
  });

  // ===========================================================================
  // Edge cases and integration
  // ===========================================================================
  group('edge cases', () {
    test('emit with no handlers is a no-op', () async {
      final result = await bus.emit<String>(event: 'lonely');
      expect(result.event, 'lonely');
      expect(result.stopped, isFalse);
    });

    test(
      'emit with identifier but no scoped handlers only runs general',
      () async {
        var generalCalled = false;
        bus.on<String>((event) {
          generalCalled = true;
        });

        await bus.emit<String>(event: 'test', identifier: 'no-such-scope');
        expect(generalCalled, isTrue);
      },
    );

    test('handler can be async', () async {
      String? result;
      bus.on<String>((event) async {
        await Future.delayed(Duration(milliseconds: 10));
        result = event.event;
      });

      await bus.emit<String>(event: 'async-test');
      expect(result, 'async-test');
    });

    test('multiple emit calls are independent', () async {
      final received = <String>[];
      bus.on<String>((event) {
        received.add(event.event);
      });

      await bus.emit<String>(event: 'first');
      await bus.emit<String>(event: 'second');
      await bus.emit<String>(event: 'third');
      expect(received, ['first', 'second', 'third']);
    });

    test('cancelling between emits removes handler', () async {
      var callCount = 0;
      final sub = bus.on<String>((event) {
        callCount++;
      });

      await bus.emit<String>(event: 'test');
      expect(callCount, 1);

      // Cancel between emits (not during iteration)
      await sub.cancel();

      await bus.emit<String>(event: 'test2');
      expect(callCount, 1);
    });

    test(
      'request with identifier that has scoped and general handlers merges',
      () async {
        bus.onRequest<String, String?>((req) async => null, priority: 0);
        bus.onRequest<String, String?>(
          (req) async => 'from-scoped',
          priority: 10,
          identifier: 'a',
        );

        final result = await bus.request<String, String?>('q', identifier: 'a');
        expect(result, 'from-scoped');
      },
    );

    test('onRequestSync cancellation works', () {
      final sub = bus.onRequestSync<String, int>((req) => 42);
      sub.cancel();
      expect(
        () => bus.requestSync<String, int>('q'),
        throwsA(isA<RequestUnavailableException>()),
      );
    });

    test('hasRequestHandler with empty identifier list', () {
      // Register a general handler, then check for a non-existent identifier
      bus.onRequest<String, int>((req) async => 42);
      // Checking an identifier that has no handlers: this will
      // putIfAbsent an empty list for that identifier
      expect(bus.hasRequestHandler<String, int>(identifier: 'new-id'), isFalse);
    });

    test('handler exception during emit propagates to caller', () async {
      // Higher-priority handler runs first and throws; lower-priority
      // handler must NOT run because the exception propagates.
      bus.on<String>((event) {
        throw StateError('handler exploded');
      }, priority: 10);

      var secondHandlerCalled = false;
      bus.on<String>((event) {
        secondHandlerCalled = true;
      }, priority: 0);

      expect(() => bus.emit<String>(event: 'test'), throwsStateError);
      expect(secondHandlerCalled, isFalse);
    });

    test('double cancel of a subscription is safe', () async {
      final sub = bus.on<String>((event) {});
      await expectLater(sub.cancel(), completes);
      // Second cancel should be a no-op (remove returns false, no crash).
      await expectLater(sub.cancel(), completes);
    });

    test('bind callback receives events of multiple different types', () async {
      final types = <Type>[];
      bus.bind((e) => types.add(e.event.runtimeType));

      bus.on<String>((event) {});
      bus.on<int>((event) {});
      bus.on<EventA>((event) {});

      await bus.emit<String>(event: 'hello');
      await bus.emit<int>(event: 42);
      await bus.emit<EventA>(event: EventA('x'));

      expect(types, [String, int, EventA]);
    });

    test('multiple identifier scopes are isolated from each other', () async {
      final agent1Calls = <String>[];
      final agent2Calls = <String>[];
      final generalCalls = <String>[];

      bus.on<String>((event) {
        generalCalls.add(event.event);
      });
      bus.on<String>((event) {
        agent1Calls.add(event.event);
      }, identifier: 'agent1');
      bus.on<String>((event) {
        agent2Calls.add(event.event);
      }, identifier: 'agent2');

      await bus.emit<String>(event: 'to-agent1', identifier: 'agent1');
      await bus.emit<String>(event: 'to-agent2', identifier: 'agent2');

      expect(agent1Calls, ['to-agent1']);
      expect(agent2Calls, ['to-agent2']);
      // General handlers see both
      expect(generalCalls, ['to-agent1', 'to-agent2']);
    });

    test(
      'same-priority general handler runs before scoped handler in merge',
      () async {
        final order = <String>[];

        bus.on<String>((event) {
          order.add('general');
        }, priority: 5);
        bus.on<String>(
          (event) {
            order.add('scoped');
          },
          priority: 5,
          identifier: 'a',
        );

        await bus.emit<String>(event: 'test', identifier: 'a');
        // At equal priority, general list comes first due to >= in merge.
        expect(order, ['general', 'scoped']);
      },
    );

    test(
      'first handler in dispatch order stopping prevents all subsequent handlers',
      () async {
        var handler2Called = false;
        var handler3Called = false;

        // Highest priority runs FIRST under descending dispatch. It stops
        // the cascade; neither of the lower-priority handlers should run.
        bus.on<String>((e) async => e.stop('intercepted'), priority: 20);
        bus.on<String>((e) async {
          handler2Called = true;
          e.stop('also-non-null');
          return;
        }, priority: 10);
        bus.on<String>((e) async {
          handler3Called = true;
        }, priority: 0);

        final result = await bus.emit<String>(event: 'test');
        expect(result.event, 'intercepted');
        expect(result.stopped, isTrue);
        expect(handler2Called, isFalse);
        expect(handler3Called, isFalse);
      },
    );

    test(
      'request throws when scoped handler exists but queried identifier has none',
      () async {
        // This tests the merged.isEmpty path specifically:
        // handlers exist in _handlers for the type key (because agent1 registered),
        // but merged list for agent2 is empty
        bus.onRequest<String, String>(
          (req) async => 'ok',
          identifier: 'agent1',
        );

        expect(
          () => bus.request<String, String>('q', identifier: 'agent2'),
          throwsA(isA<Exception>()),
        );
      },
    );
  });

  // ===========================================================================
  // Post-dispose guards
  // ===========================================================================
  group('Post-dispose guards', () {
    test('emit on disposed bus throws StateError', () async {
      final disposedBus = EventBus();
      disposedBus.dispose();

      expect(
        () => disposedBus.emit<EventA>(event: EventA('hello')),
        throwsA(isA<StateError>()),
      );
    });

    test('on() registration on disposed bus throws StateError', () async {
      final disposedBus = EventBus();
      disposedBus.dispose();

      expect(() => disposedBus.on<EventA>((e) {}), throwsA(isA<StateError>()));
    });

    test('all mutating/dispatching methods throw on disposed bus', () {
      final bus = EventBus();
      bus.dispose();

      expect(() => bus.bind((_) {}), throwsA(isA<StateError>()));
      expect(() => bus.onSync<EventA>((_) {}), throwsA(isA<StateError>()));
      expect(
        () => bus.request<SearchQuery, SearchResults>(SearchQuery('q')),
        throwsA(isA<StateError>()),
      );
      expect(
        () => bus.maybeRequest<SearchQuery, SearchResults>(SearchQuery('q')),
        throwsA(isA<StateError>()),
      );
      expect(
        () => bus.onRequest<SearchQuery, SearchResults>(
          (_) async => SearchResults([]),
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => bus.requestSync<SearchQuery, SearchResults>(SearchQuery('q')),
        throwsA(isA<StateError>()),
      );
      expect(
        () =>
            bus.maybeRequestSync<SearchQuery, SearchResults>(SearchQuery('q')),
        throwsA(isA<StateError>()),
      );
      expect(
        () => bus.onRequestSync<SearchQuery, SearchResults>(
          (_) => SearchResults([]),
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => bus.emitSync<EventA>(event: EventA('x')),
        throwsA(isA<StateError>()),
      );
    });
  });
}
