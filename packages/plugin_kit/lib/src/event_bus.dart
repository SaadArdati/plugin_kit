library;

import 'dart:async';

import 'package:plugin_kit/plugin_kit.dart';

/// Cancel-only handle returned by [EventBus.on], [EventBus.onSync],
/// [EventBus.onRequest], and [EventBus.onRequestSync].
///
/// Distinct from [EventBinding] (which is a declarative descriptor used
/// before the subscription is materialized). An [EventSubscription] is
/// the live token returned AFTER a handler has been attached; cancel it
/// to remove the handler.
///
/// Bus subscriptions are not backed by a Dart [Stream] and don't support
/// backpressure, data callbacks, or `asFuture`. Modelling them as a
/// dedicated handle avoids the previous fragility of returning a
/// [StreamSubscription] whose non-cancel methods all threw at runtime.
abstract interface class EventSubscription {
  /// Cancel the subscription. Idempotent: calling cancel twice is a no-op
  /// after the first removes the handler.
  Future<void> cancel();
}

/// Wrapper around an event payload passed to each handler during dispatch.
///
/// Handlers can read [event], mutate it for downstream handlers, or call
/// [stop] to halt propagation and set the final result.
///
/// ```dart
/// final res = await bus.emit<UserMessage>(
///   event: UserMessage(text: 'Hello'),
/// );
/// if (res.stopped) print('Stopped with: ${res.event}');
/// ```
class EventEnvelope<T> {
  /// Optional identifier for scoped event dispatch.
  ///
  /// When non-null, the event bus merges both general handlers and
  /// identifier-specific handlers during dispatch.
  final String? identifier;

  /// The event payload. May be mutated by handlers during dispatch.
  T event;

  /// Whether the event processing was stopped early.
  bool _stopped = false;

  /// Whether a handler called [stop] to halt the cascade.
  bool get stopped => _stopped;

  /// Creates an envelope for [event] with optional scoped [identifier].
  EventEnvelope({required this.event, required this.identifier});

  /// Stop event processing and set the final result.
  ///
  /// After calling this, no further handlers will be invoked and the
  /// [event] field is set to [value], which the emitter receives as
  /// the result.
  void stop(T value) {
    event = value;
    _stopped = true;
  }
}

/// Handler function for events of type [T].
///
/// Receives an [EventEnvelope] wrapping the payload. Handlers may:
/// - read the payload via `e.event`,
/// - mutate it in place (downstream handlers see the change), and
/// - call [EventEnvelope.stop] to halt the cascade and set the final result.
///
/// Handlers return void. To short-circuit the cascade with a replacement
/// value, call `e.stop(value)`.
typedef EventHandler<T> = FutureOr<void> Function(EventEnvelope<T> e);

/// Synchronous handler function for events of type [T].
///
/// Like [EventHandler] but guaranteed to return synchronously.
/// Used with [EventBus.onSync] and safe to invoke via [EventBus.emitSync].
typedef SyncEventHandler<T> = void Function(EventEnvelope<T> e);

/// Handler function for request/response communication on an [EventBus].
///
/// Receives the request wrapped in an [EventEnvelope]. Returns a value
/// of type [Response] to claim the request, or `null` to concede so the
/// next handler in priority order can claim. Concession by `null` is
/// supported regardless of whether [Response] is itself nullable.
///
/// Throwing from a handler signals a real error. The chain stops and
/// the original exception propagates to the caller. Do not throw to
/// express concession; return `null`. The framework never converts a
/// throw into a "try the next handler" signal.
///
/// See [EventBus.onRequest] for handler registration, and
/// [EventBus.request] / [EventBus.maybeRequest] for the consumer-side
/// semantics (especially which method to choose when concession is a
/// valid outcome at the call site).
typedef RequestHandler<Request, Response> =
    FutureOr<Response?> Function(EventEnvelope<Request> e);

