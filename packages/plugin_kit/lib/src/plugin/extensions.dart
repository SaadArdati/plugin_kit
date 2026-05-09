part of 'plugin.dart';

/// Convenience helpers for [Plugin] subscriptions and bus emit.
///
/// Every helper takes the [PluginContext] explicitly as its first
/// argument. This is the contract Plugin needs because the same plugin
/// instance is shared across sessions: there is no safe "current context"
/// to read from a field. Inside [Plugin.attach] / [Plugin.detach] the
/// `context` parameter is right there; pass it along.
///
/// Subscriptions registered via [on], [onRequest], [onRequestSync], and
/// [bind] are bucketed under the [context] you passed; the framework
/// cancels each context's bucket when that context detaches, so concurrent
/// sessions of the same plugin do not trample each other's teardown.
extension PluginHelper on Plugin {
  /// Subscribe to events of type [E] on [context]'s bus.
  ///
  /// The handler receives the [EventEnvelope] wrapping the payload. It may
  /// mutate `e.event` and call [EventEnvelope.stop] to halt the cascade. The
  /// subscription is auto-tracked under [context] and cancelled when that
  /// context detaches; the returned [StreamSubscription] is for cases that
  /// need to cancel the handler explicitly before then.
  StreamSubscription on<E>(
    PluginContext context,
    EventHandler<E> handler, {
    int priority = 0,
    String? identifier,
  }) {
    final sub = context.bus.on<E>(
      handler,
      priority: priority,
      identifier: identifier,
    );
    (_subscriptionsByContext[context] ??= []).add(sub);
    return sub;
  }

  /// Register a request handler on [context]'s bus.
  ///
  /// Auto-tracked under [context]. See [EventBus.onRequest] for details on
  /// request/response communication.
  StreamSubscription onRequest<Request, Response>(
    PluginContext context,
    RequestHandler<Request, Response> handler, {
    int priority = 0,
    String? identifier,
  }) {
    final sub = context.bus.onRequest<Request, Response>(
      handler,
      priority: priority,
      identifier: identifier,
    );
    (_subscriptionsByContext[context] ??= []).add(sub);
    return sub;
  }

  /// Register a synchronous request handler on [context]'s bus.
  ///
  /// Like [onRequest] but enforces sync return at compile time. Safe to
  /// invoke via [EventBus.requestSync]. Auto-tracked under [context].
  StreamSubscription onRequestSync<Request, Response>(
    PluginContext context,
    SyncRequestHandler<Request, Response> handler, {
    int priority = 0,
    String? identifier,
  }) {
    final sub = context.bus.onRequestSync<Request, Response>(
      handler,
      priority: priority,
      identifier: identifier,
    );
    (_subscriptionsByContext[context] ??= []).add(sub);
    return sub;
  }

  /// Bind a type-agnostic observer to [context]'s bus.
  ///
  /// The callback fires for every non-internal event emitted on the bus,
  /// regardless of type. Use for tracing, telemetry, or other passive
  /// observation. The binding is auto-tracked under [context]; the returned
  /// cancel callback is for cases that need to remove the binding
  /// explicitly before detach.
  void Function() bind(PluginContext context, EventBindingCallback callback) {
    final cancel = context.bus.bind(callback);
    (_bindingsByContext[context] ??= []).add(cancel);
    return cancel;
  }

  /// Emit an event onto [context]'s bus.
  ///
  /// For session plugins shared across sessions, pass the context for the
  /// session you want to target. Capture the bus during [Plugin.attach] if
  /// you need to emit from a long-lived callback after attach returns.
  Future<EventEnvelope<T>> emit<T>(
    PluginContext context,
    T event, {
    String? identifier,
  }) => context.bus.emit<T>(event: event, identifier: identifier);
}

/// Convenience helpers for resolving services from a [PluginService].
extension PluginServiceHelper on PluginService {
  /// Resolve a service by its [serviceId].
  ///
  /// Throws [StateError] if no service is registered for [serviceId].
  T resolve<T>(PluginContext context, ServiceId serviceId) =>
      context.registry.resolve<T>(serviceId);

