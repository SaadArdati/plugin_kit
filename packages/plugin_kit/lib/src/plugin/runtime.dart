part of 'plugin.dart';

final _runtimeLog = Logger('plugin_kit.PluginRuntime');
final _sessionLog = Logger('plugin_kit.PluginSession');

bool _isReservedPluginId(String value) => value.startsWith('__pk_');

/// Builds the global plugin context from runtime services.
typedef GlobalContextFactory<
  G extends GlobalPluginContext,
  S extends SessionPluginContext
> =
    G Function(
      ServiceRegistry registry,
      EventBus bus,
      List<PluginSession<S>> sessions,
    );

/// Builds a session plugin context from session and global services.
typedef SessionContextFactory<
  G extends GlobalPluginContext,
  S extends SessionPluginContext
> =
    S Function(
      ServiceRegistry registry,
      EventBus sessionBus,
      EventBus globalBus,
    );

/// The central runtime that manages the full plugin lifecycle.
///
/// Drives plugin initialization, session creation, settings reconciliation,
/// and disposal. Manages a unified plugin list with two scopes: [GlobalPlugin]s
/// register once during [init] and persist for the application lifetime,
/// sharing a single [globalRegistry] and [globalBus]; [SessionPlugin]s are
/// created per-session with their own [ServiceRegistry] and [EventBus].
///
/// Lifecycle:
///
/// 1. `addPlugin(s)`: register plugin instances.
/// 2. `init(settings)`: initialize the global scope; create [globalRegistry]
///    and [globalBus]; call `register()` then `attach()` on enabled
///    [GlobalPlugin]s.
/// 3. `createSession(settings, contextFactory?)`: determine enabled
///    [SessionPlugin]s, build a session [ServiceRegistry] and [EventBus],
///    register them, apply wildcard overrides, create the context, then
///    attach.
/// 4. `updateSessionSettings()` / `updateGlobalSettings()`: reconcile changes.
/// 5. `dispose()`: tear down everything.
///
/// Type parameters: [G] is the global context class (`GlobalPluginContext` or
/// a subtype); [S] is the session context class (`SessionPluginContext` or a
/// subtype).
///
/// Plugin enablement falls back through three rules in order: explicit
/// [RuntimeSettings.plugins] entry, [FeatureFlag.locked] (always on),
/// [FeatureFlag.experimental] (default off). Non-experimental plugins
/// with no explicit setting default to enabled.
class PluginRuntime<
  G extends GlobalPluginContext,
  S extends SessionPluginContext
