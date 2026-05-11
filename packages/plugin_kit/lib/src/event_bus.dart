library;

import 'dart:async';

import 'package:plugin_kit/plugin_kit.dart';

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

/// Internal-only event response that is not exposed to [EventBindingCallback]s.
///
/// Used for system-internal events that should not be observed by external
/// binding callbacks (e.g., lifecycle events).
class InternalPluginEventResponse<T> extends EventEnvelope<T> {
  /// Creates an internal-only event response.
  InternalPluginEventResponse({
    required super.event,
    required super.identifier,
  });
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

/// Handler function for request/response communication.
///
/// Receives the request wrapped in a [EventEnvelope] and must
/// return a response of type [Response].
///
/// See [EventBus.onRequest] and [EventBus.request].
typedef RequestHandler<Request, Response> =
    FutureOr<Response> Function(EventEnvelope<Request> e);

/// Synchronous handler function for request/response communication.
///
/// Like [RequestHandler] but guaranteed to return synchronously.
/// Used with [EventBus.onRequestSync] and [EventBus.requestSync].
typedef SyncRequestHandler<Request, Response> =
    Response Function(EventEnvelope<Request> e);

/// Callback for observing all non-internal events emitted on the bus.
///
/// Registered via [EventBus.bind]. Called before handler dispatch.
typedef EventBindingCallback = void Function(EventEnvelope<dynamic> event);

/// Typed, priority-ordered event bus for decoupled inter-plugin
/// communication.
///
/// Events are dispatched by Dart type (`T`); handlers run in ascending
/// priority order (lower numbers first), so higher-priority handlers
/// intercept before lower-priority ones see the event. A handler can stop
/// dispatch by calling [EventEnvelope.stop] with a final result. Events
/// optionally carry an [identifier] (an agent id, etc.); both general and
/// identifier-specific handlers merge during dispatch.
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
/// Priority convention: ascending. A handler with `priority: 0` runs before
/// `priority: 10`. This is the opposite of [ServiceRegistry], where higher
/// numbers win during resolution. The rationale: event handlers form an
/// ordered pipeline (first handler can intercept) while service resolution
/// is a competition (highest priority wins).
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
  /// Handlers are dispatched in ascending priority order (lower numbers
  /// first). When [identifier] is supplied, identifier-scoped handlers
  /// merge with general handlers in the same priority-ordered sequence.
  StreamSubscription on<T>(
    EventHandler<T> handler, {
    int priority = 0,
    String? identifier,
  }) {
    _checkNotDisposed();
    final buckets =
        _eventHandlers.putIfAbsent(T, _EventBuckets<T>.new) as _EventBuckets<T>;
    final List<_EventEntry<T>> list = identifier == null
        ? buckets.general
        : buckets.byId.putIfAbsent(identifier, () => <_EventEntry<T>>[]);

    final entry = _EventEntry<T>(priority: priority, run: handler);
    _insertPrioritized(list, entry);

    return _EventHandlerSub(
      onCancel: () {
        list.remove(entry);
        if (list.isEmpty) {
          if (identifier == null) {
            if (buckets.byId.isEmpty) _eventHandlers.remove(T);
          } else {
            buckets.byId.remove(identifier);
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
  StreamSubscription onSync<T>(
    SyncEventHandler<T> handler, {
    int priority = 0,
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

  /// Send a typed request and walk registered handlers in priority
  /// order until one claims it.
  ///
  /// Dispatch model (mirrors [emit]):
  ///
  ///   * General handlers and `identifier`-scoped handlers are merged
  ///     into a single ascending-priority sequence (lower priority
  ///     number runs first).
  ///   * Each handler is invoked with the wrapped request. A handler
  ///     claims the call by returning a non-null [Response];
  ///     dispatch stops and that value is returned.
  ///   * A handler concedes by returning `null`: the next
  ///     handler in priority order gets a turn. This requires
  ///     [Response] to be nullable; for non-nullable [Response] the
  ///     first handler to return wins (handlers can't return null,
  ///     so cascade is a no-op).
  ///
  /// Throws if no handler is registered, or if every registered
  /// handler concedes and [Response] is non-nullable.
  ///
  /// Example:
  /// ```dart
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
      throw RequestUnavailableException(
        requestType: Request,
        responseType: Response,
        identifier: identifier,
        reason: 'no handlers registered',
      );
    }
    final buckets = raw as _RequestBuckets<Request, Response>;

    final merged = _mergePrioritized(buckets.general, buckets.byId[identifier]);
    if (merged.isEmpty) {
      throw RequestUnavailableException(
        requestType: Request,
        responseType: Response,
        identifier: identifier,
        reason: 'no handlers registered',
      );
    }

    final wrapped = InternalPluginEventResponse<Request>(
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
    throw RequestUnavailableException(
      requestType: Request,
      responseType: Response,
      identifier: identifier,
      reason:
          'every registered handler returned null but Response is non-nullable',
    );
  }

  /// Sends a typed request and returns `null` if no handler is registered or
  /// every registered handler concedes (returns `null`).
  ///
  /// Exceptions thrown by handlers propagate. A `null` return means the
  /// request was unavailable, not that handler execution failed.
  Future<Response?> maybeRequest<Request, Response>(
    Request request, {
    String? identifier,
  }) async {
    try {
      return await this.request<Request, Response>(
        request,
        identifier: identifier,
      );
    } on RequestUnavailableException {
      return null;
    }
  }

  /// Register a handler for request/response communication.
  ///
  /// When [request] is called with matching `Request`/`Response` types,
  /// this handler is invoked to produce the envelope. Returns a
  /// [StreamSubscription] for cancellation.
  ///
  /// Example:
  /// ```dart
  /// final sub = bus.onRequest<SearchQuery, SearchResults>((req) async {
  ///   return await performSearch(req.event.query);
  /// }, priority: 10);
  /// ```
  StreamSubscription onRequest<Request, Response>(
    RequestHandler<Request, Response> handler, {
    int priority = 0,
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
    _insertPrioritized(list, entry);

    return _EventHandlerSub(
      onCancel: () {
        list.remove(entry);
        if (list.isEmpty) {
          if (identifier == null) {
            if (buckets.byId.isEmpty) _requestHandlers.remove(key);
          } else {
            buckets.byId.remove(identifier);
            if (buckets.byId.isEmpty && buckets.general.isEmpty) {
              _requestHandlers.remove(key);
            }
          }
        }
      },
    );
  }

  /// Synchronous priority-cascade version of [request]. Same dispatch
  /// model: handlers tried in priority order, first non-null wins,
  /// nullable [Response] enables concession via `null`: but every
  /// invoked handler must return synchronously.
  ///
  /// Handlers MUST have been registered via [onRequestSync]; if any
  /// invoked handler returns a [Future], throws [StateError].
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
      throw RequestUnavailableException(
        requestType: Request,
        responseType: Response,
        identifier: identifier,
        reason: 'no handlers registered',
      );
    }
    final buckets = raw as _RequestBuckets<Request, Response>;

    final merged = _mergePrioritized(buckets.general, buckets.byId[identifier]);
    if (merged.isEmpty) {
      throw RequestUnavailableException(
        requestType: Request,
        responseType: Response,
        identifier: identifier,
        reason: 'no handlers registered',
      );
    }

    final wrapped = InternalPluginEventResponse<Request>(
      event: request,
      identifier: identifier,
    );

    Response? lastResponse;
    for (final entry in merged) {
      final result = entry.run(wrapped);
      if (result is Future) {
        throw StateError(
          'requestSync called but handler for ${Request.toString()} → ${Response.toString()} '
          'returned a Future. Use request() instead, or register with onRequestSync().',
        );
      }
      lastResponse = result;
      if (result != null) return result;
    }

    if (null is Response) return lastResponse as Response;
    throw RequestUnavailableException(
      requestType: Request,
      responseType: Response,
      identifier: identifier,
      reason:
          'every registered handler returned null but Response is non-nullable',
    );
  }

  /// Sends a typed request synchronously and returns `null` if no handler is
  /// registered or every registered handler concedes (returns `null`).
  ///
  /// Exceptions thrown by handlers propagate. A `null` return means the
  /// request was unavailable, not that handler execution failed.
  Response? maybeRequestSync<Request, Response>(
    Request request, {
    String? identifier,
  }) {
    try {
      return requestSync<Request, Response>(request, identifier: identifier);
    } on RequestUnavailableException {
      return null;
    }
  }

  /// Register a synchronous handler for request/response communication.
  ///
  /// Like [onRequest] but enforces at compile time that the handler
  /// returns synchronously. Handlers registered this way are safe to
  /// invoke via [requestSync].
  ///
  /// ```dart
  /// bus.onRequestSync<ModelRef, ModelPassport>((req) {
  ///   return findModel(req.event); // must be sync
  /// });
  /// ```
  StreamSubscription onRequestSync<Request, Response>(
    SyncRequestHandler<Request, Response> handler, {
    int priority = 0,
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
  /// Delegates to [emit] with `internal: true`. Internal events are
  /// wrapped in [InternalPluginEventResponse] and skip [EventBindingCallback]
  /// observation. Used for system lifecycle events.
  Future<EventEnvelope<T>> emitInternal<T>({
    required T event,
    String? identifier,
  }) => emit<T>(event: event, identifier: identifier, internal: true);

  /// Emit an event and await all handlers.
  ///
  /// Wraps [event] in an [EventEnvelope], then runs registered handlers in
  /// ascending priority order. Dispatch stops when a handler calls
  /// [EventEnvelope.stop] or when every handler has run. Returns the
  /// envelope with its final state.
  // #docregion event-bus-emit
  Future<EventEnvelope<T>> emit<T>({
    required T event,
    String? identifier,
    bool internal = false,
  }) async {
    // #enddocregion event-bus-emit
    _checkNotDisposed();
    final wrapped = internal
        ? InternalPluginEventResponse(event: event, identifier: identifier)
        : EventEnvelope<T>(event: event, identifier: identifier);

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
    final wrapped = internal
        ? InternalPluginEventResponse(event: event, identifier: identifier)
        : EventEnvelope<T>(event: event, identifier: identifier);

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
  /// a single ascending-priority sequence.
  ///
  /// Both inputs are assumed already sorted by priority. Used by [emit],
  /// [request], and [requestSync] so all three dispatch paths agree on
  /// ordering.
  ///
  /// Always returns a NEW list — never the underlying bucket — so callers
  /// can iterate safely while a handler cancels (and thus mutates the
  /// underlying bucket) mid-dispatch.
  List<E> _mergePrioritized<E extends _PriorityEntry>(List<E> a, List<E>? b) {
    if (b == null || b.isEmpty) return List<E>.of(a);
    if (a.isEmpty) return List<E>.of(b);

    final merged = <E>[];
    int i = 0, j = 0;
    while (i < a.length && j < b.length) {
      if (a[i].priority <= b[j].priority) {
        merged.add(a[i++]);
      } else {
        merged.add(b[j++]);
      }
    }
    if (i < a.length) merged.addAll(a.sublist(i));
    if (j < b.length) merged.addAll(b.sublist(j));
    return merged;
  }

  /// Insert [entry] into [list] keeping it sorted by ascending priority.
  void _insertPrioritized<E extends _PriorityEntry>(List<E> list, E entry) {
    // Simple insertion; lists are expected to be small.
    final index = list.indexWhere((e) => entry.priority < e.priority);
    if (index == -1) {
      list.add(entry);
    } else {
      list.insert(index, entry);
    }
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
class _EventBuckets<T> {
  final List<_EventEntry<T>> general = <_EventEntry<T>>[];
  final Map<String, List<_EventEntry<T>>> byId =
      <String, List<_EventEntry<T>>>{};
}

/// Typed request handler entry.
class _RequestEntry<Request, Response> implements _PriorityEntry {
  @override
  final int priority;
  final FutureOr<Response> Function(EventEnvelope<Request>) run;

  _RequestEntry({required this.priority, required this.run});
}

/// Per-request-pair buckets. Stored in [EventBus._requestHandlers] at key
/// `(Request, Response)`.
class _RequestBuckets<Request, Response> {
  final List<_RequestEntry<Request, Response>> general =
      <_RequestEntry<Request, Response>>[];
  final Map<String, List<_RequestEntry<Request, Response>>> byId =
      <String, List<_RequestEntry<Request, Response>>>{};
}

typedef _CancelCallback = void Function();

/// Subscription wrapper for event handlers.
///
/// Provides a [StreamSubscription] interface for canceling event handlers.
/// Only [cancel] is supported: other [StreamSubscription] methods throw
/// [UnsupportedError] since event bus subscriptions are not backed by a
/// real [Stream] and don't support backpressure or data callbacks.
class _EventHandlerSub implements StreamSubscription {
  /// Function to call when canceling the subscription.
  final _CancelCallback _cancel;

  _EventHandlerSub({required _CancelCallback onCancel}) : _cancel = onCancel;

  @override
  Future<void> cancel() async => _cancel();

  @override
  void onData(void Function(dynamic)? handleData) =>
      throw UnsupportedError('Event bus subscriptions do not support onData');

  @override
  void onDone(void Function()? handleDone) =>
      throw UnsupportedError('Event bus subscriptions do not support onDone');

  @override
  void onError(Function? handleError) =>
      throw UnsupportedError('Event bus subscriptions do not support onError');

  @override
  void pause([Future<void>? resumeSignal]) =>
      throw UnsupportedError('Event bus subscriptions do not support pause');

  @override
  void resume() =>
      throw UnsupportedError('Event bus subscriptions do not support resume');

  @override
  bool get isPaused => false;

  @override
  Future<E> asFuture<E>([E? futureValue]) =>
      throw UnsupportedError('Event bus subscriptions do not support asFuture');
}
