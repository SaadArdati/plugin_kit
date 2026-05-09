import 'package:plugin_kit/plugin_kit.dart';

/// Context object passed to plugin lifecycle hooks.
///
/// Bundles a [ServiceRegistry] for service resolution, an [EventBus] for
/// emitting and subscribing to events, and an [extras] map for arbitrary
/// sidecar data. Created by the [PluginRuntime] (global scope) or by the
/// caller during session preparation, then passed to every plugin lifecycle
/// method.
///
/// The shorthand methods on this class (`resolve`, `maybeResolve`,
/// `resolveAfter`, ...) delegate to the underlying [registry]:
///
/// ```dart
/// // These are equivalent:
/// final service = context.resolve<MyService>(const ServiceId('my_service'));
/// final service = context.registry
///     .resolve<MyService>(const ServiceId('my_service'));
/// ```
///
/// Domain-specific projects typically subclass `PluginContext` to carry
/// additional state. Use [PluginContext.stub] to create a minimal context for
/// unit tests.
class PluginContext {
  /// The service registry for resolving services.
  ///
  /// Plugins use this to look up services registered by other plugins.
  /// Services are resolved by id, with the highest-priority registration
  /// winning when multiple plugins register the same id.
  final ServiceRegistry registry;

  /// Arbitrary sidecar data passed through the context.
  ///
  /// Allows callers to attach domain-specific data without subclassing.
  final Map<String, Object> extras;

  /// The event bus for inter-plugin communication.
  ///
  /// Plugins subscribe to typed events via [EventBus.on] and emit events via
  /// [EventBus.emit]. Events dispatch in priority order with support for
  /// early termination.
  final EventBus bus;

  /// Creates a plugin context from runtime services and optional [extras].
  PluginContext({
    required this.registry,
    required this.bus,
    this.extras = const {},
  });

  /// Creates a minimal context for testing. All parameters default to
  /// empty/no-op implementations.
  factory PluginContext.stub({
    ServiceRegistry? registry,
    EventBus? bus,
    Map<String, Object>? extras,
  }) {
    return PluginContext(
      registry: registry ?? ServiceRegistry.empty(),
      bus: bus ?? EventBus(),
      extras: extras ?? const {},
    );
  }

  /// Resolve a service by its full id.
  ///
  /// Shorthand for `registry.resolve<T>(serviceId)`.
  /// Throws [StateError] if no service is registered for [serviceId].
  T resolve<T extends Object>(ServiceId serviceId) =>
      registry.resolve<T>(serviceId);

  /// Resolve a service by its full id, returning `null` if not found.
  T? maybeResolve<T extends Object>(ServiceId serviceId) =>
      registry.maybeResolve<T>(serviceId);

  /// Resolve the next service in the priority chain after [pluginId].
  ///
  /// Implements chain-of-responsibility: a plugin can delegate to the
  /// next-highest-priority registrant for the same [serviceId]. Throws
  /// [StateError] if no service exists after [pluginId].
  T resolveAfter<T extends Object>({
    required PluginId pluginId,
    required ServiceId serviceId,
  }) => registry.resolveAfter<T>(pluginId: pluginId, serviceId: serviceId);

  /// Send a typed request and await an envelope.
  ///
  /// Delegates to [EventBus.request]: handlers for the
  /// `Request`/`Response` type pair (merged general + identifier-scoped) are
  /// walked in priority order and the first non-null response wins. A
  /// handler returning null concedes to the next; this requires [Response]
  /// to be nullable for that concession to be expressible.
  ///
  /// Throws if no handler is registered, or if every handler concedes and
  /// [Response] is non-nullable.
  Future<Response> request<Request, Response>(
    Request request, {
    String? identifier,
  }) => bus.request<Request, Response>(request, identifier: identifier);

  /// Sends a typed request and returns null if no handler can satisfy it.
  Future<Response?> maybeRequest<Request, Response>(
    Request request, {
    String? identifier,
  }) => bus.maybeRequest<Request, Response>(request, identifier: identifier);

  /// Synchronous version of [request]. The handler must have been registered
  /// via [EventBus.onRequestSync]. Throws [StateError] if no handler is
  /// registered or the handler returns a Future. When [identifier] is
  /// supplied, identifier-scoped handlers merge with general handlers in
  /// priority order.
  Response requestSync<Request, Response>(
    Request request, {
    String? identifier,
  }) => bus.requestSync<Request, Response>(request, identifier: identifier);

  /// Whether a request handler is registered for the given request/response
  /// types.
  bool hasRequestHandler<Request, Response>({String? identifier}) =>
      bus.hasRequestHandler<Request, Response>(identifier: identifier);