> {
  /// The global service registry shared across the application.
  late final ServiceRegistry globalRegistry;

  /// The global event bus shared across the application.
  late final EventBus globalBus;

  final List<Plugin> _plugins = [];

  /// Unmodifiable view of registered plugins.
  List<Plugin> get plugins => List.unmodifiable(_plugins);

  /// Returns only [GlobalPlugin] instances from the registered plugins.
  List<GlobalPlugin> get globalPlugins =>
      _plugins.whereType<GlobalPlugin>().toList();

  /// Returns only [SessionPlugin] instances from the registered plugins.
  List<SessionPlugin> get sessionPlugins =>
      _plugins.whereType<SessionPlugin>().toList();

  final List<PluginSession<S>> _sessions = [];

  /// Unmodifiable view of active sessions.
  List<PluginSession<S>> get sessions => List.unmodifiable(_sessions);

  /// Context for global plugins.
  late final G globalContext;

  /// Tracks enabled and attached global plugin IDs.
  final Set<PluginId> _enabledGlobalPluginIds = {};

  /// Global plugin ids currently attached at runtime.
  Set<PluginId> get attachedGlobalPluginIds =>
      Set.unmodifiable(_enabledGlobalPluginIds);

  /// Whether [init] has been called. Used to guard [dispose] against
  /// accessing late-initialized fields before initialization.
  bool _initialized = false;

  /// How to react when [RuntimeSettings] entries reference an id the
  /// runtime does not know about (plugin ids in either map, service
  /// ids in a pin whose plugin exists but does not register that
  /// slot). Set via [init]; defaults to
  /// [UnknownReferencePolicy.throwError] so the base package stays
  /// strict and surfaces drift loudly. Production callers that load
  /// cached settings across app upgrades should pass
  /// [UnknownReferencePolicy.logAndSkip] explicitly.
  UnknownReferencePolicy _unknownReferencePolicy =
      UnknownReferencePolicy.throwError;

  // Re-created on each [init] so the runtime can be re-initialized after
  // [dispose]. The original `late final` declaration was permanently closed
  // by dispose() and could not be reused, which contradicted the doc on
  // [init] that calls out re-init support.
  late StreamController<RuntimeSettings> _settingsController;

  /// True while a settings-reconciliation pass
  /// ([updateSettings] / [updateGlobalSettings] / [updateSessionSettings])
  /// is in flight. Concurrent reconciliations are rejected because they
  /// would interleave across `await` boundaries and corrupt shared state
  /// (`_enabledGlobalPluginIds`, registries, the session list).
  ///
  /// The docs already require callers to serialize toggles. This flag
  /// makes the contract loud rather than letting silent interleaving
  /// produce drift.
  bool _reconciling = false;

  late RuntimeSettings _settings = const RuntimeSettings();

  /// The current [RuntimeSettings] snapshot.
  ///
  /// Initialized to `const RuntimeSettings()` (an empty snapshot) on
  /// construction, replaced by the `settings` argument passed to [init] (when
  /// non-null), and updated by [updateSettings], [updateSettingsSnapshot], and
  /// [resetSettings].
  RuntimeSettings get settings => _settings;

  set _settingsValue(RuntimeSettings value) {
    _settings = value;
    _settingsController.add(value);
  }

  /// Broadcast stream that emits whenever [settings] changes.
  ///
  /// New subscribers do not receive the current value; read [settings] for
  /// the latest snapshot.
  ///
  /// Reading this getter before [init] throws `LateInitializationError`
  /// (the underlying controller is constructed in `init`). The debug-only
  /// assertion below surfaces a clearer message during development; in
  /// release builds the lower-level error still propagates.
  Stream<RuntimeSettings> get settingsStream {
    assert(
      _initialized,
      'PluginRuntime.settingsStream read before init(). Call init() first.',
    );
    return _settingsController.stream;
  }

  /// Creates a runtime seeded with optional initial [plugins].
  ///
  /// Pass no arguments (or omit [plugins]) for an empty runtime; call
  /// [addPlugin] / [addPlugins] before [init] to register additional
  /// plugins.
  PluginRuntime({List<Plugin>? plugins}) {
    _plugins.addAll([...?plugins]);
  }

  /// Add a plugin to the runtime.
  ///
  /// Plugins are routed by type:
  /// - [GlobalPlugin] participates in `register` → `attach` → `detach` at global scope.
  /// - [SessionPlugin] participates in `register` → `attach` → `detach` at session scope.
  ///
  /// Throws [StateError] if a plugin with the same [Plugin.pluginId]
  /// is already registered.
  void addPlugin(Plugin plugin) {
    if (_isReservedPluginId(plugin.pluginId)) {
      throw ArgumentError.value(
        plugin.pluginId,
        'plugin.pluginId',
        'PluginId values starting with "__pk_" are reserved for internal use.',
      );
    }

    if (_plugins.any((p) => p.pluginId == plugin.pluginId)) {
      throw StateError('Plugin ${plugin.pluginId} is already registered');
    }

    _plugins.add(plugin);
  }

  /// Add multiple plugins at once.
  void addPlugins(List<Plugin> plugins) {
    for (final plugin in plugins) {
      addPlugin(plugin);
    }
  }

  /// Initialized here instead of at the field level directly to allow
  /// re-initialization.
  ///
  /// [globalContextFactory] allows callers to supply a custom [G] constructor.
  /// When null, a default [GlobalPluginContext] is created and cast to [G].
  ///
  /// [unknownReferencePolicy] controls how the runtime responds when
  /// [RuntimeSettings] references plugin or service ids that this
  /// runtime does not know about (typically a typo, a renamed id, or
  /// cached user settings written by a prior app version). Defaults to
  /// [UnknownReferencePolicy.throwError]: the base package stays strict
  /// so drift is loud during development and CI. Production load paths
  /// that read cached settings across app upgrades should pass
  /// [UnknownReferencePolicy.logAndSkip] so a renamed id does not
  /// crash app startup. See [UnknownReferencePolicy] for all three
  /// modes.
  PluginRuntime init({
    RuntimeSettings? settings,
    GlobalContextFactory<G, S>? globalContextFactory,
    UnknownReferencePolicy unknownReferencePolicy =
        UnknownReferencePolicy.throwError,
  }) {
    // Defensive: if init() is called a second time without dispose() in
    // between, the previous controller is still alive and would leak when
    // we reassign the field below. Close it first. This is a programming
    // error (the documented flow is init -> use -> dispose -> init), but
    // we handle it gracefully rather than silently leaking.
    if (_initialized && !_settingsController.isClosed) {
      _settingsController.close();
    }
    _initialized = true;
    _unknownReferencePolicy = unknownReferencePolicy;
    _settingsController = StreamController<RuntimeSettings>.broadcast(
      sync: true,
    );
    _runtimeLog.info('Initializing runtime');

    if (settings != null) {
      _settingsValue = settings;
    }

    globalBus = EventBus();

    final effectiveSettings = settings ?? RuntimeSettings();
    _validateServiceSettingPluginIds(
      entryPoint: 'init',
      services: effectiveSettings.services,
    );
    _validatePluginConfigPluginIds(
      entryPoint: 'init',
      plugins: effectiveSettings.plugins,
    );

    // Parse service settings into overrides for the global registry.
    final overrides = <LocalPluginOverride>[];
    final pendingWildcards = <ServiceId, ServiceSettings>{};
    _partitionServiceSettings(
      services: effectiveSettings.services,
      overrides: overrides,
      pendingWildcards: pendingWildcards,
      plugins: globalPlugins,
    );

    globalRegistry = ServiceRegistry(overrides: overrides);

    // Determine enabled global plugins (uses _determineEnabledPluginIds
    // which correctly handles experimental flags and dependency validation).
    _enabledGlobalPluginIds.addAll(
      _determineEnabledPluginIds(
        effectiveSettings,
        pluginSubset: globalPlugins,
      ),
    );
    _runtimeLog.fine(
      'Enabled global plugins: ${_enabledGlobalPluginIds.join(', ')}',
    );

    // Register enabled global plugins. A throwing register() is the same
    // shape of bug as a throwing attach(): without rollback, the plugin
    // id stays in `_enabledGlobalPluginIds` and any partial registrations
    // it made before throwing stay live. Collect errors and roll the
    // plugin back per-plugin.
    final registerErrors = <(PluginId, Object, StackTrace)>[];
    for (final plugin in globalPlugins) {
      if (_enabledGlobalPluginIds.contains(plugin.pluginId)) {
        try {
          plugin.register(globalRegistry.scopedFor(plugin.pluginId));
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to register global plugin "${plugin.pluginId}"',
            e,
            st,
          );
          registerErrors.add((plugin.pluginId, e, st));
          _enabledGlobalPluginIds.remove(plugin.pluginId);
          final serviceIds = globalRegistry.listAllServiceIds(plugin.pluginId);
          for (final id in serviceIds) {
            globalRegistry.unregister(pluginId: plugin.pluginId, serviceId: id);
          }
        }
      }
    }
    // Throw register errors before pin-validation runs, so the user sees
    // the actual register failure rather than a downstream StateError
    // from validation against the rolled-back registry. Also unwind
    // siblings that registered successfully: this throw fires before
    // [globalContext] is initialized, so leaving siblings in
    // `_enabledGlobalPluginIds` would advertise them as attached
    // without ever running attach() and would LateInitializationError
    // on dispose.
    if (registerErrors.isNotEmpty) {
      for (final pluginId in _enabledGlobalPluginIds.toList()) {
        final serviceIds = globalRegistry.listAllServiceIds(pluginId);
        for (final id in serviceIds) {
          globalRegistry.unregister(pluginId: pluginId, serviceId: id);
        }
      }
      _enabledGlobalPluginIds.clear();
      _runtimeLog.warning(
        'Runtime register pass failed for ${registerErrors.length} plugin(s)',
      );
      throw PluginLifecycleException('attachGlobal', registerErrors);
    }
    // With every global plugin registered, the set of known service ids
    // for each plugin is now stable. Validate that every plugin-scoped
    // service pin targets a service the named plugin actually registered.
    _validateServicePinServiceIds(
      entryPoint: 'init',
      registry: globalRegistry,
      services: effectiveSettings.services,
      plugins: globalPlugins,
    );
    // Create global context
    if (globalContextFactory != null) {
      globalContext = globalContextFactory(
        globalRegistry,
        globalBus,
        _sessions,
      );
    } else {
      if (G != GlobalPluginContext) {
        throw StateError(
          'globalContextFactory is required when using a custom global context '
          'type ($G). The default factory creates a GlobalPluginContext, which '
          'cannot be assigned to $G.',
        );
      }
      globalContext =
          GlobalPluginContext(
                registry: globalRegistry,
                bus: globalBus,
                sessions: _sessions,
              )
              as G;
    }

    // Apply wildcard overrides and inject all settings into global services.
    _resolveAndApplyWildcards(
      registry: globalRegistry,
      pendingWildcards: pendingWildcards,
      overrides: overrides,
    );
    if (pendingWildcards.isEmpty && overrides.isNotEmpty) {
      globalRegistry.updateSettings(overrides: overrides);
    }

    // Attach enabled plugins. Per-plugin rollback on failure (option a):
    // a failed attach() removes the plugin from [_enabledGlobalPluginIds]
    // and unregisters its services, so attached/enabled tracking equals
    // reality. Successfully-attached siblings stay attached. Subscriptions
    // opened in attach() before the throw stay live until process exit
    // because sync init() cannot await `_unbindContext`, and dispose()
    // does not re-detach the rolled-back plugin. Option (b) async init
    // replaces this with a proper unwind; see
    // docs/superpowers/plans/2026-05-13-runtime-correctness-followups.md.
    final attachErrors = <(PluginId, Object, StackTrace)>[];
    for (final plugin in globalPlugins) {
      if (_enabledGlobalPluginIds.contains(plugin.pluginId)) {
        try {
          plugin._runAttach(globalContext);
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to attach global plugin "${plugin.pluginId}"',
            e,
            st,
          );
          attachErrors.add((plugin.pluginId, e, st));
          _enabledGlobalPluginIds.remove(plugin.pluginId);
          final serviceIds = globalRegistry.listAllServiceIds(plugin.pluginId);
          for (final id in serviceIds) {
            globalRegistry.unregister(pluginId: plugin.pluginId, serviceId: id);
          }
        }
      }
    }

    if (attachErrors.isNotEmpty) {
      _runtimeLog.warning(
        'Runtime initialized with ${attachErrors.length} plugin failure(s)',
      );
      throw PluginLifecycleException('attachGlobal', attachErrors);
    }
    _runtimeLog.info('Runtime initialized');

    return this;
  }

  /// Create a session in a single call.
  ///
  /// Combines plugin registration, context creation, and plugin attachment
  /// into one operation.
  ///
  /// [contextFactory] receives the session's [ServiceRegistry], a fresh
  /// [EventBus] for the session, and the [globalBus]. Return your
  /// domain-specific [S] from it. When null, a default [SessionPluginContext]
  /// is created and cast to [S].
  ///
  /// Example:
  /// ```dart
  /// final session = await runtime.createSession(
  ///   settings: mySettings,
  ///   contextFactory: (registry, sessionBus, globalBus) => MySessionContext(
  ///     registry: registry,
  ///     bus: sessionBus,
  ///     globalBus: globalBus,
  ///     myField: myValue,
  ///   ),
  /// );
  /// ```
  Future<PluginSession<S>> createSession({
    RuntimeSettings? settings,
    SessionContextFactory<G, S>? contextFactory,
  }) async {
    if (!_initialized) {
      throw StateError(
        'PluginRuntime.createSession() called before init(). '
        'Call init() first to initialize the global scope.',
      );
    }

    settings ??= this.settings;

    _validateServiceSettingPluginIds(
      entryPoint: 'createSession',
      services: settings.services,
    );
    _validatePluginConfigPluginIds(
      entryPoint: 'createSession',
      plugins: settings.plugins,
    );

    final overrides = <LocalPluginOverride>[];
    final pendingWildcards = <ServiceId, ServiceSettings>{};

    _partitionServiceSettings(
      services: settings.services,
      overrides: overrides,
      pendingWildcards: pendingWildcards,
      plugins: sessionPlugins,
    );

    final enabledPluginIds = _determineEnabledPluginIds(
      settings,
      pluginSubset: sessionPlugins,
      additionalEnabledPluginIds: _enabledGlobalPluginIds,
    );

    final registry = ServiceRegistry(overrides: overrides);

    // Register enabled session plugins
    for (final plugin in sessionPlugins) {
      if (enabledPluginIds.contains(plugin.pluginId)) {
        plugin.register(registry.scopedFor(plugin.pluginId));
      }
    }

    // Validate service pin service ids now that the registry is populated.
    _validateServicePinServiceIds(
      entryPoint: 'createSession',
      registry: registry,
      services: settings.services,
      plugins: sessionPlugins,
    );

    // Resolve wildcard winner-scoped overrides now that services are registered
    _resolveAndApplyWildcards(
      registry: registry,
      pendingWildcards: pendingWildcards,
      overrides: overrides,
    );

    // Create session bus and context
    final sessionBus = EventBus();

    final S context;
    if (contextFactory != null) {
      context = contextFactory(registry, sessionBus, globalBus);
    } else {
      if (S != SessionPluginContext) {
        throw StateError(
          'contextFactory is required when using a custom session context '
          'type ($S). The default factory creates a SessionPluginContext, '
          'which cannot be assigned to $S.',
        );
      }
      context =
          SessionPluginContext(
                registry: registry,
                bus: sessionBus,
                globalBus: globalBus,
              )
              as S;
    }

    final session = PluginSession<S>(
      registry: registry,
      bus: sessionBus,
      context: context,
      plugins: List.unmodifiable(sessionPlugins),
      settings: settings,
    );

    // Session buses are independent of the global bus. Global plugins that
    // want to broadcast to sessions do so explicitly via the
    // `GlobalPluginContext.sessions.emit(...)` extension; session plugins that
    // want to reach the global scope emit on `context.globalBus`. There is no
    // implicit forwarding between the two.
    session._onDispose = () {
      _sessions.remove(session);
    };

    // Track enabled plugins so `session.init()` knows which plugins to
    // attach. The session is NOT yet visible via `runtime.sessions` -
    // we only publish it after init() succeeds. If init throws, the
    // half-attached session is dropped on the floor (the caller's
    // reference becomes unreachable after the rethrow).
    for (final pluginId in enabledPluginIds) {
      session.markPluginEnabled(pluginId);
    }

    try {
      await session.init();
    } catch (e) {
      // session.init aggregates per-plugin attach failures. Some plugins
      // may have attached successfully before another threw; all
      // partial state in this dropped session needs cleanup before we
      // throw away the session reference. Walk every enabled plugin
      // and best-effort detach. Cleanup failures are swallowed; the
      // original PluginLifecycleException is what the caller sees.
      for (final plugin in sessionPlugins) {
        if (!session.isPluginEnabled(plugin.pluginId)) continue;
        try {
          await plugin._runDetach(session.context);
        } catch (_) {}
      }
      // Dispose the session's bus so its broadcast controller is closed
      // and any lingering observers stop receiving events from an
      // orphan session.
      try {
        sessionBus.dispose();
      } catch (_) {}
      rethrow;
    }

    // Publish only after successful attach so `runtime.sessions` never
    // contains a session whose lifecycle failed.
    _sessions.add(session);

    _runtimeLog.info(
      'Session created with ${enabledPluginIds.length} enabled plugins',
    );

    return session;
  }

  /// Update session settings with full reconciliation.
  ///
  /// Applies [newSettings] and determines which plugins need to be enabled,
  /// disabled, or notified of changes:
  ///
  /// 1. Parse new service settings into overrides.
  /// 2. Reconcile plugin enablement (disable/detach or enable/register/attach).
  /// 3. Apply wildcard overrides.
  /// 4. Update the registry's override list.
  /// 5. Notify remaining enabled plugins via [Plugin.onPluginSettingsChanged].
  Future<void> updateSessionSettings(
    PluginSession<S> session, {
    required RuntimeSettings newSettings,
  }) async {
    _enterReconcile('updateSessionSettings');
    try {
      _validateServiceSettingPluginIds(
        entryPoint: 'updateSessionSettings',
        services: newSettings.services,
      );
      _validatePluginConfigPluginIds(
        entryPoint: 'updateSessionSettings',
        plugins: newSettings.plugins,
      );
      await _updateSessionSettingsInternal(session, newSettings: newSettings);
    } finally {
      _reconciling = false;
    }
  }

  /// Body of [updateSessionSettings] without the re-entry guard. Used by
  /// [updateSettings] which already holds the guard for the whole pass.
  Future<void> _updateSessionSettingsInternal(
    PluginSession<S> session, {
    required RuntimeSettings newSettings,
  }) async {
    final oldContext = session.context.copyWith();
    // Strict runtimeType equality is intentionally over-constrained for now:
    // the bug we're guarding against only requires `oldContext` to be
    // assignable to whatever the plugin's covariant `onPluginSettingsChanged`
    // declares. If the framework ever grows "context promotion" semantics
    // (subclass on snapshot, base type on live, or vice versa), weaken this
    // to an `is`-check that matches the plugin's declared type.
    assert(
      oldContext.runtimeType == session.context.runtimeType,
      'Custom context subclass ${session.context.runtimeType} did not override '
      'copyWith(); onPluginSettingsChanged will receive a base-type oldContext '
      'and any covariant subtype override on the plugin will throw TypeError. '
      'See concepts/custom-context for the required override shape.',
    );

    final overrides = <LocalPluginOverride>[];
    final pendingWildcards = <ServiceId, ServiceSettings>{};
    _partitionServiceSettings(
      services: newSettings.services,
      overrides: overrides,
      pendingWildcards: pendingWildcards,
      plugins: sessionPlugins,
    );

    final enabledPluginIds = _determineEnabledPluginIds(
      newSettings,
      pluginSubset: sessionPlugins,
      additionalEnabledPluginIds: _enabledGlobalPluginIds,
    );

    final registry = session.registry;
    await _reconcilePluginsOnSettingsUpdate(
      registry: registry,
      enabledPluginIds: enabledPluginIds,
      overrides: overrides,
      session: session,
    );
    _runtimeLog.info('Session settings updated');

    // Validate service pin service ids after reconciliation: any plugins
    // newly enabled by this pass have registered, so the registry now
    // reflects every service id that should be addressable.
    _validateServicePinServiceIds(
      entryPoint: 'updateSessionSettings',
      registry: registry,
      services: newSettings.services,
      plugins: sessionPlugins,
    );

    // Snapshot attached stateful services BEFORE the override flip below
    // (which can be triggered by either _resolveAndApplyWildcards or the
    // unconditional registry.updateSettings call). The post-flip diff
    // detaches services that just flipped to disabled and attaches those
    // that flipped to enabled.
    final preAttached = _snapshotAttachedStatefulServices(
      registry: registry,
      pluginIds: enabledPluginIds,
    );

    _resolveAndApplyWildcards(
      registry: registry,
      pendingWildcards: pendingWildcards,
      overrides: overrides,
    );

    registry.updateSettings(overrides: overrides);

    final serviceErrors = await _reconcileServiceLifecycleDiff(
      registry: registry,
      pluginIds: enabledPluginIds,
      preAttached: preAttached,
      context: session.context,
    );

    // Notify each plugin that settings have been updated
    for (final pluginId in enabledPluginIds) {
      final plugin = _plugins.firstWhereOrNull((p) => p.pluginId == pluginId);
      if (plugin != null) {
        await plugin.onPluginSettingsChanged(oldContext, session.context);
      }
    }

    if (serviceErrors.isNotEmpty) {
      throw PluginLifecycleException('updateSessionSettings', serviceErrors);
    }
  }

  // ---- Helpers ----
  //
  // Service settings pipeline
  //
  // RuntimeSettings.services maps scoped keys to ServiceSettings. Each scoped
  // key is either plugin-specific ('pluginA:agent.model', targets pluginA's
  // agent.model registration) or wildcard ('*:agent.model', targets whoever
  // wins agent.model right now).
  //
  // Pipeline (run on init, createSession, and updateSettings):
  //
  //   1. Partition. _partitionServiceSettings splits the input into a
  //      finished LocalPluginOverride list (plugin-specific entries) and a
  //      pendingWildcards map (wildcards that cannot be materialized yet
  //      because the winner is not known until plugins register).
  //
  //   2. Seed. ServiceRegistry(overrides: ...) installs the finished list
  //      immediately. Plugin-specific priority overrides take effect when
  //      the matching plugin calls one of the register methods, because the
  //      registry's effectivePriority lookup only checks overrides keyed by
  //      the registering plugin's id, with no fallback
  //      to PluginId.winnerScoped.
  //
  //   3. Resolve. After plugins have registered, _resolveAndApplyWildcards
  //      looks up the current winner for each pending wildcard and emits
  //      the override under two scopes: the winner's pluginId AND
  //      PluginId.winnerScoped ('*'). Both are then passed into
  //      ServiceRegistry.updateSettings, which restamps each existing
  //      wrapper's effective priority using the new override list. So a
  //      wildcard priority intent applies live to the just-registered
  //      winner's wrapper, AND survives a future re-registration of the
  //      same plugin (e.g. a model swap that calls registerSingleton
  //      again) because the override entry stays in the registry's
  //      override list. The PluginId.winnerScoped entry separately feeds
  //      _overrideForInjection's fallback when service CONFIG settings
  //      are injected.
  //
  //   4. Lookup. The two paths that consume the override list are
  //      asymmetric. The register methods (_effectivePriorityFor) consult
  //      overrides keyed by the registering plugin's id only, with no
  //      fallback (so they pick up the wildcard-forwarded plugin-scoped
  //      entry but not the winnerScoped sentinel). _overrideForInjection
  //      merges plugin-specific with the winnerScoped fallback knob by
  //      knob: enabled AND-merges (either layer disables -> disabled),
  //      priority is plugin-specific-wins-if-set, settings is
  //      plugin-specific-wins-if-non-empty. The net effect: a wildcard's
  //      CONFIG intent persists across winner changes via the
  //      winnerScoped fallback even when a plugin-specific entry sets
  //      only priority, while its PRIORITY intent attaches to whoever
  //      was the winner at stage 3 and stays attached to that plugin's
  //      wrapper across re-registrations (priority transfers are not
  //      automatic on winner changes).

  /// Appends a single canonical [LocalPluginOverride] for one
  /// (cfg, serviceId, plugin) tuple carrying every knob from [cfg]
  /// (enabled, priority, settings) in one row.
  ///
  /// One-row-per-pair lets readers do a single lookup per (plugin,
  /// serviceId) and merge knob-by-knob across layers in
  /// [ServiceRegistry._overrideForInjection], instead of risking the
  /// "first matching row wins" shadow that drops other knobs set inside
  /// the same [ServiceSettings].
  void _appendServiceOverrides({
    required ServiceSettings cfg,
    required ServiceId serviceId,
    required PluginId targetPluginId,
    required List<LocalPluginOverride> out,
  }) {
    final hasOverrideKnob =
        !cfg.enabled || cfg.priority != null || cfg.config.isNotEmpty;
    if (!hasOverrideKnob) return;
    out.add(
      LocalPluginOverride(
        plugin: targetPluginId,
        serviceId: serviceId,
        enabled: cfg.enabled,
        priority: cfg.priority,
        settings: cfg.config,
      ),
    );
  }

  /// Splits service settings into plugin-specific overrides (appended to
  /// [overrides] immediately) and wildcard entries (stashed in
  /// [pendingWildcards] for [_resolveAndApplyWildcards] once plugins
  /// register). See stage 1 of the pipeline narrative above.
  ///
  /// Plugin-specific keys that target plugins outside [plugins] are ignored
  /// by this pass. This lets global and session reconciliation read the same
  /// root [RuntimeSettings.services] map without failing on cross-scope keys.
  void _partitionServiceSettings({
    required Map<Pin, ServiceSettings> services,
    required List<LocalPluginOverride> overrides,
    required Map<ServiceId, ServiceSettings> pendingWildcards,
    required Iterable<Plugin> plugins,
  }) {
    final scopedPluginIds = {for (final plugin in plugins) plugin.pluginId};
    for (final MapEntry(key: scopedKey, value: cfg) in services.entries) {
      final ServiceId serviceId = scopedKey.serviceId;
      if (scopedKey.isWildcard) {
        pendingWildcards[serviceId] = cfg;
        continue;
      }
      final PluginId pluginId = scopedKey.pluginId;
      if (!scopedPluginIds.contains(pluginId)) continue;
      _appendServiceOverrides(
        cfg: cfg,
        serviceId: serviceId,
        targetPluginId: pluginId,
        out: overrides,
      );
    }
  }

  /// Applies the current [_unknownReferencePolicy] to the list of
  /// detected unknown references for a single validation pass. The
  /// pass collects every unknown reference into [unknowns] (a list of
  /// human-readable descriptions) and then this helper either throws,
  /// logs once with all entries, or no-ops. Batching is intentional:
  /// one severe log entry per pass is easier to scan than N separate
  /// messages.
  void _applyUnknownReferencePolicy({
    required String kind,
    required String entryPoint,
    required List<String> unknowns,
  }) {
    if (unknowns.isEmpty) return;
    switch (_unknownReferencePolicy) {
      case UnknownReferencePolicy.throwError:
        throw StateError(
          'PluginRuntime.$entryPoint received ${unknowns.length} '
          'RuntimeSettings entries that reference unknown $kind: '
          '${unknowns.join(', ')}. Either register the missing ids or '
          'switch the runtime to UnknownReferencePolicy.logAndSkip '
          '(production-safe default) to drop unknown entries instead '
          'of crashing.',
        );
      case UnknownReferencePolicy.logAndSkip:
        _runtimeLog.severe(
          'PluginRuntime.$entryPoint dropped ${unknowns.length} '
          'RuntimeSettings entries with unknown $kind '
          '(typo, renamed id, or stale cached settings from a prior '
          'app version): ${unknowns.join(', ')}.',
        );
      case UnknownReferencePolicy.ignore:
        // Intentional no-op: caller has another channel for surfacing
        // dropped ids.
        break;
    }
  }

  /// Validates that every plugin-scoped service override references a known
  /// plugin id from this runtime's registered plugin set.
  ///
  /// Wildcard keys are excluded because they intentionally target "whoever
  /// wins." Cross-scope keys are still valid as long as the plugin exists;
  /// scope filtering is handled by [_partitionServiceSettings] per pass.
  void _validateServiceSettingPluginIds({
    required String entryPoint,
    required Map<Pin, ServiceSettings> services,
  }) {
    if (services.isEmpty) return;
    final knownPluginIds = {for (final plugin in _plugins) plugin.pluginId};
    final unknowns = <String>[];
    for (final MapEntry(key: scopedKey, value: _) in services.entries) {
      if (scopedKey.isWildcard) continue;
      final pluginId = scopedKey.pluginId;
      if (knownPluginIds.contains(pluginId)) continue;
      unknowns.add('$scopedKey (unknown plugin "$pluginId")');
    }
    _applyUnknownReferencePolicy(
      kind: 'plugin ids in services pin',
      entryPoint: entryPoint,
      unknowns: unknowns,
    );
  }

  /// Validates that every key in [RuntimeSettings.plugins] references a
  /// plugin id known to this runtime. Symmetrical to
  /// [_validateServiceSettingPluginIds] on the services side.
  void _validatePluginConfigPluginIds({
    required String entryPoint,
    required Map<PluginId, PluginConfig> plugins,
  }) {
    if (plugins.isEmpty) return;
    final knownPluginIds = {for (final plugin in _plugins) plugin.pluginId};
    final unknowns = <String>[];
    for (final pluginId in plugins.keys) {
      if (knownPluginIds.contains(pluginId)) continue;
      unknowns.add(pluginId);
    }
    _applyUnknownReferencePolicy(
      kind: 'plugin ids in plugins config',
      entryPoint: entryPoint,
      unknowns: unknowns,
    );
  }

  /// Validates that every plugin-scoped service pin references a service
  /// id the named plugin actually registered. Runs AFTER `register-all`
  /// because the set of registered service ids is not known until then.
  ///
  /// Wildcard pins are exempt (they target whoever wins, by design).
  /// Pins whose plugin id is unknown to this scope are also exempt
  /// here; those are caught by [_validateServiceSettingPluginIds] in
  /// the up-front pass.
  void _validateServicePinServiceIds({
    required String entryPoint,
    required ServiceRegistry registry,
    required Map<Pin, ServiceSettings> services,
    required Iterable<Plugin> plugins,
  }) {
    if (services.isEmpty) return;
    final scopedPluginIds = {for (final plugin in plugins) plugin.pluginId};
    final knownByPlugin = <PluginId, Set<ServiceId>>{};
    Set<ServiceId> knownFor(PluginId pid) =>
        knownByPlugin.putIfAbsent(pid, () => registry.listAllServiceIds(pid));

    final unknowns = <String>[];
    for (final MapEntry(key: scopedKey, value: _) in services.entries) {
      if (scopedKey.isWildcard) continue;
      final pluginId = scopedKey.pluginId;
      if (!scopedPluginIds.contains(pluginId)) continue;
      final serviceId = scopedKey.serviceId;
      if (knownFor(pluginId).contains(serviceId)) continue;
      unknowns.add(
        '$scopedKey (plugin "$pluginId" did not register "$serviceId")',
      );
    }
    _applyUnknownReferencePolicy(
      kind: 'service ids in services pin',
      entryPoint: entryPoint,
      unknowns: unknowns,
    );
  }

  /// Whether [plugin] is enabled by default in the absence of any
  /// `RuntimeSettings` override.
  ///
  /// Locked plugins are always on, experimental plugins default off, all
  /// others default on. The Plugins tab uses this to seed UI state, and the
  /// controller uses it to prune no-op overrides from the working draft.
  static bool isPluginEnabledByDefault(Plugin plugin) {
    if (plugin.featureFlags.contains(FeatureFlag.locked)) {
      return true;
    }
    if (plugin.featureFlags.contains(FeatureFlag.experimental)) {
      return false;
    }
    return true;
  }

  /// Whether [plugin] would be enabled under [settings], ignoring
  /// dependency resolution.
  ///
  /// Precedence (highest to lowest):
  /// 1. [FeatureFlag.locked]: always enabled, cannot be overridden.
  /// 2. Explicit [RuntimeSettings.plugins] entry: its [PluginConfig.enabled]
  ///    value wins over the experimental heuristic.
  /// 3. Experimental heuristic: non-experimental plugins are enabled,
  ///    [FeatureFlag.experimental] plugins are disabled.
  bool _isPluginEnabled(Plugin plugin, RuntimeSettings settings) {
    if (plugin.featureFlags.contains(FeatureFlag.locked)) {
      return true;
    }
    final cfgEnabled = settings.plugins[plugin.pluginId]?.enabled;
    if (cfgEnabled != null) return cfgEnabled;
    return !plugin.featureFlags.contains(FeatureFlag.experimental);
  }

  /// Detects strongly connected components in the dependency subgraph
  /// restricted to [enabledPluginIds] (plus [additionalEnabledPluginIds]
  /// for cross-scope dep resolution) and emits one `severe` log per cycle
  /// naming the participants.
  ///
  /// Detection is informational: cycles where every member is enabled
  /// satisfy each other's dependencies and the plugins remain attached.
  /// A cycle is still a structural smell (order ambiguity, fragile
  /// startup, harder debugging), so silence is the worst outcome. Logging
  /// preserves backward-compat behavior while surfacing the issue.
  ///
  /// Uses Tarjan's algorithm to find SCCs in one pass. Components of size
  /// >= 2 are cycles; components of size 1 with a self-loop edge are
  /// self-cycles.
  void _logDependencyCycles(
    Set<PluginId> enabledPluginIds,
    List<Plugin> pluginSubset, {
    Set<PluginId> additionalEnabledPluginIds = const {},
  }) {
    if (enabledPluginIds.isEmpty) return;
    final byId = <PluginId, Plugin>{
      for (final p in pluginSubset)
        if (enabledPluginIds.contains(p.pluginId)) p.pluginId: p,
    };

    final reachable = <PluginId>{
      ...enabledPluginIds,
      ...additionalEnabledPluginIds,
    };

    int index = 0;
    final indexMap = <PluginId, int>{};
    final lowlink = <PluginId, int>{};
    final onStack = <PluginId>{};
    final stack = <PluginId>[];
    final sccs = <List<PluginId>>[];

    void strongConnect(PluginId v) {
      indexMap[v] = index;
      lowlink[v] = index;
      index++;
      stack.add(v);
      onStack.add(v);

      final plugin = byId[v];
      if (plugin != null) {
        for (final w in plugin.dependencies) {
          if (!reachable.contains(w)) continue;
          if (!indexMap.containsKey(w)) {
            strongConnect(w);
            final lw = lowlink[w]!;
            if (lw < lowlink[v]!) lowlink[v] = lw;
          } else if (onStack.contains(w)) {
            final iw = indexMap[w]!;
            if (iw < lowlink[v]!) lowlink[v] = iw;
          }
        }
      }

      if (lowlink[v] == indexMap[v]) {
        final scc = <PluginId>[];
        PluginId w;
        do {
          w = stack.removeLast();
          onStack.remove(w);
          scc.add(w);
        } while (w != v);
        sccs.add(scc);
      }
    }

    for (final v in enabledPluginIds) {
      if (!indexMap.containsKey(v)) strongConnect(v);
    }

    for (final scc in sccs) {
      final isCycle =
          scc.length > 1 ||
          (scc.length == 1 &&
              (byId[scc.first]?.dependencies.contains(scc.first) ?? false));
      if (!isCycle) continue;
      final names = scc.map((p) => p).join(' -> ');
      _runtimeLog.severe(
        'Dependency cycle detected among enabled plugins: $names. '
        'Cycles are functional when every member is enabled but indicate '
        'tight coupling that should usually be one plugin or merged via '
        'a shared service.',
      );
    }
  }

  /// Determines the set of enabled plugin ids based on [RuntimeSettings].
  ///
  /// [pluginSubset] specifies which plugins to evaluate. This allows callers
  /// to scope enablement checks to only global or only session plugins.
  ///
  /// [additionalEnabledPluginIds] lists plugin ids that are enabled in
  /// another scope and are visible for dependency resolution: e.g., when
  /// evaluating session plugins, pass the enabled global plugin ids so that
  /// session plugins can declare cross-scope dependencies on globals.
  ///
  /// Base enablement precedence is documented on [_isPluginEnabled]. After
  /// the base pass, plugins whose [Plugin.dependencies] are not satisfied by
  /// [pluginSubset] ∪ [additionalEnabledPluginIds] are disabled via
  /// [_validateDependencies]. Locked plugins with unsatisfied dependencies
  /// are kept enabled and logged at severe: per contract they are always
  /// on, so an unmet dependency is a configuration error, not a condition to
  /// silently resolve.
  Set<PluginId> _determineEnabledPluginIds(
    RuntimeSettings settings, {
    required List<Plugin> pluginSubset,
    Set<PluginId> additionalEnabledPluginIds = const {},
  }) {
    final enabledPluginIds = <PluginId>{};
    for (final plugin in pluginSubset) {
      if (_isPluginEnabled(plugin, settings)) {
        enabledPluginIds.add(plugin.pluginId);
      }
    }

    _validateDependencies(
      enabledPluginIds,
      pluginSubset,
      additionalEnabledPluginIds: additionalEnabledPluginIds,
    );

    _logDependencyCycles(
      enabledPluginIds,
      pluginSubset,
      additionalEnabledPluginIds: additionalEnabledPluginIds,
    );

    return enabledPluginIds;
  }

  /// Validates that all enabled plugins have their dependencies satisfied.
  /// Iterates until stable to handle transitive dependencies.
  ///
  /// [additionalEnabledPluginIds] contains plugin ids enabled in another
  /// scope that are visible for dependency resolution (e.g., global plugin
  /// ids when validating session plugins).
  ///
  /// Locked plugins ([FeatureFlag.locked]) with unsatisfied
  /// dependencies are kept enabled and logged at severe: per contract they
  /// are always on, so unmet dependencies indicate a configuration error.
  void _validateDependencies(
    Set<PluginId> enabledPluginIds,
    List<Plugin> pluginSubset, {
    Set<PluginId> additionalEnabledPluginIds = const {},
  }) {
    final warnedLocked = <PluginId>{};
    bool changed = true;
    while (changed) {
      changed = false;
      for (final plugin in pluginSubset) {
        if (!enabledPluginIds.contains(plugin.pluginId)) continue;
        final isLocked = plugin.featureFlags.contains(FeatureFlag.locked);
        for (final dep in plugin.dependencies) {
          final satisfied =
              enabledPluginIds.contains(dep) ||
              additionalEnabledPluginIds.contains(dep);
          if (satisfied) continue;

          if (isLocked) {
            if (warnedLocked.add(plugin.pluginId)) {
              _runtimeLog.severe(
                'Locked plugin "${plugin.pluginId}" has unsatisfied '
                'dependency "$dep". Keeping enabled per locked contract; '
                'this is a configuration error.',
              );
            }
            continue;
          }

          enabledPluginIds.remove(plugin.pluginId);
          _runtimeLog.info(
            'Auto-disabling "${plugin.pluginId}": '
            'dependency "$dep" is not enabled.',
          );
          changed = true;
          break;
        }
      }
    }
  }

  /// Looks up the winner of each pending wildcard, drops any prior override
  /// targeting that winner (unless an explicit plugin-specific override exists)
  /// or [PluginId.winnerScoped] for the same service, then re-emits via
  /// [_appendServiceOverrides] and installs the result via
  /// [ServiceRegistry.updateSettings]. See stage 3 of the pipeline
  /// narrative above.
  ///
  /// Idempotent for a stable winner. If the winner changes between calls,
  /// the prior winner's plugin-scoped entry remains in the overrides list,
  /// available if that plugin later re-registers but otherwise inert.
  void _resolveAndApplyWildcards({
    required ServiceRegistry registry,
    required Map<ServiceId, ServiceSettings> pendingWildcards,
    required List<LocalPluginOverride> overrides,
  }) {
    if (pendingWildcards.isEmpty) return;

    final wildcardServiceIds = pendingWildcards.keys.toSet();
    overrides.removeWhere(
      (o) =>
          wildcardServiceIds.contains(o.serviceId) &&
          o.plugin == PluginId.winnerScoped,
    );

    // Snapshot which (plugin, serviceId) pairs already have an explicit
    // plugin-specific override from _partitionServiceSettings. These must
    // not be displaced by the wildcard winner entry: the plugin-specific
    // row is preserved verbatim so _overrideForInjection can layer it
    // over the winnerScoped fallback knob by knob (a priority-only
    // plugin-specific row still lets the wildcard's config flow in).
    final explicitKeys = {
      for (final o in overrides)
        if (o.plugin != PluginId.winnerScoped) (o.plugin, o.serviceId),
    };

    for (final entry in pendingWildcards.entries) {
      final ServiceId serviceId = entry.key;
      final ServiceSettings cfg = entry.value;

      final wrapper = registry.maybeResolveRaw<Object>(serviceId);
      if (wrapper == null) {
        continue;
      }

      final winnerPluginId = wrapper.pluginId;
      _runtimeLog.fine(
        'Wildcard override for "$serviceId" resolved to plugin "$winnerPluginId"',
      );

      // Only displace the winner's prior entry when there is no explicit
      // plugin-specific override for this (winner, service) pair. An explicit
      // override from _partitionServiceSettings takes precedence over the
      // wildcard and must survive.
      if (!explicitKeys.contains((winnerPluginId, serviceId))) {
        overrides.removeWhere(
          (o) => o.serviceId == serviceId && o.plugin == winnerPluginId,
        );
        _appendServiceOverrides(
          cfg: cfg,
          serviceId: serviceId,
          targetPluginId: winnerPluginId,
          out: overrides,
        );
      }

      // Always emit the PluginId.winnerScoped entry so _overrideForInjection's fallback
      // keeps the wildcard's config flowing into any future winner.
      _appendServiceOverrides(
        cfg: cfg,
        serviceId: serviceId,
        targetPluginId: PluginId.winnerScoped,
        out: overrides,
      );
    }
    registry.updateSettings(overrides: overrides);
  }

  /// Reconciles plugin enablement on settings update.
  Future<void> _reconcilePluginsOnSettingsUpdate({
    required ServiceRegistry registry,
    required Set<PluginId> enabledPluginIds,
    required List<LocalPluginOverride> overrides,
    required PluginSession<S> session,
  }) async {
    final errors = <(PluginId, Object, StackTrace)>[];
    for (final plugin in sessionPlugins) {
      final bool isEnabled = enabledPluginIds.contains(plugin.pluginId);
      final bool wasEnabled = session.isPluginEnabled(plugin.pluginId);

      if (wasEnabled && !isEnabled) {
        session.markPluginDisabled(plugin.pluginId);
        _runtimeLog.info(
          'Settings update: disabling plugin "${plugin.pluginId}"',
        );
        // Run the plugin's own detach first so any subscriptions it set up
        // in attach (and any StatefulPluginServices it owns) are torn
        // down symmetrically. The registry snapshot is taken AFTER detach
        // (matching the global path) in case detach mutates registrations.
        try {
          await plugin._runDetach(session.context);
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to detach plugin "${plugin.pluginId}" during settings update',
            e,
            st,
          );
          errors.add((plugin.pluginId, e, st));
        }
        final serviceIds = registry.listAllServiceIds(plugin.pluginId);
        for (final serviceId in serviceIds) {
          registry.unregister(pluginId: plugin.pluginId, serviceId: serviceId);
        }
      } else if (!wasEnabled && isEnabled) {
        _runtimeLog.info(
          'Settings update: enabling plugin "${plugin.pluginId}"',
        );
        // Wrap register in the same try/catch as attach/detach so a
        // throwing plugin doesn't abort reconciliation for other plugins.
        try {
          plugin.register(registry.scopedFor(plugin.pluginId));
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to register plugin "${plugin.pluginId}" during settings update',
            e,
            st,
          );
          errors.add((plugin.pluginId, e, st));
          continue;
        }
        // Calling the plugin's attach runs any direct subscriptions AND,
        // via the base implementation, attaches all StatefulPluginServices
        // the plugin just registered.
        try {
          plugin._runAttach(session.context);
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to attach plugin "${plugin.pluginId}" during settings update',
            e,
            st,
          );
          errors.add((plugin.pluginId, e, st));
          // Cleanup pass: `_runAttach` may have bound StatefulPluginService
          // contexts and registered subscriptions before throwing. Without
          // an explicit detach, those services keep `hasContext == true`
          // and their attach-time subscriptions stay live on the bus,
          // firing for events on a "rolled back" plugin. Best-effort
          // detach reverses that; failures during cleanup are swallowed
          // because the original attach error is what the caller cares
          // about.
          try {
            await plugin._runDetach(session.context);
          } catch (_) {}
          // Roll back the partial registration so the registry does not
          // hold orphan wrappers for a plugin that never attached. State
          // queries (session.isPluginEnabled, runtime.attachedPluginIds)
          // must report the plugin as NOT enabled after this failure.
          final serviceIds = registry.listAllServiceIds(plugin.pluginId);
          for (final serviceId in serviceIds) {
            registry.unregister(
              pluginId: plugin.pluginId,
              serviceId: serviceId,
            );
          }
          continue;
        }
        // Both register and attach succeeded: only NOW record the plugin
        // as enabled in this session.
        session.markPluginEnabled(plugin.pluginId);
      }
    }
    if (errors.isNotEmpty) {
      throw PluginLifecycleException('updateSessionSettings', errors);
    }
  }

  /// Snapshot of currently-attached stateful services per plugin in
  /// [pluginIds], keyed by `(pluginId, serviceId)`. Used as the pre-state
  /// for the override-flip diff in [_reconcileServiceLifecycleDiff].
  /// Factories are skipped (cannot host stateful services); disabled
  /// wrappers are filtered by [ServiceRegistry.getPluginServicesWithIds].
  Map<(PluginId, ServiceId), StatefulPluginService>
  _snapshotAttachedStatefulServices({
    required ServiceRegistry registry,
    required Iterable<PluginId> pluginIds,
  }) {
    final snapshot = <(PluginId, ServiceId), StatefulPluginService>{};
    for (final pluginId in pluginIds) {
      for (final (serviceId, instance) in registry.getPluginServicesWithIds(
        pluginId,
        skipFactories: true,
      )) {
        if (instance is StatefulPluginService && instance.hasContext) {
          snapshot[(pluginId, serviceId)] = instance;
        }
      }
    }
    return snapshot;
  }

  /// Diff [preAttached] (captured before the override flip) against the
  /// current enabled set and run lifecycle on transitions: enabled to
  /// disabled gets `detach()` + unbind; disabled to enabled gets bind +
  /// `attach()`. Returns errors as `(pluginId, error, stackTrace)` tuples
  /// for aggregation. Fatal VM errors are rethrown.
  Future<List<(PluginId, Object, StackTrace)>> _reconcileServiceLifecycleDiff({
    required ServiceRegistry registry,
    required Iterable<PluginId> pluginIds,
    required Map<(PluginId, ServiceId), StatefulPluginService> preAttached,
    required PluginContext context,
  }) async {
    final errors = <(PluginId, Object, StackTrace)>[];

    final postEnabled = <(PluginId, ServiceId), StatefulPluginService>{};
    for (final pluginId in pluginIds) {
      for (final (serviceId, instance) in registry.getPluginServicesWithIds(
        pluginId,
        skipFactories: true,
      )) {
        if (instance is StatefulPluginService) {
          postEnabled[(pluginId, serviceId)] = instance;
        }
      }
    }

    // Detach services that flipped enabled -> disabled.
    for (final entry in preAttached.entries) {
      if (postEnabled.containsKey(entry.key)) continue;
      final (pluginId, serviceId) = entry.key;
      final service = entry.value;
      try {
        await service.detach();
      } catch (e, st) {
        if (_isFatalError(e)) rethrow;
        _runtimeLog.severe(
          'Service "$serviceId" of plugin "$pluginId" detach() threw '
          'while reconciling disabled override',
          e,
          st,
        );
        errors.add((pluginId, e, st));
      }
      final unbindFailures = await service._unbindContext();
      for (final (step, e, st) in unbindFailures) {
        _runtimeLog.severe(
          'Service "$serviceId" of plugin "$pluginId" $step threw during '
          'override-driven unbind',
          e,
          st,
        );
        errors.add((pluginId, e, st));
      }
    }

    // Attach services that flipped disabled -> enabled. Skip those already
    // attached (e.g. via the plugin enable path inside
    // _reconcilePluginsOnSettingsUpdate or _updateGlobalSettingsInternal's
    // own plugin-transition loop).
    for (final entry in postEnabled.entries) {
      if (preAttached.containsKey(entry.key)) continue;
      final (pluginId, serviceId) = entry.key;
      final service = entry.value;
      if (service.hasContext) continue;
      service._bindContext(context);
      try {
        service.attach();
      } catch (e, st) {
        if (_isFatalError(e)) rethrow;
        _runtimeLog.severe(
          'Service "$serviceId" of plugin "$pluginId" attach() threw '
          'while reconciling enabled override',
          e,
          st,
        );
        errors.add((pluginId, e, st));
        // Best-effort unwind: bind happened above but attach() never
        // completed. _unbindContext cancels any subscriptions opened
        // before the throw and clears _context.
        final unbindFailures = await service._unbindContext();
        for (final (step, ue, ust) in unbindFailures) {
          _runtimeLog.severe(
            'Service "$serviceId" of plugin "$pluginId" $step threw during '
            'attach-failure unwind',
            ue,
            ust,
          );
          errors.add((pluginId, ue, ust));
        }
      }
    }

    return errors;
  }

  /// Determine if a plugin would be enabled for a given [settings] snapshot.
  ///
  /// When [settings] is null, the runtime's current snapshot ([this.settings])
  /// is used.
  ///
  /// Applies the same precedence as [_determineEnabledPluginIds]: locked
  /// plugins are always enabled, explicit config wins over defaults, and
  /// experimental plugins are disabled by default. Dependency validation is
  /// not applied here: this returns the base enablement only.
  bool isPluginEnabled(PluginId pluginId, [RuntimeSettings? settings]) {
    final plugin = _plugins.firstWhereOrNull((p) => p.pluginId == pluginId);
    if (plugin == null) return false;
    return _isPluginEnabled(plugin, settings ?? this.settings);
  }

  /// Plugins enabled per current settings (settings-intent).
  ///
  /// Reports the base enablement decision: locked + explicit settings +
  /// defaults + experimental heuristic. Does not account for dependency
  /// cascade; a plugin whose dependency is disabled remains in this list
  /// even though the runtime has actually disabled it.
  ///
  /// For runtime truth, use [attachedPlugins].
  Iterable<Plugin> get enabledPlugins sync* {
    for (final plugin in _plugins) {
      if (isPluginEnabled(plugin.pluginId)) yield plugin;
    }
  }

  /// Plugin ids enabled per current settings (settings-intent).
  ///
  /// For runtime truth, use [attachedPluginIds].
  Set<PluginId> get enabledPluginIds => {
    for (final p in enabledPlugins) p.pluginId,
  };

  /// Plugins currently attached at runtime.
  ///
  /// Distinct from [enabledPlugins], which reports settings-intent
  /// (locked + explicit settings + defaults + experimental heuristic).
  /// `attachedPlugins` reports the post-cascade effective set: plugins
  /// whose dependencies are satisfied AND that the runtime has actually
  /// run `attach` on. A plugin enabled in settings but cascade-disabled
  /// because its dependency is off appears in [enabledPlugins] but NOT
  /// in [attachedPlugins].
  ///
  /// Read this when you need runtime truth (e.g., a UI that shows which
  /// plugins are running). Read [enabledPlugins] when you need settings
  /// truth (e.g., a settings-screen toggle list).
  List<Plugin> get attachedPlugins => [
    for (final plugin in _plugins)
      if (attachedPluginIds.contains(plugin.pluginId)) plugin,
  ];

  /// Plugin ids currently attached at runtime (post-cascade effective set).
  Set<PluginId> get attachedPluginIds {
    final ids = <PluginId>{...attachedGlobalPluginIds};
    for (final session in _sessions) {
      ids.addAll(session.enabledPluginIds);
    }
    return ids;
  }

  /// Whether [pluginId] is currently attached at runtime.
  bool isPluginAttached(PluginId pluginId) =>
      attachedPluginIds.contains(pluginId);

  /// Reconciles the runtime to [newSettings] in serialized order: global
  /// scope first, then each active session sequentially. Transactional:
  /// on any failure, every touched unit is reverted via a re-reconcile
  /// pass back to the prior snapshot, the stored snapshot stays at the
  /// previous value, and the original exception is rethrown. Secondary
  /// failures during the revert pass log severe but never suppress the
  /// primary; fatal VM errors during revert supersede it.
  Future<void> updateSettings(RuntimeSettings newSettings) async {
    _enterReconcile('updateSettings');
    try {
      final oldSettings = _settings;
      // Tracks units mid-reconcile so the catch can roll them back too.
      // A unit that throws partway still left fully-transitioned plugins
      // on the new state (per-plugin rollback only unwinds the thrower);
      // skipping the in-flight unit would leave it half-applied while
      // every completed sibling reverts cleanly.
      final reconciledSessions = <PluginSession<S>>[];
      bool globalStarted = false;
      PluginSession<S>? inFlightSession;

      try {
        globalStarted = true;
        await _updateGlobalSettingsInternal(
          oldSettings: oldSettings,
          newSettings: newSettings,
        );

        for (final session in _sessions) {
          inFlightSession = session;
          await _updateSessionSettingsInternal(
            session,
            newSettings: newSettings,
          );
          reconciledSessions.add(session);
          inFlightSession = null;
        }
        _settingsValue = newSettings;
      } catch (e) {
        // Revert order: GLOBAL first, then in-flight session, then
        // completed sessions in reverse. Session enablement depends on
        // `_enabledGlobalPluginIds` for dependency cascade, so reverting
        // global first restores the cascade input each session's
        // rollback reconcile reads. Global revert runs on either
        // `globalStarted` outcome because a partial reconcile still
        // left mutations.
        if (globalStarted) {
          try {
            await _updateGlobalSettingsInternal(
              oldSettings: newSettings,
              newSettings: oldSettings,
            );
          } catch (rollbackError, rollbackSt) {
            if (_isFatalError(rollbackError)) rethrow;
            _runtimeLog.severe(
              'updateSettings rollback failed for global; the original '
              'reconcile exception is rethrown and this secondary error '
              'is surfaced here only',
              rollbackError,
              rollbackSt,
            );
          }
        }
        if (inFlightSession != null) {
          try {
            await _updateSessionSettingsInternal(
              inFlightSession,
              newSettings: oldSettings,
            );
          } catch (rollbackError, rollbackSt) {
            if (_isFatalError(rollbackError)) rethrow;
            _runtimeLog.severe(
              'updateSettings rollback failed for in-flight session; the '
              'original reconcile exception is rethrown and this '
              'secondary error is surfaced here only',
              rollbackError,
              rollbackSt,
            );
          }
        }
        for (final session in reconciledSessions.reversed) {
          try {
            await _updateSessionSettingsInternal(
              session,
              newSettings: oldSettings,
            );
          } catch (rollbackError, rollbackSt) {
            if (_isFatalError(rollbackError)) rethrow;
            _runtimeLog.severe(
              'updateSettings rollback failed for session; the original '
              'reconcile exception is rethrown and this secondary error '
              'is surfaced here only',
              rollbackError,
              rollbackSt,
            );
          }
        }
        rethrow;
      }
    } finally {
      _reconciling = false;
    }
  }

  /// Mark a reconciliation pass as in flight, or throw if one already is.
  /// Paired with `_reconciling = false` in a `finally` so failed reconciles
  /// do not leave the runtime permanently locked.
  void _enterReconcile(String entryPoint) {
    if (_reconciling) {
      throw StateError(
        'PluginRuntime.$entryPoint called while a settings reconciliation '
        'is already in progress. Concurrent reconciliations would '
        'interleave across await boundaries and corrupt registry / '
        'session state. Serialize your settings updates (the standard '
        'pattern is a tail-chained Future per the troubleshooting docs).',
      );
    }
    _reconciling = true;
  }

  /// Replace the stored [settings] snapshot and emit it on [settingsStream]
  /// without running any reconciliation.
  ///
  /// Use [updateSettings] when you want the runtime to converge on the new
  /// settings (attach, detach, re-inject). Use this method when you only
  /// want to publish a new snapshot to listeners (e.g. replaying a saved
  /// draft into the UI), or when the runtime has already converged and you
  /// just need to broadcast the change.
  void updateSettingsSnapshot(RuntimeSettings value) {
    if (value == _settings) return;
    _settingsValue = value;
  }

  /// Reset [settings] to an empty `const RuntimeSettings()`. Does not run
  /// reconciliation.
  void resetSettings() {
    _settingsValue = const RuntimeSettings();
  }

  /// Update global plugin settings with reconciliation.
  ///
  /// Reconciles plugin enablement (disable/enable) and notifies remaining
  /// enabled global plugins via [Plugin.onPluginSettingsChanged].
  Future<void> updateGlobalSettings({
    required RuntimeSettings oldSettings,
    required RuntimeSettings newSettings,
  }) async {
    _enterReconcile('updateGlobalSettings');
    try {
      await _updateGlobalSettingsInternal(
        oldSettings: oldSettings,
        newSettings: newSettings,
      );
    } finally {
      _reconciling = false;
    }
  }

  /// Body of [updateGlobalSettings] without the re-entry guard. Used by
  /// [updateSettings] which already holds the guard for the whole pass.
  Future<void> _updateGlobalSettingsInternal({
    required RuntimeSettings oldSettings,
    required RuntimeSettings newSettings,
  }) async {
    final oldContext = globalContext.copyWith();
    // See the matching assert in `_updateSessionSettingsInternal` for the
    // rationale; this is intentionally over-constrained for the same reason.
    assert(
      oldContext.runtimeType == globalContext.runtimeType,
      'Custom global context subclass ${globalContext.runtimeType} did not '
      'override copyWith(); onPluginSettingsChanged will receive a base-type '
      'oldContext and any covariant subtype override on the plugin will throw '
      'TypeError. See concepts/custom-context for the required override shape.',
    );
    _validateServiceSettingPluginIds(
      entryPoint: 'updateGlobalSettings',
      services: newSettings.services,
    );
    _validatePluginConfigPluginIds(
      entryPoint: 'updateGlobalSettings',
      plugins: newSettings.plugins,
    );

    final overrides = <LocalPluginOverride>[];
    final pendingWildcards = <ServiceId, ServiceSettings>{};
    _partitionServiceSettings(
      services: newSettings.services,
      overrides: overrides,
      pendingWildcards: pendingWildcards,
      plugins: globalPlugins,
    );
    final enabledPluginIds = _determineEnabledPluginIds(
      newSettings,
      pluginSubset: globalPlugins,
    );

    final errors = <(PluginId, Object, StackTrace)>[];
    for (final plugin in globalPlugins) {
      final wasEnabled = _enabledGlobalPluginIds.contains(plugin.pluginId);
      final isEnabled = enabledPluginIds.contains(plugin.pluginId);

      // Disable: detach and unregister
      if (wasEnabled && !isEnabled) {
        try {
          await plugin._runDetach(globalContext);
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to detach global plugin "${plugin.pluginId}" during settings update',
            e,
            st,
          );
          errors.add((plugin.pluginId, e, st));
        }
        final serviceIds = globalRegistry.listAllServiceIds(plugin.pluginId);
        for (final id in serviceIds) {
          globalRegistry.unregister(pluginId: plugin.pluginId, serviceId: id);
        }
        _enabledGlobalPluginIds.remove(plugin.pluginId);
        _runtimeLog.info(
          'Global settings update: disabled plugin "${plugin.pluginId}"',
        );
      }
      // Enable: register and attach
      else if (!wasEnabled && isEnabled) {
        try {
          plugin.register(globalRegistry.scopedFor(plugin.pluginId));
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to register global plugin "${plugin.pluginId}" during settings update',
            e,
            st,
          );
          errors.add((plugin.pluginId, e, st));
          continue;
        }
        try {
          plugin._runAttach(globalContext);
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to attach global plugin "${plugin.pluginId}" during settings update',
            e,
            st,
          );
          errors.add((plugin.pluginId, e, st));
          // Cleanup pass: see the matching comment in the session enable
          // path. `_runAttach` may have left service contexts bound and
          // subscriptions live before throwing; best-effort detach
          // reverses that. Failures during cleanup are swallowed; the
          // original attach error already surfaces.
          try {
            await plugin._runDetach(globalContext);
          } catch (_) {}
          // Roll back the partial registration so attachedGlobalPluginIds
          // does not advertise a plugin whose attach failed and so the
          // global registry is not left with orphan wrappers.
          final serviceIds = globalRegistry.listAllServiceIds(plugin.pluginId);
          for (final id in serviceIds) {
            globalRegistry.unregister(pluginId: plugin.pluginId, serviceId: id);
          }
          continue;
        }
        // Both register and attach succeeded: only NOW record the plugin
        // as attached at the global scope.
        _enabledGlobalPluginIds.add(plugin.pluginId);
        _runtimeLog.info(
          'Global settings update: enabled plugin "${plugin.pluginId}"',
        );
      }
    }

    // Validate service pin service ids now that newly-enabled global
    // plugins have registered and disabled ones have been unregistered.
    _validateServicePinServiceIds(
      entryPoint: 'updateGlobalSettings',
      registry: globalRegistry,
      services: newSettings.services,
      plugins: globalPlugins,
    );

    // Snapshot attached stateful services BEFORE the override flip
    // below (either _resolveAndApplyWildcards or the unconditional
    // updateSettings call may apply it). The post-flip diff handles
    // service-level enable/disable transitions for plugins that stay
    // enabled across the update.
    final preAttached = _snapshotAttachedStatefulServices(
      registry: globalRegistry,
      pluginIds: _enabledGlobalPluginIds,
    );

    // Always call updateSettings even when both lists are empty so
    // wrappers whose priority overrides were just removed get restamped
    // back to their basePriority.
    _resolveAndApplyWildcards(
      registry: globalRegistry,
      pendingWildcards: pendingWildcards,
      overrides: overrides,
    );
    if (pendingWildcards.isEmpty) {
      globalRegistry.updateSettings(overrides: overrides);
    }

    final serviceErrors = await _reconcileServiceLifecycleDiff(
      registry: globalRegistry,
      pluginIds: _enabledGlobalPluginIds,
      preAttached: preAttached,
      context: globalContext,
    );
    errors.addAll(serviceErrors);

    // Notify remaining enabled global plugins of settings changes
    for (final pluginId in _enabledGlobalPluginIds) {
      final plugin = _plugins.firstWhereOrNull((p) => p.pluginId == pluginId);
      if (plugin != null) {
        await plugin.onPluginSettingsChanged(oldContext, globalContext);
      }
    }
    if (errors.isNotEmpty) {
      _runtimeLog.warning(
        'Global settings updated with ${errors.length} plugin failure(s)',
      );
      throw PluginLifecycleException('updateGlobalSettings', errors);
    }
    _runtimeLog.info('Global settings updated');
  }

  /// Dispose runtime: detach all global plugins, dispose sessions.
  Future<void> dispose() async {
    if (!_initialized) return;

    final detachErrors = <(PluginId, Object, StackTrace)>[];
    for (final plugin in globalPlugins) {
      if (_enabledGlobalPluginIds.contains(plugin.pluginId)) {
        try {
          await plugin._runDetach(globalContext);
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to detach global plugin "${plugin.pluginId}"',
            e,
            st,
          );
          detachErrors.add((plugin.pluginId, e, st));
        }
      }
    }
    for (final session in [..._sessions]) {
      await session.dispose();
    }
    globalBus.dispose();
    _enabledGlobalPluginIds.clear();
    await _settingsController.close();
    _initialized = false;

    if (detachErrors.isNotEmpty) {
      _runtimeLog.warning(
        'Runtime disposed with ${detachErrors.length} plugin failure(s)',
      );
      throw PluginLifecycleException('detachGlobal', detachErrors);
    }
    _runtimeLog.info('Runtime disposed');
  }
}