  /// Resolve a service by its [serviceId], returning `null` if not found.
  T? maybeResolve<T extends Object>(
    PluginContext context,
    ServiceId serviceId,
  ) => context.registry.maybeResolve<T>(serviceId);

  /// Resolve the next service in the priority chain after [pluginId].
  ///
  /// Implements chain-of-responsibility: skips the registration from
  /// [pluginId] and returns the next-highest-priority registrant. Throws
  /// [StateError] if no service exists after [pluginId].
  T resolveAfter<T>(
    PluginContext context, {
    required PluginId pluginId,
    required ServiceId serviceId,
  }) => context.registry.resolveAfter<T>(
    pluginId: pluginId,
    serviceId: serviceId,
  );
}

/// Convenience helpers for [StatefulPluginService] resolution and bus APIs.
///
/// Subscriptions/bindings registered via these helpers go into the service's
/// own [activeSubscriptions] / [activeBindings] lists. Each session calls
/// `register` separately and constructs its own service instance inline, so
/// per-context bucketing isn't required at the service level.
extension StatefulPluginServiceHelper on StatefulPluginService {
  /// Resolve a service by its [serviceId].
  ///
  /// Throws [StateError] if no service is registered for [serviceId].
  T resolve<T>(ServiceId serviceId) => context.registry.resolve<T>(serviceId);

  /// Resolve a service by its [serviceId], returning `null` if not found.
  T? maybeResolve<T extends Object>(ServiceId serviceId) =>
      context.registry.maybeResolve<T>(serviceId);

  /// Resolve the next service in the priority chain after [pluginId].
  ///
  /// Implements chain-of-responsibility: skips the registration from
  /// [pluginId] and returns the next-highest-priority registrant. Throws
  /// [StateError] if no service exists after [pluginId].
  T resolveAfter<T>({
    required PluginId pluginId,
    required ServiceId serviceId,
  }) => context.registry.resolveAfter<T>(
    pluginId: pluginId,
    serviceId: serviceId,
  );

  /// Register a request handler for a request/response type pair.
  /// Auto-tracked and cancelled when the framework unbinds the service.
  StreamSubscription onRequest<Request, Response>(
    RequestHandler<Request, Response> handler, {
    int priority = 0,
    String? identifier,
  }) {
    final sub = context.bus.onRequest<Request, Response>(
      handler,
      priority: priority,
      identifier: identifier,
    );
    activeSubscriptions.add(sub);
    return sub;
  }

  /// Register a synchronous request handler.
  /// Auto-tracked and cancelled when the framework unbinds the service.
  StreamSubscription onRequestSync<Request, Response>(
    SyncRequestHandler<Request, Response> handler, {
    int priority = 0,
    String? identifier,
  }) {
    final sub = context.bus.onRequestSync<Request, Response>(
      handler,
      priority: priority,
      identifier: identifier,
    );
    activeSubscriptions.add(sub);
    return sub;
  }

  /// Subscribe to events of type [E].
  ///
  /// The handler receives the [EventEnvelope] wrapping the payload. It may
  /// mutate `e.event` and call [EventEnvelope.stop] to halt the cascade.
  /// Auto-tracked and cancelled when the framework unbinds the service;
  /// the returned [StreamSubscription] is for cases that need to cancel
  /// the handler explicitly before then.
  StreamSubscription on<E>(
    EventHandler<E> handler, {
    int priority = 0,
    String? identifier,
  }) {
    final sub = context.bus.on<E>(
      handler,
      priority: priority,
      identifier: identifier,
    );
    activeSubscriptions.add(sub);
    return sub;
  }

  /// Bind a type-agnostic observer to the session's event bus.
  ///
  /// Auto-tracked and removed when the framework unbinds the service.
  void Function() bind(EventBindingCallback callback) {
    final cancel = context.bus.bind(callback);
    activeBindings.add(cancel);
    return cancel;
  }

  /// Emit an event into the session's event bus and await all handlers.
  ///
  /// Returns the [EventEnvelope] with its final state (stopped flag,
  /// possibly-mutated payload). Throws [StateError] if called before
  /// [attach] or after [detach].
  Future<EventEnvelope<T>> emit<T>(T event, {String? identifier}) {
    if (!hasContext) {
      throw StateError(
        'Plugin service context is not set. You cannot emit events before attach() and after detach().',
      );
    }
    return context.bus.emit<T>(event: event, identifier: identifier);
  }
}

