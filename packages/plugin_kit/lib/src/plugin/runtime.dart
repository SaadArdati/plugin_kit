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
/// [init] accepts an optional `defaultEnabledPluginIds` set. When provided,
/// only listed plugins are enabled by default; when null, all plugins are
/// enabled by default. Explicit [RuntimeSettings] entries always override
/// these defaults.
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

  /// Caller-supplied default-enabled plugin IDs.
  ///
  /// When `null`, plugins are enabled by default except those marked
  /// [FeatureFlag.experimental], which default off. When non-null, only
  /// listed plugins are enabled by default. Explicit
  /// [RuntimeSettings.plugins] entries always override these defaults.
  Set<PluginId>? _defaultEnabledPluginIds;

  /// Creates an empty runtime with no pre-registered plugins.
  PluginRuntime.empty();

  /// Creates a runtime seeded with optional initial [plugins].
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
    if (_isReservedPluginId(plugin.pluginId.value)) {
      throw ArgumentError.value(
        plugin.pluginId.value,
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

  /// Initialized here instead of at the field level directly to allow re-initialization.
  ///
  /// [defaultEnabledPluginIds] controls which plugins are enabled by default
  /// when no explicit [RuntimeSettings.plugins] entry exists. When `null`,
  /// plugins are enabled by default except those marked
  /// [FeatureFlag.experimental], which default off. When non-null, only
  /// listed plugins are enabled by default. Explicit [RuntimeSettings.plugins]
  /// entries always override these defaults.
  ///
  /// [globalContextFactory] allows callers to supply a custom [G] constructor.
  /// When null, a default [GlobalPluginContext] is created and cast to [G].
  PluginRuntime init({
    RuntimeSettings? settings,
    Set<PluginId>? defaultEnabledPluginIds,
    GlobalContextFactory<G, S>? globalContextFactory,
  }) {
    _initialized = true;
    _defaultEnabledPluginIds = defaultEnabledPluginIds;
    _runtimeLog.info('Initializing runtime');

    globalBus = EventBus();

    final effectiveSettings = settings ?? RuntimeSettings.empty();
    _validateServiceSettingPluginIds(services: effectiveSettings.services);

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

    // Register enabled global plugins
    for (final plugin in globalPlugins) {
      if (_enabledGlobalPluginIds.contains(plugin.pluginId)) {
        plugin.register(globalRegistry.scopedFor(plugin.pluginId));
      }
    }
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

    // Attach enabled plugins. Errors are collected so all plugins get a
    // chance to attach, then thrown as an aggregate.
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
    RuntimeSettings settings = const RuntimeSettings.empty(),
    SessionContextFactory<G, S>? contextFactory,
  }) async {
    if (!_initialized) {
      throw StateError(
        'PluginRuntime.createSession() called before init(). '
        'Call init() first to initialize the global scope.',
      );
    }

    _validateServiceSettingPluginIds(services: settings.services);

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
    _sessions.add(session);

    // Session buses are independent of the global bus. Global plugins that
    // want to broadcast to sessions do so explicitly via the
    // `GlobalPluginContext.sessions.emit(...)` extension; session plugins that
    // want to reach the global scope emit on `context.globalBus`. There is no
    // implicit forwarding between the two.
    session._onDispose = () {
      _sessions.remove(session);
    };

    // Track enabled plugins and attach
    for (final pluginId in enabledPluginIds) {
      session.markPluginEnabled(pluginId);
    }

    await session.init();
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
    final oldContext = session.context.copyWith();

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

    // Resolve wildcard overrides now that registry has current services
    _resolveAndApplyWildcards(
      registry: registry,
      pendingWildcards: pendingWildcards,
      overrides: overrides,
    );

    registry.updateSettings(overrides: overrides);

    // Notify each plugin that settings have been updated
    for (final pluginId in enabledPluginIds) {
      final plugin = _plugins.firstWhereOrNull((p) => p.pluginId == pluginId);
      if (plugin != null) {
        await plugin.onPluginSettingsChanged(oldContext, session.context);
      }
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
  //      asymmetric. The register methods consult overrides keyed by the
  //      registering plugin's id only, with no fallback (so they pick up
  //      the wildcard-forwarded plugin-scoped entry but not the
  //      winnerScoped sentinel). _overrideForInjection prefers
  //      plugin-specific then falls back to PluginId.winnerScoped. The
  //      net effect: a wildcard's CONFIG intent persists across winner
  //      changes via the winnerScoped fallback, while its PRIORITY
  //      intent attaches to whoever was the winner at stage 3 and stays
  //      attached to that plugin's wrapper across re-registrations
  //      (priority transfers are not automatic on winner changes).

  /// Appends up to three LocalPluginOverride entries for one
  /// (cfg, serviceId, plugin) tuple: a disable entry when cfg.enabled is
  /// false, a priority entry when cfg.priority is non-null, a settings entry
  /// when cfg.config is non-empty.
  void _appendServiceOverrides({
    required ServiceSettings cfg,
    required ServiceId serviceId,
    required PluginId targetPluginId,
    required List<LocalPluginOverride> out,
  }) {
    if (!cfg.enabled) {
      out.add(
        LocalPluginOverride.disable(
          plugin: targetPluginId,
          serviceId: serviceId,
        ),
      );
      return;
    }
    if (cfg.priority != null) {
      out.add(
        LocalPluginOverride.withPriority(
          plugin: targetPluginId,
          serviceId: serviceId,
          priority: cfg.priority!,
        ),
      );
    }
    if (cfg.config.isNotEmpty) {
      out.add(
        LocalPluginOverride(
          plugin: targetPluginId,
          serviceId: serviceId,
          settings: cfg.config,
        ),
      );
    }
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

  /// Validates that every plugin-scoped service override references a known
  /// plugin id from this runtime's registered plugin set.
  ///
  /// Wildcard keys are excluded because they intentionally target "whoever
  /// wins." Cross-scope keys are still valid as long as the plugin exists;
  /// scope filtering is handled by [_partitionServiceSettings] per pass.
  void _validateServiceSettingPluginIds({
    required Map<Pin, ServiceSettings> services,
  }) {
    final knownPluginIds = {for (final plugin in _plugins) plugin.pluginId};
    for (final MapEntry(key: scopedKey, value: _) in services.entries) {
      if (scopedKey.isWildcard) continue;
      final pluginId = scopedKey.pluginId;
      if (knownPluginIds.contains(pluginId)) continue;
      final serviceId = scopedKey.serviceId;
      throw StateError(
        'Service override targets disabled/unknown plugin "$pluginId" for "$serviceId".',
      );
    }
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
  ///    value wins over defaults and experimental heuristic.
  /// 3. Caller-supplied [_defaultEnabledPluginIds]: when non-null, the
  ///    plugin is enabled iff its id is in that set.
  /// 4. Experimental heuristic: non-experimental plugins are enabled,
  ///    [FeatureFlag.experimental] plugins are disabled.
  bool _isPluginEnabled(Plugin plugin, RuntimeSettings settings) {
    if (plugin.featureFlags.contains(FeatureFlag.locked)) {
      return true;
    }
    final cfgEnabled = settings.plugins[plugin.pluginId]?.enabled;
    if (cfgEnabled != null) return cfgEnabled;
    final defaults = _defaultEnabledPluginIds;
    if (defaults != null) return defaults.contains(plugin.pluginId);
    return !plugin.featureFlags.contains(FeatureFlag.experimental);
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
    // plugin-specific override from _partitionServiceSettings. These must not
    // be displaced by the wildcard winner entry -- plugin-specific beats
    // wildcard.
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
        session.markPluginEnabled(plugin.pluginId);
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
        }
      }
    }
    if (errors.isNotEmpty) {
      throw PluginLifecycleException('updateSessionSettings', errors);
    }
  }

  /// Determine if a plugin would be enabled for a given [settings] snapshot.
  ///
  /// Applies the same precedence as [_determineEnabledPluginIds]: locked
  /// plugins are always enabled, explicit config wins over defaults, and
  /// experimental plugins are disabled by default. Dependency validation is
  /// not applied here: this returns the base enablement only.
  bool isPluginEnabled(PluginId pluginId, RuntimeSettings settings) {
    final plugin = _plugins.firstWhereOrNull((p) => p.pluginId == pluginId);
    if (plugin == null) return false;
    return _isPluginEnabled(plugin, settings);
  }

  /// Update global plugin settings with reconciliation.
  ///
  /// Reconciles plugin enablement (disable/enable) and notifies remaining
  /// enabled global plugins via [Plugin.onPluginSettingsChanged].
  Future<void> updateGlobalSettings({
    required RuntimeSettings oldSettings,
    required RuntimeSettings newSettings,
  }) async {
    final oldContext = globalContext.copyWith();
    _validateServiceSettingPluginIds(services: newSettings.services);

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
        }
        _enabledGlobalPluginIds.add(plugin.pluginId);
        _runtimeLog.info(
          'Global settings update: enabled plugin "${plugin.pluginId}"',
        );
      }
    }

    // Apply updated overrides to global registry. Always call updateSettings,
    // even when both lists are empty, so wrappers whose priority overrides
    // were just removed get restamped back to their basePriority.
    _resolveAndApplyWildcards(
      registry: globalRegistry,
      pendingWildcards: pendingWildcards,
      overrides: overrides,
    );
    if (pendingWildcards.isEmpty) {
      globalRegistry.updateSettings(overrides: overrides);
    }

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
    _defaultEnabledPluginIds = null;
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

  /// Plugin ids currently attached in this session.
  Set<PluginId> get attachedPluginIds => Set.unmodifiable(_enabledPluginIds);

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