/// A scoped session with its own registry, event bus, and plugin attachments.
///
/// Represents a single session (a conversation, a playground instance) with
/// fully isolated state: [registry] (session-scoped DI container with
/// all enabled plugins' services), [bus] (session-scoped event bus), and
/// [context] (the domain-specific context passed to plugin lifecycle hooks).
///
/// Sessions are lightweight and can be created or disposed as needed. The
/// [PluginRuntime] tracks all active sessions for settings reconciliation.
///
/// Lifecycle: created by [PluginRuntime.createSession]; [init] calls
/// [Plugin.attach] on all enabled session plugins; during the session events
/// flow through [bus] and services resolve from [registry]; [dispose]
/// calls [Plugin.detach] on all enabled session plugins and disposes the
/// event bus.
///
/// The session tracks enabled plugin ids separately from the
/// [ServiceRegistry] because some plugins only register tools (not services)
/// and wouldn't be detectable via registry inspection alone.
class PluginSession<K extends SessionPluginContext> {
  /// Session-scoped service registry with all enabled plugins' services.
  final ServiceRegistry registry;

  /// Session-scoped event bus for inter-plugin communication.
  final EventBus bus;

  /// The domain-specific context for this session.
  final K context;

  /// All session plugins (for lifecycle management during init/dispose).
  final List<Plugin> plugins;