  /// Like [requestSync] but returns null instead of throwing.
  Response? maybeRequestSync<Request, Response>(
    Request request, {
    String? identifier,
  }) =>
      bus.maybeRequestSync<Request, Response>(request, identifier: identifier);

  /// Creates a copy of this context with optional field overrides.
  ///
  /// [registry] defaults to a shallow copy of the current registry
  /// (via [ServiceRegistry.copy]) to preserve isolation between original
  /// and copy.
  PluginContext copyWith({
    ServiceRegistry? registry,
    Map<String, Object>? extras,
    EventBus? bus,
  }) {
    return PluginContext(
      registry: registry ?? this.registry.copy(),
      extras: extras ?? this.extras,
      bus: bus ?? this.bus,
    );
  }
}

/// A global-scoped context that additionally carries all active sessions.
///
/// Extends [PluginContext] with awareness of every session managed by the
/// runtime, allowing global-scope code to iterate or look up sessions by
/// plugin id.
class GlobalPluginContext extends PluginContext {
  /// All active plugin sessions managed by the runtime. Each session's
  /// context is at least a [SessionPluginContext]; runtimes with a custom
  /// `S extends SessionPluginContext` generic can pass tighter session
  /// instances here via Dart's list covariance.
  final List<PluginSession<SessionPluginContext>> sessions;

  /// Creates a global context with runtime services and optional [sessions].
  GlobalPluginContext({
    required super.registry,
    required super.bus,
    super.extras,
    this.sessions = const [],
  });

  /// Creates a minimal global context for testing.
  factory GlobalPluginContext.stub({
    ServiceRegistry? registry,
    EventBus? bus,
    Map<String, Object>? extras,
    List<PluginSession<SessionPluginContext>>? sessions,
  }) {
    return GlobalPluginContext(
      registry: registry ?? ServiceRegistry.empty(),
      bus: bus ?? EventBus(),
      extras: extras ?? const {},
      sessions: sessions ?? const [],
    );
  }

  /// Returns the [PluginSession] in which [pluginId] is enabled.
  ///
  /// Iterates [sessions] and returns the first session for which
  /// [PluginSession.isPluginEnabled] is true. Throws [StateError] if no
  /// session has [pluginId] enabled.
  PluginSession<SessionPluginContext> sessionOf(PluginId pluginId) {
    for (final session in sessions) {
      if (session.isPluginEnabled(pluginId)) return session;
    }
    throw StateError('No session found with plugin "$pluginId" enabled.');
  }

  @override
  GlobalPluginContext copyWith({
    ServiceRegistry? registry,
    Map<String, Object>? extras,
    EventBus? bus,
    List<PluginSession<SessionPluginContext>>? sessions,
  }) {
    return GlobalPluginContext(
      registry: registry ?? this.registry.copy(),
      extras: extras ?? this.extras,
      bus: bus ?? this.bus,
      sessions: sessions ?? this.sessions,
    );
  }
}

/// A session-scoped context that also carries a reference to the global
/// [EventBus].
///
/// Extends [PluginContext] with a [globalBus] field so that session-scoped
/// plugins can emit or subscribe to events at the global level when needed.
class SessionPluginContext extends PluginContext {
  /// The global event bus, shared across all sessions.
  ///
  /// Use this when a session-scoped plugin needs to communicate at the
  /// global level rather than within its own session bus.
  final EventBus globalBus;

  /// Creates a session context with scoped and global runtime services.
  SessionPluginContext({
    required super.registry,
    required super.bus,
    required this.globalBus,
    super.extras,
  });

  /// Creates a minimal session context for testing.
  factory SessionPluginContext.stub({
    ServiceRegistry? registry,
    EventBus? bus,
    EventBus? globalBus,
    Map<String, Object>? extras,
  }) {
    return SessionPluginContext(
      registry: registry ?? ServiceRegistry.empty(),
      bus: bus ?? EventBus(),
      globalBus: globalBus ?? EventBus(),
      extras: extras ?? const {},
    );
  }

  @override
  SessionPluginContext copyWith({
    ServiceRegistry? registry,
    Map<String, Object>? extras,
    EventBus? bus,
    EventBus? globalBus,
  }) {
    return SessionPluginContext(
      registry: registry ?? this.registry.copy(),
      extras: extras ?? this.extras,
      bus: bus ?? this.bus,
      globalBus: globalBus ?? this.globalBus,
    );
  }
}

/// Convenience extension for broadcasting events across all active sessions.
extension SessionBroadcast on List<PluginSession> {
  /// Emits [event] on every session's bus.
  Future<void> emit<T>(T event, {String? identifier}) async {
    for (final session in this) {
      await session.bus.emit<T>(event: event, identifier: identifier);
    }
  }
}
