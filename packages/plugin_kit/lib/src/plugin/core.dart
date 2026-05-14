part of 'plugin.dart';

final _pluginLog = Logger('plugin_kit.Plugin');

/// VM-level errors that lifecycle isolation must NEVER swallow. When one of
/// these escapes a hook, propagating it lets the process die rather than
/// continuing with a corrupted runtime. Used at every framework catch site
/// in this library (Plugin, StatefulPluginService, PluginRuntime).
bool _isFatalError(Object e) =>
    e is OutOfMemoryError || e is StackOverflowError;

/// Rethrows the first step failure when there is exactly one, or wraps
/// multiple failures in a [PluginStepAggregateException]. Returns normally
/// when [stepFailures] is empty. Used by [Plugin._runAttach] and
/// [Plugin._runDetach] to surface failures to the runtime without losing
/// the concrete exception type in the single-failure case.
Never _throwAggregated(
  PluginId pluginId,
  String hook,
  List<(String, Object, StackTrace)> stepFailures,
) {
  if (stepFailures.length == 1) {
    final (_, e, st) = stepFailures.single;
    Error.throwWithStackTrace(e, st);
  }
  throw PluginStepAggregateException(pluginId, hook, stepFailures);
}

/// Well-known feature flags for plugins.
///
/// Plugins declare flags via [Plugin.featureFlags]. The runtime inspects
/// them to set default enablement: [experimental] plugins are disabled by
/// default and require opt-in; non-experimental plugins are enabled by
/// default. Custom flags can be defined by wrapping any string, e.g. `const
/// FeatureFlag('requires_network')`.
///
/// This is a zero-cost extension type wrapping [String], so flag values can
/// be compared, serialized, and stored as strings while the static type
/// still unlocks Dart's dot-shorthand syntax (`.experimental`, `.locked`).
///
/// ```dart
/// class MyPlugin extends GlobalPlugin {
///   @override
///   List<FeatureFlag> get featureFlags => const [.experimental];
/// }
/// ```
// #docregion core-feature-flag
extension type const FeatureFlag(String value) {
  /// Plugin is locked and cannot be enabled or disabled by the user.
  ///
  /// Locked plugins are always enabled and cannot be turned off via
  /// [RuntimeSettings]. This is useful for critical plugins that must always be
  /// active for the system to function.
  static const locked = FeatureFlag('locked');

  /// Plugin is experimental and requires opt-in.
  ///
  /// Experimental plugins are disabled by default and must be explicitly
  /// enabled via [RuntimeSettings]. This is useful for plugins that are
  /// still in development or not yet ready for general use.
  static const experimental = FeatureFlag('experimental');
}
// #enddocregion core-feature-flag

/// Abstract base class for all plugins in the plugin_kit system.
///
/// Defines the plugin's identity, metadata, and lifecycle hooks that the
/// [PluginRuntime] invokes during initialization, context management, and
/// teardown. Use [GlobalPlugin] for application-lifetime plugins (registered
/// once during [PluginRuntime.init], shared across all sessions) and
/// [SessionPlugin] for per-session plugins.
///
/// Lifecycle hooks for user code:
///
/// - [register] - register services into the registry; runs during
///   register-all phase before any plugin attaches.
/// - [attach] - setup hook; the plugin context is already bound when this
///   runs. Use the helpers on [PluginHelper] (`on`, `onRequest`,
///   `onRequestSync`, `bind`, `emit`) for auto-tracked subscriptions. No
///   `super.attach()` call is required - the framework drives the underlying
///   plumbing around your hook.
/// - [detach] - cleanup hook; the plugin context is still bound when this
///   runs. Tracked subscriptions and bindings are cancelled by the framework
///   after [detach] returns. No `super.detach()` call is required.
///
/// During [register], plugins populate a [ServiceRegistry] with their
/// services. Each registration carries a priority; higher priorities win
/// when multiple plugins register the same service id.
///
/// ```dart
/// @override
/// void register(ScopedServiceRegistry registry) {
///   registry.registerFactory<MyService>(
///     const ServiceId('my_service'),
///     MyServiceImpl.new,
///     priority: 100,
///   );
/// }
/// ```
///
/// Plugins are identified by both [pluginId] and [runtimeType]; two
/// instances are equal only if they share both. Runtime registration still
/// enforces unique [pluginId] values across all plugin types in one runtime.
abstract class Plugin {
  /// Unique identifier for this plugin.
  ///
  /// Used throughout the system to register and resolve services in the
  /// [ServiceRegistry], track plugin enablement in [RuntimeSettings],
  /// determine equality between plugin instances, and scope event
  /// subscriptions and service overrides.
  ///
  /// Must be unique across all plugins registered in the same [PluginRuntime].
  /// By convention, use lowercase snake_case (e.g. `'model_router'`,
  /// `'firebase_mcp'`).
  PluginId get pluginId;

