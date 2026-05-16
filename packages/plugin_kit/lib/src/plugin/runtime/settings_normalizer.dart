import 'package:logging/logging.dart';

import '../../service_registry.dart';
import '../../settings.dart';
import '../../typed_handles.dart';

/// Pure normalizer for [RuntimeSettings]. Strips entries that reference
/// unknown plugin or service ids per the configured
/// [UnknownReferencePolicy], deep-copies plugin/service configs at every
/// boundary (caller-owned maps must not alias runtime-held state), and
/// expands wildcard service pins after the registry knows which plugin
/// wins. Owned by [PluginRuntime]; deliberately importable as a regular
/// library (no part-of) so its inputs are narrow [Set]s and core types
/// only, never the parent runtime.
class SettingsNormalizer {
  /// Creates a normalizer with the given unknown-reference [policy] and
  /// [Logger] for the `logAndSkip` path. The instance is reusable across
  /// many [normalize] calls.
  SettingsNormalizer({required this.policy, required Logger logger})
    : _log = logger;

  /// How references to unknown plugin or service ids should be handled.
  /// See [UnknownReferencePolicy] for the three modes.
  final UnknownReferencePolicy policy;
  final Logger _log;

  /// Returns a normalized copy of [raw] with unknown-id entries handled
  /// per [policy]. Three passes:
  ///
  /// 1. Drop entries from `raw.plugins` whose key is not in
  ///    [allKnownPluginIds].
  /// 2. Drop entries from `raw.services` whose pin's plugin id is not in
  ///    [allKnownPluginIds]. Wildcard pins always survive.
  /// 3. If [registryForServiceIdCheck] is non-null, additionally drop
  ///    service pins whose plugin is in [scopedPluginIds] but did not
  ///    register the named service id. Pass null when called before the
  ///    register-all phase completes.
  ///
  /// Each surviving entry's nested [PluginConfig] / [ServiceSettings]
  /// is detached via `copyWith()` so the result shares no mutable state
  /// with the input.
  RuntimeSettings normalize({
    required String entryPoint,
    required RuntimeSettings raw,
    required Set<PluginId> allKnownPluginIds,
    required Set<PluginId> scopedPluginIds,
    ServiceRegistry? registryForServiceIdCheck,
  }) {
    final shouldFilter = policy != UnknownReferencePolicy.throwError;

    // Pass 1: plugins map.
    final pluginUnknowns = <String>[];
    final outPlugins = <PluginId, PluginConfig>{};
    for (final entry in raw.plugins.entries) {
      final known = allKnownPluginIds.contains(entry.key);
      if (known) {
        outPlugins[entry.key] = entry.value.copyWith();
      } else {
        pluginUnknowns.add(entry.key.toString());
        // Under throwError, keep the entry so the throw context is accurate.
        if (!shouldFilter) outPlugins[entry.key] = entry.value.copyWith();
      }
    }
    _applyUnknownReferencePolicy(
      kind: 'plugin ids in plugins config',
      entryPoint: entryPoint,
      unknowns: pluginUnknowns,
    );

    // Pass 2: services map, plugin-id check.
    final servicePluginUnknowns = <String>[];
    final afterPass2 = <Pin, ServiceSettings>{};
    for (final entry in raw.services.entries) {
      if (entry.key.isWildcard) {
        afterPass2[entry.key] = entry.value.copyWith();
        continue;
      }
      final known = allKnownPluginIds.contains(entry.key.pluginId);
      if (known) {
        afterPass2[entry.key] = entry.value.copyWith();
      } else {
        servicePluginUnknowns.add(
          '${entry.key} (unknown plugin "${entry.key.pluginId}")',
        );
        if (!shouldFilter) afterPass2[entry.key] = entry.value.copyWith();
      }
    }
    _applyUnknownReferencePolicy(
      kind: 'plugin ids in services pin',
      entryPoint: entryPoint,
      unknowns: servicePluginUnknowns,
    );

    // Pass 3: services map, service-id check (post-register only).
    if (registryForServiceIdCheck == null) {
      return RuntimeSettings(plugins: outPlugins, services: afterPass2);
    }

    final knownByPlugin = <PluginId, Set<ServiceId>>{};
    Set<ServiceId> knownFor(PluginId pid) => knownByPlugin.putIfAbsent(
      pid,
      () => registryForServiceIdCheck.listAllServiceIds(pid),
    );

    final serviceIdUnknowns = <String>[];
    final outServices = <Pin, ServiceSettings>{};
    for (final entry in afterPass2.entries) {
      if (entry.key.isWildcard) {
        outServices[entry.key] = entry.value.copyWith();
        continue;
      }
      // plugin ids outside this scope are not validated here; another scope
      // either owns them or has already filtered them.
      if (!scopedPluginIds.contains(entry.key.pluginId)) {
        outServices[entry.key] = entry.value.copyWith();
        continue;
      }
      final hasServiceId = knownFor(
        entry.key.pluginId,
      ).contains(entry.key.serviceId);
      if (hasServiceId) {
        outServices[entry.key] = entry.value.copyWith();
      } else {
        serviceIdUnknowns.add(
          '${entry.key} (plugin "${entry.key.pluginId}" did not register "${entry.key.serviceId}")',
        );
        if (!shouldFilter) outServices[entry.key] = entry.value.copyWith();
      }
    }
    _applyUnknownReferencePolicy(
      kind: 'service ids in services pin',
      entryPoint: entryPoint,
      unknowns: serviceIdUnknowns,
    );

    return RuntimeSettings(plugins: outPlugins, services: outServices);
  }

