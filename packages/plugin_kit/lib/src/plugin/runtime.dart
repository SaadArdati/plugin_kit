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
/// sharing a single [globalRegistry] and [globalBus]; [SessionPlugin] instances
/// are reused across sessions, while each session gets its own
/// [ServiceRegistry], [EventBus], and context.
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
/// Plugin enablement falls back through three rules in order:
/// [FeatureFlag.locked] (always on), explicit [RuntimeSettings.plugins]
/// entry, [FeatureFlag.experimental] (default off). Non-experimental
/// plugins with no explicit setting default to enabled.
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

  /// Per-session settings as they currently stand in the runtime. Set when
  /// a session is created (from the `settings` arg or the runtime's global
  /// settings), and updated whenever an `_updateSessionSettingsInternal`
  /// pass successfully commits. Used by [updateSettings] rollback to
  /// restore each session to its OWN pre-update state rather than to the
  /// global pre-update snapshot, which would discard any per-session
  /// overrides the session was constructed with.
  final Map<PluginSession<S>, RuntimeSettings> _sessionSettings = {};

  /// Unmodifiable snapshot of the per-session settings map. Exposed only
  /// for `@visibleForTesting` rollback-integrity assertions; production
  /// code must not depend on this surface (the analyzer warns when it
  /// is read outside test code).
  @visibleForTesting
  Map<PluginSession<S>, RuntimeSettings> get debugSessionSettings =>
      Map.unmodifiable(_sessionSettings);

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

  /// Whether [dispose] has run to completion. A disposed runtime is
  /// terminal: subsequent calls to [init], [createSession], [updateSettings],
  /// and the other mutating entry points all throw [StateError]. To run a
  /// fresh runtime, construct a new [PluginRuntime] instance.
  bool _disposed = false;

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
  late final SettingsNormalizer _normalizer;
  late final EnablementResolver _enablement;

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
  ///
  /// Throws [ArgumentError] if [plugins] contains duplicate
  /// [Plugin.pluginId] values. This matches the rejection done by
  /// [addPlugin] / [addPlugins], so the constructor cannot silently
  /// accept a bad seed that the runtime API would reject.
  PluginRuntime({List<Plugin>? plugins}) {
    if (plugins != null) {
      final seen = <PluginId>{};
      for (final p in plugins) {
        if (!seen.add(p.pluginId)) {
          throw ArgumentError.value(
            plugins,
            'plugins',
            'duplicate pluginId "${p.pluginId}"; each plugin must have a '
                'unique pluginId. addPlugin/addPlugins enforce this; the '
                'constructor now matches.',
          );
        }
      }
      _plugins.addAll(plugins);
    }
  }

  /// Add a plugin to the runtime.
  ///
  /// Plugins are routed by type:
  /// - [GlobalPlugin] participates in `register` → `attach` → `detach` at global scope.
  /// - [SessionPlugin] participates in `register` → `attach` → `detach` at session scope.
  ///
  /// Throws [StateError] if a plugin with the same [Plugin.pluginId]
  /// is already registered.
  void addPlugin(Plugin plugin) => _addPluginImpl(plugin);

  /// Add multiple plugins at once.
  void addPlugins(List<Plugin> plugins) => _addPluginsImpl(plugins);

  /// Initialized here instead of at field declaration time so repeated
  /// `init()` calls can rebuild internal runtime state.
  ///
  /// A disposed runtime cannot be re-initialized.
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
  }) => _initImpl(
    settings: settings,
    globalContextFactory: globalContextFactory,
    unknownReferencePolicy: unknownReferencePolicy,
  );

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
  }) => _createSessionImpl(settings: settings, contextFactory: contextFactory);

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
  }) => _updateSessionSettingsImpl(session, newSettings: newSettings);

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
  }) => _normalizer.partitionServiceSettings(
    services: services,
    overrides: overrides,
    pendingWildcards: pendingWildcards,
    scopedPluginIds: {for (final plugin in plugins) plugin.pluginId},
  );

  /// Normalizes incoming [RuntimeSettings] before storage or reconciliation.
  ///
  /// Three responsibilities, applied in sequence over fresh maps so that the
  /// caller's original map is never aliased into runtime state:
  ///
  /// 1. Defensive deep-copy of `plugins` and `services`. Callers may pass
  ///    mutable maps; after this returns the runtime owns the storage.
  /// 2. Plugin-id filtering: drops entries in `plugins` whose key is unknown
  ///    to this runtime, and entries in `services` whose pin references an
  ///    unknown plugin id. Wildcard service pins are always kept.
  /// 3. Service-id filtering (only when [registryForServiceIdCheck] is
  ///    supplied): drops service pins whose plugin is in scope but never
  ///    registered the named service id.
  ///
  /// Under [UnknownReferencePolicy.throwError] the offending entries are
  /// kept in the output and the policy's throw fires. Under `logAndSkip` /
  /// `ignore` they are dropped from the output silently or with a log.
  ///
  /// Pass [registryForServiceIdCheck] only AFTER the register-all phase
  /// completes; before that the set of registered service ids is unknown
  /// and the third pass is meaningless.
  RuntimeSettings _normalizeSettings({
    required String entryPoint,
    required RuntimeSettings raw,
    required Iterable<Plugin> scopePlugins,
    ServiceRegistry? registryForServiceIdCheck,
  }) => _normalizer.normalize(
    entryPoint: entryPoint,
    raw: raw,
    allKnownPluginIds: {for (final p in _plugins) p.pluginId},
    scopedPluginIds: {for (final p in scopePlugins) p.pluginId},
    registryForServiceIdCheck: registryForServiceIdCheck,
  );

  /// Validates that every plugin-scoped service override references a known
  /// plugin id from this runtime's registered plugin set.
  ///
  /// Wildcard keys are excluded because they intentionally target "whoever
  /// wins." Cross-scope keys are still valid as long as the plugin exists;
  /// scope filtering is handled by [_partitionServiceSettings] per pass.
  void _validateServiceSettingPluginIds({
    required String entryPoint,
    required Map<Pin, ServiceSettings> services,
  }) => _normalizer.validateServiceSettingPluginIds(
    entryPoint: entryPoint,
    services: services,
    knownPluginIds: {for (final plugin in _plugins) plugin.pluginId},
  );

  /// Validates that every key in [RuntimeSettings.plugins] references a
  /// plugin id known to this runtime. Symmetrical to
  /// [_validateServiceSettingPluginIds] on the services side.
  void _validatePluginConfigPluginIds({
    required String entryPoint,
    required Map<PluginId, PluginConfig> plugins,
  }) => _normalizer.validatePluginConfigPluginIds(
    entryPoint: entryPoint,
    plugins: plugins,
    knownPluginIds: {for (final plugin in _plugins) plugin.pluginId},
  );

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
  }) => _normalizer.validateServicePinServiceIds(
    entryPoint: entryPoint,
    registry: registry,
    services: services,
    scopedPluginIds: {for (final plugin in plugins) plugin.pluginId},
  );

  /// Whether [plugin] is enabled by default in the absence of any
  /// `RuntimeSettings` override.
  ///
  /// Locked plugins are always on, experimental plugins default off, all
  /// others default on. The Plugins tab uses this to seed UI state, and the
  /// controller uses it to prune no-op overrides from the working draft.
  static bool isPluginEnabledByDefault(Plugin plugin) =>
      EnablementResolver.isEnabledByDefault(plugin);

  /// Whether [plugin] would be enabled under [settings], ignoring
  /// dependency resolution.
  ///
  /// Precedence (highest to lowest):
  /// 1. [FeatureFlag.locked]: always enabled, cannot be overridden.
  /// 2. Explicit [RuntimeSettings.plugins] entry: its [PluginConfig.enabled]
  ///    value wins over the experimental heuristic.
  /// 3. Experimental heuristic: non-experimental plugins are enabled,
  ///    [FeatureFlag.experimental] plugins are disabled.
  bool _isPluginEnabled(Plugin plugin, RuntimeSettings settings) =>
      _enablement.isEnabled(plugin, settings);

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
  ///
  /// Cycle detection now lives on EnablementResolver; PluginRuntime no
  /// longer needs a private forwarder since the only callers moved to the
  /// resolver too.

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
  }) => _enablement.determineEnabledPluginIds(
    settings,
    pluginSubset: pluginSubset,
    additionalEnabledPluginIds: additionalEnabledPluginIds,
  );

  /// Dependency validation also lives on EnablementResolver; no
  /// PluginRuntime private forwarder needed.

  /// Looks up the winner of each pending wildcard, drops any prior override
  /// targeting that winner (unless an explicit plugin-specific override exists)
  /// or [PluginId.winnerScoped] for the same service, then re-emits via
  /// the normalizer's append helper and installs the result via
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
  }) => _normalizer.resolveAndApplyWildcards(
    registry: registry,
    pendingWildcards: pendingWildcards,
    overrides: overrides,
  );

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
  Future<void> updateSettings(RuntimeSettings newSettings) =>
      _updateSettingsImpl(newSettings);

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
    if (_disposed) {
      throw StateError(
        'PluginRuntime.updateSettingsSnapshot() called on a disposed '
        'runtime. Call init() first.',
      );
    }
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
  }) => _updateGlobalSettingsImpl(
    oldSettings: oldSettings,
    newSettings: newSettings,
  );

  /// Dispose runtime: dispose sessions, then detach all global plugins.
  Future<void> dispose() => _disposeImpl();
}
