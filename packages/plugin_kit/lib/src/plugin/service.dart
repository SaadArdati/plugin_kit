part of 'plugin.dart';

/// Base class for plugin services that receive injected settings.
///
/// A [PluginService] is registered in the [ServiceRegistry] by a [Plugin]. The
/// registry calls [injectSettings] with the service's scoped configuration
/// from any matching [LocalPluginOverride]. The [config] property exposes the
/// settings as a [ConfigNode] for typed access.
///
/// Lifecycle: the plugin calls one of the registry's `register*` methods.
/// `registerSingleton` takes a pre-built instance constructed inline at the
/// call site; `registerLazySingleton` and `registerFactory` take a
/// `Factory<T>` invoked on first / every resolve respectively. Whichever
/// path produces the instance, the registry stamps [pluginId] and
/// [serviceId] on it before [injectSettings] runs. Subclasses do not pass
/// those identity fields to `super()`.
///
/// For services that also need session lifecycle hooks, use
/// [StatefulPluginService].
///
/// ```dart
/// class MyModelService extends PluginService {
///   String get provider => config.get<String>('provider') ?? 'default';
///   String get model => config.get<String>('model') ?? 'gpt-4';
/// }
/// ```
abstract class PluginService {
  /// Plugin that owns this service. Stamped on every resolve by
  /// [ServiceRegistry]. Reading before resolution throws
  /// `LateInitializationError`.
  late PluginId pluginId;

  /// Full registry key for this service (e.g. `main_agent.agent_service`).
  /// Stamped on every resolve. Reading before resolution throws
  /// `LateInitializationError`.
  late ServiceId serviceId;

  Map<String, dynamic> _settings;

  /// Raw settings injected by the registry. Prefer [config] for typed access.
  Map<String, dynamic> get settings => _settings;

  String _settingsHash = '-1';

  /// Hash of the current settings, used by the registry to skip redundant
  /// [injectSettings] calls on singleton and lazy-singleton services.
  String get settingsHash => _settingsHash;

  /// Type-safe accessor over [settings].
  ConfigNode config = ConfigNode(const {});

  /// Creates a service with empty injected settings.
  PluginService() : _settings = const {};

  /// Inject settings from the registry. Framework entry point and
  /// orchestrator; do not override.
  ///
  /// Called by [ServiceRegistry.resolve] (and variants) when the service is
  /// created or refreshed. The [settings] map is already scoped to this
  /// service via the matching [LocalPluginOverride]. For singleton and
  /// lazy-singleton services the registry passes a pre-computed [hash] to
  /// skip redundant updates; when null it is computed from [settings].
  ///
  /// This method does the bookkeeping (settings storage, hash, config
  /// rebuild) and then calls the user-overridable [onSettingsInjected]
  /// hook. To react to settings changes, override [onSettingsInjected] and
  /// read [config] / [settings] there; no super call is needed.
  @nonVirtual
  void injectSettings(Map<String, dynamic> settings, {String? hash}) {
    _settingsHash = hash ?? ConfigNode.hashSettings(settings);
    _settings = settings;
    config = ConfigNode({...settings});
    onSettingsInjected();
  }

  /// User-overridable hook fired AFTER [injectSettings] finishes writing
  /// [settings], [settingsHash], and [config]. Default is a no-op.
  ///
  /// Override to react to settings changes (re-derive cached values, swap
  /// upstream connections, etc.). Read fresh values via [config] (typed)
  /// or [settings] (raw); the framework has already updated both by the
  /// time this runs.
  ///
  /// No super call needed; the framework runs the bookkeeping before
  /// invoking this hook.
  void onSettingsInjected() {}
}