  /// The settings snapshot used to create this session.
  final RuntimeSettings settings;

  /// Tracks which plugins are currently enabled in this session.
  final Set<PluginId> _enabledPluginIds = {};

  /// Callback to remove this session from the runtime's session list.
  /// Set by [PluginRuntime.createSession] and called during [dispose].
  void Function()? _onDispose;

  /// Returns true if the plugin is currently enabled in this session.
  bool isPluginEnabled(PluginId pluginId) =>
      _enabledPluginIds.contains(pluginId);

  /// Plugin ids currently enabled in this session. At session scope the
  /// post-cascade effective set IS the enabled set, so there is no
  /// separate "attached" view: `_runAttach` has already run by the time
  /// the session is observable, and any plugin that failed `_runAttach`
  /// surfaces via [PluginLifecycleException] from [init], not here.
  ///
  /// The runtime-level distinction between
  /// [PluginRuntime.enabledPlugins] (settings-intent) and
  /// [PluginRuntime.attachedPlugins] (post-cascade) still applies for
  /// global plugins and for "is this plugin running anywhere?" queries.
  Set<PluginId> get enabledPluginIds => Set.unmodifiable(_enabledPluginIds);

  /// Marks a plugin as enabled in this session.
  void markPluginEnabled(PluginId pluginId) => _enabledPluginIds.add(pluginId);