/// Convenience helpers for service resolution and bus APIs on [PluginSession].
extension SessionHelper on PluginSession {
  /// Resolve a service by its [serviceId].
  ///
  /// Throws [StateError] if no service is registered for [serviceId].
  T resolve<T extends Object>(ServiceId serviceId) =>
      registry.resolve<T>(serviceId);

  /// Resolve a service by its [serviceId], returning `null` if not found.
  T? maybeResolve<T extends Object>(ServiceId serviceId) =>
      registry.maybeResolve<T>(serviceId);

  /// Resolve the next service in the priority chain after [pluginId].
  ///
  /// Implements chain-of-responsibility: skips the registration from
  /// [pluginId] and returns the next-highest-priority registrant. Throws
  /// [StateError] if no service exists after [pluginId].
  T resolveAfter<T>({
    required PluginId pluginId,
    required ServiceId serviceId,
  }) => registry.resolveAfter<T>(pluginId: pluginId, serviceId: serviceId);

  /// Emit an event on this session's bus, optionally scoped to an
  /// [identifier].
  ///
  /// When [identifier] is supplied, dispatch merges general handlers with
  /// identifier-scoped handlers in priority order. When omitted, only
  /// general handlers run.
  Future<EventEnvelope<T>> emit<T>(T event, {String? identifier}) =>
      bus.emit<T>(event: event, identifier: identifier);

  /// Delegates to the session's event bus to emit an internal event.
  Future<EventEnvelope<T>> emitInternal<T>(T event, {String? identifier}) =>
      bus.emitInternal<T>(event: event, identifier: identifier);

  /// Register a handler for events of type [T] on this session's bus.
  ///
  /// The handler receives the [EventEnvelope] wrapping the payload. It may
  /// mutate `e.event` and call [EventEnvelope.stop] to halt the cascade.
  StreamSubscription on<T>(
    EventHandler<T> handler, {
    int priority = 0,
    String? identifier,
  }) => bus.on<T>(handler, priority: priority, identifier: identifier);

  /// Register a request handler on the session's event bus.
  StreamSubscription onRequest<Request, Response>(
    RequestHandler<Request, Response> handler, {
    int priority = 0,
    String? identifier,
  }) => bus.onRequest<Request, Response>(
    handler,
    priority: priority,
    identifier: identifier,
  );

  /// Registers a synchronous request handler on this session's event bus.
  StreamSubscription onRequestSync<Request, Response>(
    SyncRequestHandler<Request, Response> handler, {
    int priority = 0,
    String? identifier,
  }) => bus.onRequestSync<Request, Response>(
    handler,
    priority: priority,
    identifier: identifier,
  );

  /// Bind a type-agnostic observer to the session's event bus.
  ///
  /// The callback fires for every non-internal event emitted on the bus,
  /// regardless of type. Returns the cancel callback. [PluginSession] has
  /// no detach hook of its own, so this binding is NOT auto-tracked - the
  /// caller is responsible for invoking the returned function when the
  /// observer should stop.
  void Function() bind(EventBindingCallback callback) => bus.bind(callback);

  /// Send a typed request and await a response on the session's event bus.
  Future<Response> request<Request, Response>(
    Request request, {
    String? identifier,
  }) => bus.request<Request, Response>(request, identifier: identifier);

  /// Sends a typed request and returns null if no handler can satisfy it.
  Future<Response?> maybeRequest<Request, Response>(
    Request request, {
    String? identifier,
  }) => bus.maybeRequest<Request, Response>(request, identifier: identifier);

  /// Sends a typed request through synchronous request handlers.
  Response requestSync<Request, Response>(
    Request request, {
    String? identifier,
  }) => bus.requestSync<Request, Response>(request, identifier: identifier);

  /// Sends a sync request and returns null instead of throwing on failure.
  Response? maybeRequestSync<Request, Response>(
    Request request, {
    String? identifier,
  }) =>
      bus.maybeRequestSync<Request, Response>(request, identifier: identifier);
}