/// Synchronous handler function for request/response communication.
///
/// Like [RequestHandler] but guaranteed to return synchronously.
/// Used with [EventBus.onRequestSync] and [EventBus.requestSync].
/// Same concession-by-`null` and throw-stops-chain rules apply: returning
/// `null` concedes to the next handler regardless of whether [Response]
/// is nullable; throwing stops the chain and propagates.
typedef SyncRequestHandler<Request, Response> =
    Response? Function(EventEnvelope<Request> e);

/// Callback for observing all non-internal events emitted on the bus.
///
/// Registered via [EventBus.bind]. Called before handler dispatch.
typedef EventBindingCallback = void Function(EventEnvelope<dynamic> event);

/// Typed, priority-ordered event bus for decoupled inter-plugin
/// communication.
///
/// Events are dispatched by Dart type (`T`); handlers run in descending
/// priority order (higher numbers first), so the highest-priority handler
/// intercepts before lower-priority handlers see the event. A handler can
/// stop dispatch by calling [EventEnvelope.stop] with a final result.
/// Events optionally carry an [identifier] (an agent id, etc.); both
/// general and identifier-specific handlers merge during dispatch.
///
/// [onRequest]/[request] provide typed RPC-style communication, while
/// [bind] observes every non-internal event for logging, debugging, or
/// analytics.
///
/// ```dart
/// final sub = bus.on<UserMessage>(
///   (e) async {
///     final response = await processMessage(e.event.text);
///     e.stop(response);
///   },
///   priority: 10,
/// );
///
/// final result = await bus.emit<UserMessage>(
///   event: UserMessage(text: 'Hello'),
/// );
///
/// bus.onRequest<SearchQuery, SearchResults>((req) async {
///   return await search(req.event.query);
/// });
/// final results = await bus.request<SearchQuery, SearchResults>(
///   SearchQuery(query: 'dart patterns'),
/// );
/// ```
///
/// Priority convention: higher runs first. A handler at
/// `Priority.elevated` (1000) runs before one at `Priority.normal` (500).
/// Matches [ServiceRegistry]: in both subsystems, higher numbers mean more
/// authority. The highest-priority handler intercepts first and can mutate
/// or stop the cascade before lower-priority handlers see the event.
///
/// Use [Priority]'s named stops (`Priority.normal`, `Priority.elevated`, …)
/// for discoverable values and `Priority.above(other)` for relative
/// positioning. Raw integers work too. Default priority is
/// `Priority.normal`.
///
/// Each [PluginSession] owns its own event bus instance. When the session
/// is disposed, [dispose] clears all handlers and bindings. For
/// [StatefulPluginService]s, subscriptions are tracked and cancelled
/// automatically on detach.
class EventBus {
  /// Callbacks registered via [bind] to observe all emitted events.
  final List<EventBindingCallback> _eventBindings = <EventBindingCallback>[];

  /// Bind a callback to receive every non-internal event emitted on this bus.
  ///
  /// Returns a function that removes the binding when called.
  void Function() bind(EventBindingCallback callback) {
    _checkNotDisposed();
    _eventBindings.add(callback);
    return () => _eventBindings.remove(callback);
  }

  /// Registered event handlers, keyed by the event `Type`.
  ///
  /// The value at key `T` is always an `_EventBuckets<T>`: invariant
  /// maintained by [on]. Handlers within a bucket are priority-sorted.
  ///
  /// Using `Type` objects (rather than `T.toString()`) as map keys is safe
  /// across all Dart compilation targets including dart2js with minification,
  /// because `Type` equality and `hashCode` are canonicalized by the runtime
  /// independently of string representation.
  final Map<Type, Object> _eventHandlers = <Type, Object>{};

  /// Registered request handlers, keyed by the `(Request, Response)` type pair.
  ///
  /// The value at key `(R, S)` is always a `_RequestBuckets<R, S>`:
  /// invariant maintained by [onRequest].
  final Map<(Type, Type), Object> _requestHandlers = <(Type, Type), Object>{};

  /// Whether this bus has been disposed.
  bool _isDisposed = false;

  /// Whether this bus has been disposed.
  bool get isDisposed => _isDisposed;