  /// Marks a plugin as disabled in this session.
  void markPluginDisabled(PluginId pluginId) =>
      _enabledPluginIds.remove(pluginId);

  /// Creates a plugin session with scoped runtime services and settings.
  PluginSession({
    required this.registry,
    required this.bus,
    required this.context,
    required this.plugins,
    required this.settings,
  });

  /// Initialize the session by attaching all enabled plugins.
  ///
  /// Only plugins tracked as enabled via [markPluginEnabled] are attached.
  /// Calls [Plugin.attach] on each enabled plugin, which automatically
  /// attaches all [StatefulPluginService]s and lets plugins subscribe
  /// to session events.
  Future<void> init() async {
    final attachErrors = <(PluginId, Object, StackTrace)>[];
    for (final plugin in plugins) {
      if (!_enabledPluginIds.contains(plugin.pluginId)) continue;
      try {
        plugin._runAttach(context);
      } catch (e, st) {
        if (_isFatalError(e)) rethrow;
        _sessionLog.severe(
          'Failed to attach session plugin "${plugin.pluginId}"',
          e,
          st,
        );
        attachErrors.add((plugin.pluginId, e, st));
      }
    }
    if (attachErrors.isNotEmpty) {
      _sessionLog.warning(
        'Session initialized with ${attachErrors.length} plugin failure(s)',
      );
      throw PluginLifecycleException('attachSession', attachErrors);
    }
    _sessionLog.info('Session initialized');
  }

  /// Dispose this session and all its plugin attachments.
  ///
  /// Detaches all enabled plugins and then disposes the session event bus.
  Future<void> dispose() async {
    final detachErrors = <(PluginId, Object, StackTrace)>[];
    for (final plugin in plugins) {
      if (!_enabledPluginIds.contains(plugin.pluginId)) continue;
      try {
        await plugin._runDetach(context);
      } catch (e, st) {
        if (_isFatalError(e)) rethrow;
        _sessionLog.severe(
          'Failed to detach session plugin "${plugin.pluginId}"',
          e,
          st,
        );
        detachErrors.add((plugin.pluginId, e, st));
      }
    }

    bus.dispose();

    _onDispose?.call();
    _onDispose = null;

    if (detachErrors.isNotEmpty) {
      _sessionLog.warning(
        'Session disposed with ${detachErrors.length} plugin failure(s)',
      );
      throw PluginLifecycleException('detachSession', detachErrors);
    }
    _sessionLog.info('Session disposed');
  }
}
