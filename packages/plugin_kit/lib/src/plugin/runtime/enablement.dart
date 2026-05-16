part of '../plugin.dart';

/// Pure helpers for plugin enablement decisions: default-enabled
/// detection, base enablement from [RuntimeSettings], dependency
/// cascading, and cycle detection. Owned by [PluginRuntime]; cleanly
/// isolated so each helper is callable without runtime mutable state.
class EnablementResolver {
  /// Creates the resolver. No state to initialize; methods are pure
  /// functions over their inputs.
  EnablementResolver();

  /// Whether [plugin] is enabled by default in the absence of any
  /// `RuntimeSettings` override.
  ///
  /// Locked plugins are always on, experimental plugins default off, all
  /// others default on. The Plugins tab uses this to seed UI state, and the
  /// controller uses it to prune no-op overrides from the working draft.
  static bool isEnabledByDefault(Plugin plugin) {
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
  bool isEnabled(Plugin plugin, RuntimeSettings settings) {
    if (plugin.featureFlags.contains(FeatureFlag.locked)) {
      return true;
    }
    final cfgEnabled = settings.plugins[plugin.pluginId]?.enabled;
    if (cfgEnabled != null) return cfgEnabled;
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
  /// Base enablement precedence is documented on [isEnabled]. After
  /// the base pass, plugins whose [Plugin.dependencies] are not satisfied by
  /// [pluginSubset] ∪ [additionalEnabledPluginIds] are disabled via
  /// [validateDependencies]. Locked plugins with unsatisfied dependencies
  /// are kept enabled and logged at severe: per contract they are always
  /// on, so an unmet dependency is a configuration error, not a condition to
  /// silently resolve.
  Set<PluginId> determineEnabledPluginIds(
    RuntimeSettings settings, {
    required List<Plugin> pluginSubset,
    Set<PluginId> additionalEnabledPluginIds = const {},
  }) {
    final enabledPluginIds = <PluginId>{};
    for (final plugin in pluginSubset) {
      if (isEnabled(plugin, settings)) {
        enabledPluginIds.add(plugin.pluginId);
      }
    }

    validateDependencies(
      enabledPluginIds,
      pluginSubset,
      additionalEnabledPluginIds: additionalEnabledPluginIds,
    );

    logDependencyCycles(
      enabledPluginIds,
      pluginSubset,
      additionalEnabledPluginIds: additionalEnabledPluginIds,
    );

    return enabledPluginIds;
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
  void logDependencyCycles(
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
  void validateDependencies(
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
}