  /// Dispose this bus by clearing all registered handlers and bindings.
  void dispose() {
    _eventHandlers.clear();
    _requestHandlers.clear();
    _eventBindings.clear();
    _isDisposed = true;
  }

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw StateError('Cannot use a disposed EventBus.');
    }
  }

  /// Register a handler for events of type [T].
  ///
  /// The handler receives an [EventEnvelope] wrapping the payload. It may
  /// mutate `e.event` (downstream handlers see the change) and call
  /// [EventEnvelope.stop] to halt the cascade and set the final result.
  ///
  /// Handlers are dispatched in descending priority order (higher numbers
  /// first), matching [ServiceRegistry] resolution. When [identifier] is
  /// supplied, identifier-scoped handlers merge with general handlers in
  /// the same priority-ordered sequence.
  EventSubscription on<T>(
    EventHandler<T> handler, {
    int priority = Priority.normal,
    String? identifier,
  }) {
    _checkNotDisposed();
    final buckets =
        _eventHandlers.putIfAbsent(T, _EventBuckets<T>.new) as _EventBuckets<T>;
    final List<_EventEntry<T>> list = identifier == null
        ? buckets.general
        : buckets.byId.putIfAbsent(identifier, () => <_EventEntry<T>>[]);

    final entry = _EventEntry<T>(priority: priority, run: handler);
    list.add(entry);
    if (identifier == null) {
      buckets.markGeneralDirty();
    } else {
      buckets.markIdDirty(identifier);
    }

    return _EventHandlerSub(
      onCancel: () {
        list.remove(entry);
        if (list.isEmpty) {
          if (identifier == null) {
            if (buckets.byId.isEmpty) _eventHandlers.remove(T);
          } else {
            buckets.removeIdBucket(identifier);
            if (buckets.byId.isEmpty && buckets.general.isEmpty) {
              _eventHandlers.remove(T);
            }
          }
        }
      },
    );
  }

  /// Register a synchronous handler for events of type [T].
  ///
  /// Like [on] but enforces at compile time that the handler returns
  /// synchronously. Handlers registered this way are safe to invoke via
  /// [emitSync] (they cannot return a [Future]).
  ///
  /// ```dart
  /// bus.onSync<UserMessage>((e) {
  ///   if (e.event.isSpam) e.stop(MessageBlocked());
  /// });
  /// ```
  EventSubscription onSync<T>(
    SyncEventHandler<T> handler, {
    int priority = Priority.normal,
    String? identifier,
  }) {
    // Wrap the sync handler as a FutureOr handler so it shares the same
    // internal storage. emitSync will verify the result is not a Future.
    return on<T>(
      (event) => handler(event),
      priority: priority,
      identifier: identifier,
    );
  }

  /// Check if there is at least one handler registered for the given
  /// request/response type pair.
  ///
  /// If [identifier] is provided, checks for handlers registered under that
  /// identifier; otherwise checks for general handlers.
  bool hasRequestHandler<Request, Response>({String? identifier}) {
    final raw = _requestHandlers[(Request, Response)];
    if (raw == null) return false;
    final buckets = raw as _RequestBuckets<Request, Response>;
    final list = identifier == null
        ? buckets.general
        : buckets.byId[identifier];
    return list != null && list.isNotEmpty;
  }

  /// Send a typed request and walk registered handlers in priority order
  /// until one claims it.
  ///
  /// Prefer [maybeRequest] over this method when concession is a valid
  /// outcome at your call site. `request` is the assertion variant: it
  /// throws if the chain bottoms out without an answer. Use it only when
  /// the caller has guaranteed (by construction, by invariant, by
  /// registration order) that at least one handler will claim. If that
  /// guarantee ever breaks, the thrown exception surfaces the violation
  /// loudly, which is the assertion's purpose.
  ///
  /// For chains where the answer can legitimately be "no one could
  /// handle this," reach for [maybeRequest]: it returns `null` for the
  /// same case and propagates handler-thrown exceptions unchanged, so
  /// real errors and "no answer" remain distinguishable.
  ///
  /// Dispatch model (mirrors [emit]):
  ///
  ///   * General handlers and `identifier`-scoped handlers are merged
  ///     into a single descending-priority sequence (higher priority
  ///     number runs first).
  ///   * Each handler is invoked with the wrapped request. A handler
  ///     claims the call by returning a non-null [Response]; dispatch
  ///     stops and that value is returned.
  ///   * A handler concedes by returning `null`. Dispatch continues to
  ///     the next handler.
  ///   * A handler that throws stops dispatch immediately; the original
  ///     exception propagates to this method's caller. Subsequent
  ///     handlers do not run.
  ///
  /// Throws:
  /// - [RequestNotWiredException] if no handler is registered for the
  ///   `(Request, Response)` type pair, or no handler matched the
  ///   requested [identifier]. Wire a handler with [onRequest].
  /// - [AllConcededException] if every handler ran and returned `null`
  ///   and [Response] is non-nullable. The exception message recommends
  ///   switching to [maybeRequest]. When [Response] is nullable, this
  ///   method returns `null` instead of throwing.
  /// - Any exception a handler raised, unwrapped.
  ///
  /// Example (asserted-success case):
  /// ```dart
  /// // The runtime always registers a fallback CompletionProvider, so
  /// // we assert at least one handler will claim. If that assumption
  /// // breaks, AllConcededException tells us our setup is wrong.
  /// final results = await bus.request<SearchQuery, SearchResults>(
  ///   SearchQuery(query: 'dart patterns'),
  /// );
  /// ```
  Future<Response> request<Request, Response>(
    Request request, {
    String? identifier,
  }) async {
    _checkNotDisposed();
    final raw = _requestHandlers[(Request, Response)];
    if (raw == null) {
      throw RequestNotWiredException(
        requestType: Request,
        responseType: Response,
        identifier: identifier,
      );
    }
    final buckets = raw as _RequestBuckets<Request, Response>;

    buckets.ensureGeneralSorted();
    buckets.ensureIdSorted(identifier);
    final merged = _mergePrioritized(buckets.general, buckets.byId[identifier]);
    if (merged.isEmpty) {
      throw RequestNotWiredException(
        requestType: Request,
        responseType: Response,
        identifier: identifier,
        wasIdentifierMismatch: true,
      );
    }

    final wrapped = EventEnvelope<Request>(
      event: request,
      identifier: identifier,
    );

    Response? lastResponse;
    for (final entry in merged) {
      final response = await entry.run(wrapped);
      lastResponse = response;
      if (response != null) return response;
    }

    if (null is Response) return lastResponse as Response;
    throw AllConcededException(
      requestType: Request,
      responseType: Response,
      identifier: identifier,
    );
  }

  /// Send a typed request and return `null` when the chain produced no
  /// answer.
  ///
  /// The canonical method for chains where concession is a valid outcome.
  /// Walks the same priority-ordered handler list as [request], with one
  /// critical difference at the consumer's call site:
  ///
  /// - First non-null handler response is returned (as `Future<Response>`
  ///   inside the nullable wrapper).
  /// - No handler registered, or no handler matched [identifier], or
  ///   every handler conceded, returns `null`.
  /// - Handler threw: original exception propagates. `maybeRequest`
  ///   does NOT swallow handler exceptions; it catches only the
  ///   framework's own [NoRequestAnswerException] subtypes
  ///   ([RequestNotWiredException] and [AllConcededException]).
  ///
  /// This preserves the distinction between "no one could answer"
  /// (returned as `null`) and "a handler had a real failure"
  /// (propagated as the original exception type). A typical consumer:
  ///
  /// ```dart
  /// try {
  ///   final visa = await bus.maybeRequest<AgentBoardingCall, ModelVisa>(
  ///     AgentBoardingCall(passport),
  ///   );
  ///   if (visa == null) {
  ///     // No provider could serve this passport; normal flow.
  ///     return _refusalResponse(passport);
  ///   }
  ///   return await visa.client.chat(prompt);
  /// } on UpstreamApiException catch (e) {
  ///   // A handler errored. Real failure, surface it.
  ///   return _errorResponse(e);
  /// }
  /// ```
  ///
  /// Reach for [request] (which throws on the no-answer case) only when
  /// the caller has guaranteed at least one handler will claim.
  Future<Response?> maybeRequest<Request, Response>(
    Request request, {
    String? identifier,
  }) async {
    try {
      return await this.request<Request, Response>(
        request,
        identifier: identifier,
      );
    } on NoRequestAnswerException {
      return null;
    }
  }

  /// Register a handler for request/response communication.
  ///
  /// When `request<Request, Response>(...)` is called with a matching
  /// `(Request, Response)` type pair (and, optionally, [identifier]),
  /// handlers walk in descending priority. Each handler may:
  ///
  /// - Return a non-null value to claim the call; dispatch stops there.
  /// - Return `null` to concede so the next handler can claim.
  /// - Throw to signal a real error; the chain stops and the exception
  ///   propagates to the caller unchanged. Subsequent handlers do not
  ///   run.
  ///
  /// Concession by `null` works whether or not [Response] is nullable.
  /// `null` is the framework's "I won't answer" signal. Throws are
  /// reserved for genuine errors. See [request] for how the consumer
  /// observes the all-conceded case (it depends on which method they
  /// call).
  ///
  /// Returns an [EventSubscription] for cancellation.
  ///
  /// Example:
  /// ```dart
  /// final sub = bus.onRequest<SearchQuery, SearchResults>((env) async {
  ///   final hit = await tryProvider(env.event);
  ///   return hit; // null to let the next provider try
  /// }, priority: 10);
  /// ```
  EventSubscription onRequest<Request, Response>(
    RequestHandler<Request, Response> handler, {
    int priority = Priority.normal,
    String? identifier,
  }) {
    _checkNotDisposed();
    final key = (Request, Response);
    final buckets =
        _requestHandlers.putIfAbsent(
              key,
              _RequestBuckets<Request, Response>.new,
            )
            as _RequestBuckets<Request, Response>;
    final List<_RequestEntry<Request, Response>> list = identifier == null
        ? buckets.general
        : buckets.byId.putIfAbsent(
            identifier,
            () => <_RequestEntry<Request, Response>>[],
          );

    final entry = _RequestEntry<Request, Response>(
      priority: priority,
      run: handler,
    );
    list.add(entry);
    if (identifier == null) {
      buckets.markGeneralDirty();
    } else {
      buckets.markIdDirty(identifier);
    }

    return _EventHandlerSub(
      onCancel: () {
        list.remove(entry);
        if (list.isEmpty) {
          if (identifier == null) {
            if (buckets.byId.isEmpty) _requestHandlers.remove(key);
          } else {
            buckets.removeIdBucket(identifier);
            if (buckets.byId.isEmpty && buckets.general.isEmpty) {
              _requestHandlers.remove(key);
            }
          }
        }
      },
    );
  }

  /// Synchronous priority-cascade version of [request].
  ///
  /// Prefer [maybeRequestSync] over this method when concession is a
  /// valid outcome at your call site. `requestSync` is the assertion
  /// variant: it throws if the chain bottoms out without an answer. Use
  /// it only when the caller has guaranteed that at least one handler
  /// will claim.
  ///
  /// Dispatch model mirrors [request]: handlers walk in priority order,
  /// first non-null wins, concession via `null` continues to the next
  /// handler, throws stop the chain and propagate. Every invoked
  /// handler must return synchronously; if any invoked handler returns a
  /// [Future], throws [StateError].
  ///
  /// Throws:
  /// - [RequestNotWiredException] if no handler is registered for the
  ///   `(Request, Response)` type pair, or no handler matched the
  ///   requested [identifier].
  /// - [AllConcededException] if every handler ran and returned `null`
  ///   and [Response] is non-nullable. The message recommends switching
  ///   to [maybeRequestSync]. When [Response] is nullable, this method
  ///   returns `null` instead of throwing.
  /// - [StateError] if any invoked handler returned a [Future].
  /// - Any exception a handler raised, unwrapped.
  ///
  /// ```dart
  /// final passport = bus.requestSync<ModelRef, ModelPassport>(
  ///   ModelRef.byModel('gpt-5'),
  /// );
  /// ```
  Response requestSync<Request, Response>(
    Request request, {
    String? identifier,
  }) {
    _checkNotDisposed();
    final raw = _requestHandlers[(Request, Response)];
    if (raw == null) {
      throw RequestNotWiredException(
        requestType: Request,
        responseType: Response,
        identifier: identifier,
      );
    }
    final buckets = raw as _RequestBuckets<Request, Response>;

    buckets.ensureGeneralSorted();
    buckets.ensureIdSorted(identifier);
    final merged = _mergePrioritized(buckets.general, buckets.byId[identifier]);
    if (merged.isEmpty) {
      throw RequestNotWiredException(
        requestType: Request,
        responseType: Response,
        identifier: identifier,
        wasIdentifierMismatch: true,
      );
    }

    final wrapped = EventEnvelope<Request>(
      event: request,
      identifier: identifier,
    );

    Response? lastResponse;
    for (final entry in merged) {
      final result = entry.run(wrapped);
      if (result is Future) {
        throw StateError(
          'requestSync called but handler for ${Request.toString()} -> ${Response.toString()} '
          'returned a Future. Use request() instead, or register with onRequestSync().',
        );
      }
      lastResponse = result;
      if (result != null) return result;
    }

    if (null is Response) return lastResponse as Response;
    throw AllConcededException(
      requestType: Request,
      responseType: Response,
      identifier: identifier,
    );
  }

  /// Synchronous priority-cascade version of [maybeRequest].
  ///
  /// The canonical synchronous method for chains where concession is a
  /// valid outcome. Returns `null` when no handler is registered, no
  /// handler matched [identifier], or every registered handler conceded.
  /// Exceptions thrown by handlers propagate unchanged; `maybeRequestSync`
  /// does NOT swallow handler exceptions, only the framework's own
  /// [NoRequestAnswerException] subtypes
  /// ([RequestNotWiredException] and [AllConcededException]).
  ///
  /// Reach for [requestSync] (which throws on the no-answer case) only
  /// when the caller has guaranteed at least one handler will claim.
  Response? maybeRequestSync<Request, Response>(
    Request request, {
    String? identifier,
  }) {
    try {
      return requestSync<Request, Response>(request, identifier: identifier);
    } on NoRequestAnswerException {
      return null;
    }
  }

  /// Register a synchronous handler for request/response communication.
  ///
  /// Like [onRequest] but enforces at compile time that the handler
  /// returns synchronously. Same concession-by-`null` and
  /// throw-stops-chain semantics; see [requestSync] / [maybeRequestSync]
  /// for consumer-side details (and especially which method to choose
  /// when concession is a valid outcome at the call site).
  ///
  /// ```dart
  /// bus.onRequestSync<ModelRef, ModelPassport>((req) {
  ///   return findModel(req.event); // null to let the next provider try
  /// });
  /// ```
  EventSubscription onRequestSync<Request, Response>(
    SyncRequestHandler<Request, Response> handler, {
    int priority = Priority.normal,
    String? identifier,
  }) {
    // Wrap the sync handler as a FutureOr handler so it shares the same
    // internal storage. requestSync will verify the result is not a Future.
    return onRequest<Request, Response>(
      (event) => handler(event),
      priority: priority,
      identifier: identifier,
    );
  }

  /// Emit an internal event that is not exposed to [bind] callbacks.
  ///
  /// Delegates to [emit] with `internal: true`. Internal events skip
  /// [EventBindingCallback] observation. Used for system lifecycle events.
  Future<EventEnvelope<T>> emitInternal<T>({
    required T event,
    String? identifier,
  }) => emit<T>(event: event, identifier: identifier, internal: true);

  /// Emit an event and await all handlers.
  ///
  /// Wraps [event] in an [EventEnvelope], then runs registered handlers in
  /// descending priority order (higher priority runs first). Dispatch stops
  /// when a handler calls [EventEnvelope.stop] or when every handler has
  /// run. Returns the envelope with its final state.
  // #docregion event-bus-emit
  Future<EventEnvelope<T>> emit<T>({
    required T event,
    String? identifier,
    bool internal = false,
  }) async {
    // #enddocregion event-bus-emit
    _checkNotDisposed();
    final wrapped = EventEnvelope<T>(event: event, identifier: identifier);

    // Forward event to all bound callbacks (skip internal events). Iterate
    // a snapshot so a callback that calls its cancel closure mid-dispatch
    // doesn't ConcurrentModificationError on _eventBindings.
    if (!internal) {
      for (final callback in List<EventBindingCallback>.of(_eventBindings)) {
        callback(wrapped);
      }
    }

    final raw = _eventHandlers[T];
    if (raw == null) return wrapped;
    final buckets = raw as _EventBuckets<T>;

    buckets.ensureGeneralSorted();
    buckets.ensureIdSorted(identifier);
    final merged = _mergePrioritized(buckets.general, buckets.byId[identifier]);

    // The wrapped object will get passed to each handler and mutated at each step.
    for (final entry in merged) {
      await entry.run(wrapped);
      if (wrapped.stopped) break;
    }
    return wrapped;
  }

  /// Synchronous version of [emit]. Same dispatch semantics but every handler
  /// must return synchronously. If any handler returns a [Future], throws
  /// [StateError].
  ///
  /// Used for synchronous lifecycle events where the emitter needs to ensure
  /// all handlers have run before proceeding, and where async handlers would be
  /// a bug.
  ///
  /// ```dart
  /// final res = bus.emitSync<InitializationEvent>(
  ///  event: InitializationEvent(),
  ///  );
  ///
  /// if (res.stopped) {
  ///  print('Initialization stopped with result: ${res.event}');
  /// } else {
  /// print('Initialization completed without early termination');
  /// }
  /// ```
  EventEnvelope<T> emitSync<T>({
    required T event,
    String? identifier,
    bool internal = false,
  }) {
    _checkNotDisposed();
    final wrapped = EventEnvelope<T>(event: event, identifier: identifier);

    // Forward event to all bound callbacks (skip internal events). Iterate
    // a snapshot so a callback that calls its cancel closure mid-dispatch
    // doesn't ConcurrentModificationError on _eventBindings.
    if (!internal) {
      for (final callback in List<EventBindingCallback>.of(_eventBindings)) {
        callback(wrapped);
      }
    }

    final raw = _eventHandlers[T];
    if (raw == null) return wrapped;
    final buckets = raw as _EventBuckets<T>;

    buckets.ensureGeneralSorted();
    buckets.ensureIdSorted(identifier);
    final merged = _mergePrioritized(buckets.general, buckets.byId[identifier]);

    // The wrapped object will get passed to each handler and mutated at each step.
    for (final entry in merged) {
      final result = entry.run(wrapped);
      if (result is Future) {
        throw StateError(
          'emitSync called but handler for ${T.toString()} returned a Future. Use emit() instead.',
        );
      }
      if (wrapped.stopped) break;
    }
    return wrapped;
  }

  /// Merge the general list with the (optional) identifier-scoped list into
  /// a single descending-priority sequence (higher priority first).
  ///
  /// Both inputs are assumed already sorted by descending priority. Used by
  /// [emit], [request], and [requestSync] so all three dispatch paths agree
  /// on ordering.
  ///
  /// Always returns a NEW list, never the underlying bucket, so callers
  /// can iterate safely while a handler cancels (and thus mutates the
  /// underlying bucket) mid-dispatch.
  List<E> _mergePrioritized<E extends _PriorityEntry>(List<E> a, List<E>? b) {
    if (b == null || b.isEmpty) return List<E>.of(a);
    if (a.isEmpty) return List<E>.of(b);

    final merged = <E>[];
    int i = 0, j = 0;
    while (i < a.length && j < b.length) {
      if (a[i].priority >= b[j].priority) {
        merged.add(a[i++]);
      } else {
        merged.add(b[j++]);
      }
    }
    if (i < a.length) merged.addAll(a.sublist(i));
    if (j < b.length) merged.addAll(b.sublist(j));
    return merged;
  }
}

