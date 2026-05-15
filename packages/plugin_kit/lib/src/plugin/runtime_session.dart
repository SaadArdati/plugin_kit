part of 'plugin.dart';

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