  /// Plugin ids this plugin depends on. Defaults to empty.
  ///
  /// The [PluginRuntime] auto-disables a plugin whose dependency is not
  /// enabled and logs a warning. Locked plugins with unsatisfied
  /// dependencies are kept enabled and logged at severe.
  Set<PluginId> get dependencies => const {};

  /// Behavioral flags inspected by the runtime and UI to adjust plugin
  /// treatment. Defaults to empty (stable plugin, enabled by default).
  ///
  /// ```dart
  /// @override
  /// List<FeatureFlag> get featureFlags => const [
  ///   .experimental,
  ///   FeatureFlag('requires_network'),
  /// ];
  /// ```
  List<FeatureFlag> get featureFlags => const [];

  /// Per-context subscriptions, populated by [PluginHelper.on] /
  /// [PluginHelper.onRequest] / [PluginHelper.onRequestSync] at registration
  /// time. The framework cancels each context's bucket from [_runDetach]
  /// when that context tears down, so subscriptions registered for one
  /// session do not leak to another concurrent session.
  ///
  /// Identity-keyed: per-session isolation depends on each [PluginContext]
  /// instance being its own bucket. A subclass that overrides `==` /
  /// `hashCode` would otherwise collapse two sessions into one entry here.
  final Map<PluginContext, List<EventSubscription>> _subscriptionsByContext =
      Map<PluginContext, List<EventSubscription>>.identity();

  /// Per-context bindings, populated by [PluginHelper.bind]. Same teardown
  /// and identity-keyed semantics as [_subscriptionsByContext].
  final Map<PluginContext, List<void Function()>> _bindingsByContext =
      Map<PluginContext, List<void Function()>>.identity();

  /// Called when plugin settings change during an active context.
  ///
  /// Receives both the old and new [PluginContext] so the plugin can diff
  /// settings and react accordingly (e.g., reconnect to a different endpoint,
  /// update internal caches).
  ///
  /// Called for every plugin currently enabled in the new context after
  /// reconciliation. This includes plugins enabled in both old and new
  /// settings (so they can react to config changes) and plugins newly enabled
  /// by the settings change (so they can read initial config alongside later
  /// updates). Plugins disabled by the settings change go through detach.
  ///
  /// The default implementation is a no-op.
  Future<void> onPluginSettingsChanged(
    covariant PluginContext oldContext,
    covariant PluginContext newContext,
  ) async {}

  /// Register services into the service registry.
  ///
  /// Called once per context scope for each enabled plugin. Services are
  /// registered with a priority that determines resolution order; higher
  /// priority wins when multiple plugins register the same service id.
  ///
  /// The [registry] is plugin-scoped: its registration methods automatically
  /// fill in this plugin's [pluginId]. Reach through to the full registry
  /// via `registry.raw` on the rare occasions you need it.
  ///
  /// The default implementation is a no-op. Override to register services:
  ///
  /// ```dart
  /// @override
  /// void register(ScopedServiceRegistry registry) {
  ///   registry.registerSingleton<MyService>(
  ///     const ServiceId('my_service'),
  ///     () => MyServiceImpl(),
  ///     priority: 100,
  ///   );
  /// }
  /// ```
  void register(ScopedServiceRegistry registry) {}

  /// Setup hook. Override for subscriptions, timers, and other startup
  /// logic. Receives the [context] for THIS attach explicitly so the same
  /// plugin instance can be attached to multiple sessions without ambiguity.
  /// Use the helpers on [PluginHelper] (which take [context] as their first
  /// argument) for auto-tracked subscriptions. No `super.attach()` call is
  /// required - the framework drives the underlying plumbing around this
  /// hook.
  ///
  /// Plugin does NOT store [context] as a field on purpose: a session
  /// plugin instance is shared across all its sessions, and storing one
  /// context would create a contract-breaking footgun (last-attach-wins,
  /// stale references). Pass [context] explicitly into anything that needs
  /// it, or capture from this scope into a closure.
  void attach(covariant PluginContext context) {}

  /// Cleanup hook. Override for cleanup logic that needs the [context] for
  /// THIS detach. Tracked subscriptions and bindings for [context] are
  /// cancelled by the framework after this returns; no `super.detach()`
  /// call is required.
  Future<void> detach(covariant PluginContext context) async {}