/// Shared interface for priority-sorted handler entries.
///
/// Both event and request handler entries implement this so a single
/// priority-merge helper can work with either kind.
abstract class _PriorityEntry {
  int get priority;
}

/// Typed event handler entry.
class _EventEntry<T> implements _PriorityEntry {
  @override
  final int priority;
  final FutureOr<void> Function(EventEnvelope<T>) run;

  _EventEntry({required this.priority, required this.run});
}

/// Per-type event buckets. Stored in [EventBus._eventHandlers] at key `T`.
///
/// Handlers are appended in O(1); the bucket is marked dirty and sorted
/// lazily on the next dispatch via [ensureGeneralSorted] /
/// [ensureIdSorted]. Sorting on append (O(N) shift per insert -> O(N^2)
/// total for N registrations) is the bottleneck the lazy strategy
/// removes for the common register-many-then-dispatch pattern.
class _EventBuckets<T> {
  final List<_EventEntry<T>> general = <_EventEntry<T>>[];
  final Map<String, List<_EventEntry<T>>> byId =
      <String, List<_EventEntry<T>>>{};
  bool _generalDirty = false;
  final Set<String> _dirtyIds = <String>{};

  void markGeneralDirty() {
    _generalDirty = true;
  }

  void markIdDirty(String id) {
    _dirtyIds.add(id);
  }