  /// Validates that every plugin-scoped service pin in [services]
  /// references a plugin id in [knownPluginIds]. Wildcard pins are
  /// always exempt. Unknown ids are surfaced via [policy].
  void validateServiceSettingPluginIds({
    required String entryPoint,
    required Map<Pin, ServiceSettings> services,
    required Set<PluginId> knownPluginIds,
  }) {
    if (services.isEmpty) return;
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

  /// Validates that every key in [plugins] is in [knownPluginIds].
  /// Unknown ids are surfaced via [policy].
  void validatePluginConfigPluginIds({
    required String entryPoint,
    required Map<PluginId, PluginConfig> plugins,
    required Set<PluginId> knownPluginIds,
  }) {
    if (plugins.isEmpty) return;
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

  /// Validates that every plugin-scoped service pin in [services] names a
  /// service id its plugin actually registered with [registry]. Wildcard
  /// pins exempt; out-of-scope plugin ids are skipped (handled by other
  /// passes). Unknown service ids are surfaced via [policy].
  void validateServicePinServiceIds({
    required String entryPoint,
    required ServiceRegistry registry,
    required Map<Pin, ServiceSettings> services,
    required Set<PluginId> scopedPluginIds,
  }) {
    if (services.isEmpty) return;
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

  /// Splits [services] into plugin-specific overrides (appended to
  /// [overrides]) and wildcard pins (stashed in [pendingWildcards] for
  /// [resolveAndApplyWildcards] once plugins have registered).
  /// Plugin-scoped pins whose plugin id is not in [scopedPluginIds] are
  /// ignored (another scope owns them).
  void partitionServiceSettings({
    required Map<Pin, ServiceSettings> services,
    required List<LocalPluginOverride> overrides,
    required Map<ServiceId, ServiceSettings> pendingWildcards,
    required Set<PluginId> scopedPluginIds,
  }) {
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

  /// Looks up the current winner for each entry in [pendingWildcards]
  /// from [registry], drops any prior wildcard-scoped override for that
  /// service id, then appends one row targeting the winning plugin (so
  /// resolution picks up the wildcard's enable/priority/config) and one
  /// `winnerScoped` fallback row (so future winners inherit the wildcard
  /// even if the current winner unregisters). No-op when
  /// [pendingWildcards] is empty.
  void resolveAndApplyWildcards({
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
    // plugin-specific override from partitionServiceSettings. These must
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
      _log.fine(
        'Wildcard override for "$serviceId" resolved to plugin "$winnerPluginId"',
      );

      // Only displace the winner's prior entry when there is no explicit
      // plugin-specific override for this (winner, service) pair. An explicit
      // override from partitionServiceSettings takes precedence over the
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

  void _applyUnknownReferencePolicy({
    required String kind,
    required String entryPoint,
    required List<String> unknowns,
  }) {
    if (unknowns.isEmpty) return;
    switch (policy) {
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
        _log.severe(
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
}