  /// Framework-only. The runtime calls this when binding a plugin to a
  /// context. Library-private; user code never overrides or invokes it.
  ///
  /// `_bindContext` cannot throw (it is a single field assignment), so it
  /// is not isolated. Each stateful service's `attach()` runs in isolation:
  /// a failure is logged and the remaining services + the plugin's own
  /// [attach] still run. The plugin's [attach] runs after services, also in
  /// isolation. After every hook has been attempted, captured failures are
  /// surfaced: the original exception when exactly one step failed, or a
  /// [PluginStepAggregateException] when two or more did. This lets the
  /// runtime still collect this plugin's failure into a
  /// [PluginLifecycleException] - isolation gives peers a chance to run,
  /// it does not make errors disappear. Fatal VM errors
  /// ([OutOfMemoryError], [StackOverflowError]) are never caught.
  void _runAttach(PluginContext context) {
    final services = context.registry
        .getPluginServices(pluginId, skipFactories: true)
        .whereType<StatefulPluginService>();
    final stepFailures = <(String, Object, StackTrace)>[];
    for (final service in services) {
      service._bindContext(context);
      try {
        service.attach();
      } catch (e, st) {
        if (_isFatalError(e)) rethrow;
        _pluginLog.severe(
          'Plugin "$pluginId" service ${service.serviceId} attach() threw',
          e,
          st,
        );
        stepFailures.add(('${service.serviceId}.attach', e, st));
      }
    }
    try {
      attach(context);
    } catch (e, st) {
      if (_isFatalError(e)) rethrow;
      _pluginLog.severe('Plugin "$pluginId" attach() threw', e, st);
      stepFailures.add(('attach', e, st));
    }
    if (stepFailures.isNotEmpty) {
      _throwAggregated(pluginId, 'attach', stepFailures);
    }
  }