  /// Remove the identifier's bucket AND its dirty-id entry atomically.
  /// Keeps `_dirtyIds` from accumulating stale entries when the last
  /// handler for an identifier is cancelled.
  void removeIdBucket(String id) {
    byId.remove(id);
    _dirtyIds.remove(id);
  }

  void ensureGeneralSorted() {
    if (!_generalDirty) return;
    general.sort((a, b) => b.priority.compareTo(a.priority));
    _generalDirty = false;
  }

  void ensureIdSorted(String? id) {
    if (id == null) return;
    if (!_dirtyIds.remove(id)) return;
    byId[id]?.sort((a, b) => b.priority.compareTo(a.priority));
  }
}

/// Typed request handler entry.
class _RequestEntry<Request, Response> implements _PriorityEntry {
  @override
  final int priority;
  final FutureOr<Response?> Function(EventEnvelope<Request>) run;

  _RequestEntry({required this.priority, required this.run});
}

/// Per-request-pair buckets. Stored in [EventBus._requestHandlers] at key
/// `(Request, Response)`. Same lazy-sort strategy as [_EventBuckets].
class _RequestBuckets<Request, Response> {
  final List<_RequestEntry<Request, Response>> general =
      <_RequestEntry<Request, Response>>[];
  final Map<String, List<_RequestEntry<Request, Response>>> byId =
      <String, List<_RequestEntry<Request, Response>>>{};
  bool _generalDirty = false;
  final Set<String> _dirtyIds = <String>{};

  void markGeneralDirty() {
    _generalDirty = true;
  }

  void markIdDirty(String id) {
    _dirtyIds.add(id);
  }

  void removeIdBucket(String id) {
    byId.remove(id);
    _dirtyIds.remove(id);
  }

  void ensureGeneralSorted() {
    if (!_generalDirty) return;
    general.sort((a, b) => b.priority.compareTo(a.priority));
    _generalDirty = false;
  }

  void ensureIdSorted(String? id) {
    if (id == null) return;
    if (!_dirtyIds.remove(id)) return;
    byId[id]?.sort((a, b) => b.priority.compareTo(a.priority));
  }
}

typedef _CancelCallback = void Function();

/// Concrete [EventSubscription] returned by every `on*` method on
/// [EventBus]. Holds the cancel callback registered when the handler was
/// inserted into its priority-sorted bucket; calling [cancel] removes the
/// handler entry and, if the bucket goes empty, removes the bucket too.
class _EventHandlerSub implements EventSubscription {
  final _CancelCallback _cancel;
  bool _cancelled = false;

  _EventHandlerSub({required _CancelCallback onCancel}) : _cancel = onCancel;

  @override
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    _cancel();
  }
}