/// A [PluginService] with session lifecycle and automatic subscription
/// cleanup.
///
/// Override [attach] for setup that should run when the owning plugin is
/// attached, and [detach] for cleanup. Both are pure user hooks: the
/// framework binds and unbinds the session context around them, so:
///
/// - In [attach], [context] is already bound and the helpers in
///   [StatefulPluginServiceHelper] (`on`, `onRequest`, `onRequestSync`,
///   `bind`, `emit`) can be used directly. No `super.attach()` call is
///   needed.
/// - In [detach], [context] is still bound so cleanup logic can use it. No
///   `super.detach()` call is needed; tracked subscriptions and bindings
///   are cancelled by the framework after [detach] returns.
///
/// The type parameter [PKC] is the concrete [PluginContext] subclass this
/// service expects, allowing access to domain-specific context fields.
///
/// ```dart
/// class MyStatefulService extends StatefulPluginService<PluginContext> {
///   @override
///   void attach() {
///     on<UserMessage>((msg) {
///       // Subscription auto-tracked, cancelled after detach() returns.
///     });
///   }
/// }
/// ```
abstract class StatefulPluginService<PKC extends PluginContext>
    extends PluginService {
  /// Subscriptions cancelled automatically by the framework after [detach]
  /// returns.
  final List<EventSubscription> activeSubscriptions = [];

  /// Bindings registered through [StatefulPluginServiceHelper.bind].
  /// Each entry is the cancel callback returned by `EventBus.bind`; the
  /// framework invokes them after [detach] returns.
  final List<void Function()> activeBindings = [];

  PKC? _context;

  /// Creates a stateful service with no bound context.
  StatefulPluginService();

  /// Whether a context is currently bound (between [attach] and [detach]).
  bool get hasContext => _context != null;

  /// The current session context. Throws [StateError] if accessed outside the
  /// attach/detach window.
  PKC get context {
    final ctx = _context;
    if (ctx == null) {
      throw StateError(
        'Plugin service context is not set. You cannot access the context before attach() and after detach().',
      );
    }
    return ctx;
  }

  /// Framework-only. Called by [Plugin._runAttach] before [attach] runs to
  /// bind the session context. Library-private; user code never calls this.
  void _bindContext(PKC context) {
    _context = context;
  }

  /// Framework-only. Called by [Plugin._runDetach] after [detach] returns to
  /// cancel tracked subscriptions/bindings and clear the bound context.
  /// Library-private; user code never calls this.
  ///
  /// Each `sub.cancel()` and binding cancel runs in isolation: a failure
  /// is logged and the rest still run, so one bad cancel never strands
  /// other cancellations or leaves [_context] set. After every cancel has
  /// been attempted, [_context] is cleared unconditionally.
  ///
  /// Returns the per-iteration step failures so [Plugin._runDetach] can
  /// merge each one into the outer aggregate as its own step entry rather
  /// than collapsing them all under a single `<service>.unbind` label.
  /// Fatal VM errors are not caught and bypass the return path entirely.
  ///
  /// Iteration runs over a snapshot of [activeSubscriptions] /
  /// [activeBindings] so a stream's `onCancel` callback that re-enters the
  /// helpers and mutates the live lists cannot trigger
  /// [ConcurrentModificationError] mid-loop.
  Future<List<(String, Object, StackTrace)>> _unbindContext() async {
    final stepFailures = <(String, Object, StackTrace)>[];
    final List<EventSubscription> subsSnapshot = [...activeSubscriptions];
    activeSubscriptions.clear();
    for (final sub in subsSnapshot) {
      try {
        await sub.cancel();
      } catch (e, st) {
        if (_isFatalError(e)) rethrow;
        _pluginLog.severe(
          '$serviceId subscription cancel threw during unbind',
          e,
          st,
        );
        stepFailures.add(('$serviceId.subscription.cancel', e, st));
      }
    }
    // Re-entry detection: if a stream's onCancel callback re-entered the
    // helpers and called `on(...)` / `onRequest(...)`, those new entries
    // landed in the just-cleared activeSubscriptions list and would never
    // be cancelled in this teardown pass. Surface as a step failure so
    // the caller plugin's failed-detach bubbles to PluginLifecycleException
    // and the developer sees the misuse instead of a silent leak.
    if (activeSubscriptions.isNotEmpty) {
      final leaked = activeSubscriptions.length;
      activeSubscriptions.clear();
      stepFailures.add((
        '$serviceId.subscription.leak',
        StateError(
          '$leaked subscription(s) were registered on $serviceId during '
          '_unbindContext (re-entrant on(...) inside a sub.cancel callback). '
          'Re-subscribing during teardown is not supported; the new entries '
          'have been dropped without being cancelled.',
        ),
        StackTrace.current,
      ));
    }
    final bindingsSnapshot = [...activeBindings];
    activeBindings.clear();
    for (final cancel in bindingsSnapshot) {
      try {
        cancel();
      } catch (e, st) {
        if (_isFatalError(e)) rethrow;
        _pluginLog.severe(
          '$serviceId binding cancel threw during unbind',
          e,
          st,
        );
        stepFailures.add(('$serviceId.binding.cancel', e, st));
      }
    }
    if (activeBindings.isNotEmpty) {
      final leaked = activeBindings.length;
      activeBindings.clear();
      stepFailures.add((
        '$serviceId.binding.leak',
        StateError(
          '$leaked binding(s) were registered on $serviceId during '
          '_unbindContext (re-entrant bind(...) inside a binding-cancel '
          'callback). Re-binding during teardown is not supported; the new '
          'entries have been dropped without being cancelled.',
        ),
        StackTrace.current,
      ));
    }
    _context = null;
    return stepFailures;
  }

  /// Setup hook. Override for subscriptions, timers, and other startup
  /// logic. The session context is already bound when this runs; access via
  /// [context] or use the helpers on [StatefulPluginServiceHelper] which
  /// auto-track their subscriptions. No `super.attach()` call required.
  void attach() {}

  /// Cleanup hook. Override for cleanup logic that needs to run while the
  /// session context is still bound. Tracked subscriptions and bindings are
  /// cancelled by the framework after this returns; no `super.detach()`
  /// call required.
  Future<void> detach() async {}
}

/// Optional alias for [StatefulPluginService] specialised to
/// [SessionPluginContext].
///
/// Pure syntactic sugar. `extends SessionStatefulPluginService` is identical
/// to `extends StatefulPluginService` at runtime; the
/// alias just removes the need to spell out the type argument when the
/// service is session-scoped and uses the conventional context. Use the
/// explicit generic form when the service uses a custom session context
/// subclass: `extends StatefulPluginService<MyAppSessionContext>`.
typedef SessionStatefulPluginService<S extends SessionPluginContext> =
    StatefulPluginService<S>;

/// Optional alias for [StatefulPluginService] specialised to
/// [GlobalPluginContext].
///
/// Pure syntactic sugar. Same role as [SessionStatefulPluginService] for
/// global-scoped services. Use the explicit generic form
/// (`extends StatefulPluginService<MyAppGlobalContext>`) when the service
/// uses a custom global context subclass.
typedef GlobalStatefulPluginService<G extends GlobalPluginContext> =
    StatefulPluginService<G>;
