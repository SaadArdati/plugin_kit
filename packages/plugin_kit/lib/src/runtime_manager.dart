import 'dart:async';

import 'package:plugin_kit/plugin_kit.dart';

/// High-level manager that wraps [PluginRuntime] with settings streaming
/// and convenience accessors.
///
/// Primary entry point for applications using the plugin system. Combines a
/// [PluginRuntime] for plugin lifecycle management, a broadcast stream of
/// [RuntimeSettings] for reactive UI updates, convenience delegation for
/// plugin registration and enablement queries, and coordinated settings
/// updates that reconcile both global and session plugins.
///
/// ```dart
/// final manager = PluginRuntimeManager(plugins: allPlugins);
/// manager.init(
///   initialSettings: savedSettings,
///   defaultEnabledPluginIds: nonExperimentalPluginIds,
/// );
///
/// // Full reconciliation:
/// await manager.updateSettings(newSettings);
///
/// // Snapshot only (no reconciliation):
/// manager.updateSettingsSnapshot(snapshot);
/// ```
///
/// Type parameters: [G] is the global context class (`GlobalPluginContext`
/// or a subtype); [S] is the session context class.
class PluginRuntimeManager<
  G extends GlobalPluginContext,
  S extends SessionPluginContext
> {
  /// The underlying [PluginRuntime] that manages plugin lifecycle.
  ///
  /// Access this directly for advanced operations like settings
  /// reconciliation or global plugin introspection.
  late final PluginRuntime<G, S> runtime;

  /// Construct a manager with an optional inline plugin list.
  ///
  /// Equivalent to constructing and calling [addPlugins] with the same list:
  ///
  /// ```dart
  /// final manager = PluginRuntimeManager(plugins: [FooPlugin(), BarPlugin()]);
  /// ```
  ///
  /// Plugins can still be added later with [addPlugin] or [addPlugins] before
  /// [init] is called.
  PluginRuntimeManager({List<Plugin>? plugins}) {
    runtime = PluginRuntime<G, S>(plugins: plugins);
  }

  final RuntimeSettings _defaultPluginSettings = RuntimeSettings();

  late final _settingsController = StreamController<RuntimeSettings>.broadcast(
    sync: true,
  );

  late RuntimeSettings _settings = _defaultPluginSettings.copyWith();

  /// The current [RuntimeSettings] snapshot.
  RuntimeSettings get settings => _settings;

  set _settingsValue(RuntimeSettings value) {
    _settings = value;
    _settingsController.add(value);
  }

  /// A stream of [RuntimeSettings] that emits whenever settings change.
  ///
  /// This is a broadcast stream. New subscribers will not receive the
  /// current value: read [settings] for the latest snapshot.
  Stream<RuntimeSettings> get settingsStream => _settingsController.stream;

  /// Initialize the runtime with optional default-enabled plugin sets
  /// and an optional custom global-context factory.
  ///
  /// Delegates to [PluginRuntime.init], passing the current [settings]
  /// and the caller-supplied default-enabled set.
  ///
  /// When [defaultEnabledPluginIds] is `null`, plugins are enabled by
  /// default except those marked [FeatureFlag.experimental], which
  /// default off. When provided, only listed plugins are enabled by
  /// default. Explicit [RuntimeSettings.plugins] entries override these
  /// defaults.
  ///
  /// If [initialSettings] is provided, it is applied to the settings
  /// controller before the runtime is initialized.
  ///
  /// [globalContextFactory] is required when [G] is a custom subtype of
  /// [GlobalPluginContext]. Use it to construct your domain-specific
  /// global context with any fields it needs. The factory receives the
  /// runtime's [ServiceRegistry], its global [EventBus], and the list
  /// of active sessions.
  void init({
    RuntimeSettings? initialSettings,
    Set<PluginId>? defaultEnabledPluginIds,
    GlobalContextFactory<G, S>? globalContextFactory,
  }) {
    if (initialSettings != null) {
      _settingsValue = initialSettings;
    }
    runtime.init(
      settings: settings,
      defaultEnabledPluginIds: defaultEnabledPluginIds,
      globalContextFactory: globalContextFactory,
    );
  }

  /// Reset settings to the empty default (all plugins at their default state).
  void resetSettings() {
    _settingsValue = _defaultPluginSettings.copyWith();
  }

  /// Replace the stored settings snapshot and emit it on [settingsStream].
  ///
  /// This does not reconcile plugin enablement, and it does not
  /// push new config into already-resolved services. It only updates
  /// the manager's stored value and notifies stream listeners.
  ///
  /// Use [updateSettings] when you want the runtime to converge on the new
  /// settings (attach, detach, re-inject). Use this method when you only
  /// want to publish a new snapshot to listeners without any lifecycle work.
  void updateSettingsSnapshot(RuntimeSettings value) {
    if (value == _settings) return;
    _settingsValue = value;
  }

  /// Register a plugin. Delegates to [PluginRuntime.addPlugin].
  void addPlugin(Plugin plugin) => runtime.addPlugin(plugin);

  /// Register multiple plugins.
  void addPlugins(List<Plugin> plugins) => runtime.addPlugins(plugins);

  /// Create a session using the runtime's [PluginRuntime.createSession].
  ///
  /// Defaults [settings] to the manager's current [RuntimeSettings] snapshot.
  /// Passes [contextFactory] through to [PluginRuntime.createSession].
  ///
  /// Example:
  /// ```dart
  /// final session = await manager.createSession();
  /// ```
  Future<PluginSession<S>> createSession({
    RuntimeSettings? settings,
    S Function(
      ServiceRegistry registry,
      EventBus sessionBus,
      EventBus globalBus,
    )?
    contextFactory,
  }) {
    return runtime.createSession(
      settings: settings ?? this.settings,
      contextFactory: contextFactory,
    );
  }

  /// Plugins enabled per current settings (settings-intent).
  ///
  /// Reports the base enablement decision: locked + explicit settings +
  /// defaults + experimental heuristic. Does NOT account for dependency
  /// cascade — a plugin whose dependency is disabled remains in this list
  /// even though the runtime has actually disabled it.
  ///
  /// For runtime truth, use [attachedPlugins].
  Iterable<Plugin> get enabledPlugins sync* {
    for (final plugin in runtime.plugins) {
      if (runtime.isPluginEnabled(plugin.pluginId, settings)) yield plugin;
    }
  }

  /// Plugin ids enabled per current settings (settings-intent).
  ///
  /// For runtime truth, use [attachedPluginIds].
  Set<PluginId> get enabledPluginIds => {
    for (final p in enabledPlugins) p.pluginId,
  };

  /// Whether a plugin is enabled per current settings (settings-intent).
  ///
  /// For runtime truth, use [isPluginAttached].
  bool isPluginEnabled(PluginId pluginId) =>
      enabledPluginIds.contains(pluginId);

  /// Plugins currently attached at runtime.
  ///
  /// Distinct from [enabledPlugins], which reports settings-intent
  /// (locked + explicit settings + defaults + experimental heuristic).
  /// `attachedPlugins` reports the post-cascade effective set — plugins
  /// whose dependencies are satisfied AND that the runtime has actually
  /// run `attach` on. A plugin enabled in settings but cascade-disabled
  /// because its dependency is off appears in [enabledPlugins] but NOT
  /// in [attachedPlugins].
  ///
  /// Read this when you need runtime truth (e.g., a UI that shows which
  /// plugins are running). Read [enabledPlugins] when you need settings
  /// truth (e.g., a settings-screen toggle list).
  List<Plugin> get attachedPlugins => [
    for (final plugin in runtime.plugins)
      if (attachedPluginIds.contains(plugin.pluginId)) plugin,
  ];

  /// Plugin ids currently attached at runtime (post-cascade effective set).
  Set<PluginId> get attachedPluginIds {
    final ids = <PluginId>{...runtime.attachedGlobalPluginIds};
    for (final session in runtime.sessions) {
      ids.addAll(session.attachedPluginIds);
    }
    return ids;
  }

  /// Whether [pluginId] is currently attached at runtime.
  bool isPluginAttached(PluginId pluginId) =>
      attachedPluginIds.contains(pluginId);

  /// Reconciles settings across the runtime in serialized order: global
  /// scope first, then each active session sequentially. Updates the stored
  /// settings snapshot only after all reconciliation completes; if any
  /// reconcile throws, the stored snapshot stays at the previous state.
  Future<void> updateSettings(RuntimeSettings newSettings) async {
    final oldSettings = _settings;
    await runtime.updateGlobalSettings(
      oldSettings: oldSettings,
      newSettings: newSettings,
    );
    for (final session in runtime.sessions) {
      await runtime.updateSessionSettings(session, newSettings: newSettings);
    }

    _settingsValue = newSettings;
  }

  /// Dispose the manager, closing the settings stream and disposing the runtime.
  Future<void> dispose() async {
    await runtime.dispose();
    await _settingsController.close();
  }
}