  /// Framework-only. The runtime calls this when tearing down a plugin's
  /// binding to a context. Library-private; user code never overrides or
  /// invokes it.
  ///
  /// Each step (user [detach], per-service [StatefulPluginService.detach] +
  /// unbind, per-context subscription cancel, per-context binding cancel)
  /// runs in isolation. A failure is logged and the rest still run, so a
  /// half-attached state from a previous failed [_runAttach] does not block
  /// teardown of the parts that did attach. After every step has been
  /// attempted, captured failures are surfaced: the original exception
  /// when exactly one step failed, or a [PluginStepAggregateException]
  /// when two or more did. Fatal VM errors ([OutOfMemoryError],
  /// [StackOverflowError]) are never caught.
  Future<void> _runDetach(PluginContext context) async {
    final stepFailures = <(String, Object, StackTrace)>[];
    try {
      await detach(context);
    } catch (e, st) {
      if (_isFatalError(e)) rethrow;
      _pluginLog.severe('Plugin "$pluginId" detach() threw', e, st);
      stepFailures.add(('detach', e, st));
    }
    final services = context.registry
        .getPluginServices(pluginId, skipFactories: true)
        .whereType<StatefulPluginService>();
    for (final service in services) {
      try {
        await service.detach();
      } catch (e, st) {
        if (_isFatalError(e)) rethrow;
        _pluginLog.severe(
          'Plugin "$pluginId" service ${service.serviceId} detach() threw',
          e,
          st,
        );
        stepFailures.add(('${service.serviceId}.detach', e, st));
      }
      // _unbindContext catches its own per-iteration cancel failures and
      // returns them as step entries; only fatal errors escape via rethrow.
      // Each returned entry already encodes its own step name (with the
      // service's serviceId), so we just merge them into the outer list.
      stepFailures.addAll(await service._unbindContext());
    }
    // Snapshot the buckets via .remove (which copies the reference and
    // detaches it from the map). Iterating the detached list means a stream's
    // onCancel callback that re-enters the helpers and mutates the live
    // bucket can't trigger ConcurrentModificationError.
    final subs = _subscriptionsByContext.remove(context);
    if (subs != null) {
      for (final sub in subs) {
        try {
          await sub.cancel();
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _pluginLog.severe(
            'Plugin "$pluginId" subscription cancel threw during detach',
            e,
            st,
          );
          stepFailures.add(('subscription.cancel', e, st));
        }
      }
    }
    // Re-entry detection: if a cancel callback re-entered Plugin.on(context,
    // ...) during the loop, the helper recreated a fresh bucket for this
    // context (`_subscriptionsByContext[context] ??= []`). Those new entries
    // would never be cancelled in this detach pass. Surface as a step
    // failure so the misuse bubbles to PluginLifecycleException instead of
    // leaking silently.
    final leakedSubs = _subscriptionsByContext.remove(context);
    if (leakedSubs != null && leakedSubs.isNotEmpty) {
      stepFailures.add((
        'subscription.leak',
        StateError(
          '${leakedSubs.length} plugin subscription(s) were registered on '
          '"$pluginId" during _runDetach (re-entrant on(context, ...) inside '
          'a sub.cancel callback). Re-subscribing during teardown is not '
          'supported; the new entries have been dropped without being '
          'cancelled.',
        ),
        StackTrace.current,
      ));
    }
    final bindings = _bindingsByContext.remove(context) ?? const [];
    for (final cancel in bindings) {
      try {
        cancel();
      } catch (e, st) {
        if (_isFatalError(e)) rethrow;
        _pluginLog.severe(
          'Plugin "$pluginId" binding cancel threw during detach',
          e,
          st,
        );
        stepFailures.add(('binding.cancel', e, st));
      }
    }
    final leakedBindings = _bindingsByContext.remove(context);
    if (leakedBindings != null && leakedBindings.isNotEmpty) {
      stepFailures.add((
        'binding.leak',
        StateError(
          '${leakedBindings.length} plugin binding(s) were registered on '
          '"$pluginId" during _runDetach (re-entrant bind(context, ...) '
          'inside a binding-cancel callback). Re-binding during teardown is '
          'not supported; the new entries have been dropped without being '
          'cancelled.',
        ),
        StackTrace.current,
      ));
    }
    if (stepFailures.isNotEmpty) {
      _throwAggregated(pluginId, 'detach', stepFailures);
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is Plugin && pluginId == other.pluginId;
  }

  @override
  int get hashCode => Object.hash(runtimeType, pluginId);

  @override
  String toString() => '$runtimeType(pluginId: $pluginId)';
}

/// A [Plugin] scoped to the global application lifetime.
///
/// Global plugins are initialized once during [PluginRuntime.init] and
/// disposed when the runtime itself is disposed. They are shared across all
/// sessions.
///
/// The type parameter [G] narrows the `context` parameter on [attach] /
/// [detach] so user code sees the concrete [GlobalPluginContext] subclass
/// and can read domain-specific fields without casts.
///
/// ```dart
/// class AppConfigPlugin extends GlobalPlugin<MyGlobalContext> {
///   @override
///   PluginId get pluginId => const PluginId('app_config');
///
///   @override
///   void register(ScopedServiceRegistry registry) {
///     registry.registerSingleton<AppConfig>(
///       const ServiceId('app_config'),
///       () => AppConfig.load(),
///       priority: 100,
///     );
///   }
///
///   @override
///   void attach(MyGlobalContext context) {
///     on<ConfigChangedEvent>(context, (e) {
///       // React to changes; e.event is ConfigChangedEvent.
///       // Context is typed as MyGlobalContext.
///     });
///   }
/// }
/// ```
abstract class GlobalPlugin<G extends GlobalPluginContext> extends Plugin {
  @override
  void attach(G context) {}

  @override
  Future<void> detach(G context) async {}
}

/// A [Plugin] scoped to an individual session lifetime.
///
/// Session plugins are initialized during [PluginRuntime.createSession] and
/// disposed when the session ends. Each session shares the same plugin
/// instance with other sessions, but [register] runs per-session so each
/// session gets its own service instances (constructed inline at the call
/// site) and its own subscription bucket inside the plugin.
///
/// The type parameter [S] narrows the `context` parameter on [attach] /
/// [detach] so user code sees the concrete [SessionPluginContext] subclass
/// and can read domain-specific fields without casts.
///
/// ```dart
/// class GreeterPlugin extends SessionPlugin<MySessionContext> {
///   @override
///   PluginId get pluginId => const PluginId('greeter');
///
///   @override
///   void register(ScopedServiceRegistry registry) {
///     registry.registerSingleton<GreeterService>(
///       const ServiceId('greeter_service'),
///       () => GreeterService(),
///       priority: 100,
///     );
///   }
///
///   @override
///   void attach(MySessionContext context) {
///     on<SessionStartedEvent>(context, (e) {
///       final greeter = context.resolve<GreeterService>(
///         const ServiceId('greeter_service'),
///       );
///       greeter.greet();
///     });
///   }
/// }
/// ```
abstract class SessionPlugin<S extends SessionPluginContext> extends Plugin {
  @override
  void attach(S context) {}

  @override
  Future<void> detach(S context) async {}
}
